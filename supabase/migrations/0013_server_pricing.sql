-- 0013 — The server prices every bill itself (docs/SYNC.md "Server-side pricing").
--
-- Until now op_session_end / op_group_end / *_extend stored whatever money the
-- device sent, and op_session_start / op_group_create stored whatever price
-- list it sent. Here:
--   * _pr_quote / _pr_session_bill / _pr_group_bill are a plpgsql port of
--     PricingService, SegmentBilling and GroupBilling (lib/domain). Integer
--     paise and the same rounding rules, so results are exact — no tolerance.
--   * start / create must carry the arena's own price list (live, or replaced
--     within the last 72 h for a device that was offline).
--   * end / extend must carry exactly the server's money, else `price_mismatch`.
-- The 0011 op bodies are kept unchanged under a _v1 name; the new op_* run them
-- first (so permission / stale / floor refusals keep their codes) and then
-- verify. A refusal raised after the body rolls the whole op back through the
-- per-op savepoint in sync_push.

-- =============================================================================
-- Integer money helpers (lib/core/money/rounding.dart)
-- =============================================================================

-- roundDivHalfUp: n / d to the nearest integer, ties up (n >= 0, d > 0).
create or replace function _pr_div(n bigint, d bigint) returns bigint as $$
  select (2 * n + d) / (2 * d);
$$ language sql immutable strict;

create or replace function _pr_ceil_step(v bigint, step int) returns bigint as $$
  select case when step <= 1 then v else ((v + step - 1) / step) * step end;
$$ language sql immutable strict;

create or replace function _pr_round_step(v bigint, step int) returns bigint as $$
  select case when step <= 1 then v else ((v + step / 2) / step) * step end;
$$ language sql immutable strict;

create or replace function _pr_money(v bigint, step int, dir text) returns bigint as $$
  select case when step <= 1 then v
              when dir = 'up' then _pr_ceil_step(v, step)
              else _pr_round_step(v, step) end;
$$ language sql immutable strict;

-- Whole seconds from s to e, truncated (Dart Duration.inSeconds).
create or replace function _pr_secs(s timestamptz, e timestamptz) returns bigint as $$
  select trunc(extract(epoch from e) - extract(epoch from s))::bigint;
$$ language sql immutable strict;

-- =============================================================================
-- IST calendar (lib/core/time) — fixed +05:30, no DST
-- =============================================================================

create or replace function _pr_ist_date(t timestamptz) returns date as $$
  select ((t at time zone 'UTC') + interval '330 minutes')::date;
$$ language sql immutable strict;

-- The happy-hour window of IST day d under snapshot s, or null (closed day,
-- holiday, or no happy hour that weekday). BusinessCalendar.happyWindow.
create or replace function _pr_happy(s jsonb, d date) returns tstzrange as $$
declare
  w jsonb := s->'hours'->'happy'->(extract(isodow from d)::int::text);
  midnight timestamptz := (d::timestamp at time zone 'UTC') - interval '330 minutes';
begin
  if coalesce(s->'holidays', '[]'::jsonb) ? d::text
     or coalesce(s->'closed_days', '[]'::jsonb) ? d::text then
    return null;
  end if;
  if w is null or jsonb_typeof(w) <> 'object' then return null; end if;
  return tstzrange(midnight + make_interval(mins => (w->>'start')::int),
                   midnight + make_interval(mins => (w->>'end')::int), '[)');
end;
$$ language plpgsql immutable;

-- =============================================================================
-- PricingService.quote
-- =============================================================================

-- BillingPolicy.defaults, so a key missing from an old snapshot reads as the
-- device would read it.
create or replace function _pr_policy(s jsonb) returns jsonb as $$
  select '{"billing_unit":"per_minute","block_rounding":"up","grace_minutes":0,
    "minimum_charge_minutes":0,"early_exit":"actual","rounding_scope":"session",
    "late_arrival":"actual","vr_unit_rounding":"up","money_rounding_paise":100,
    "money_rounding_dir":"nearest","payment_timing":"either","allow_extend_past_close":false,
    "cleaning_gap_minutes":0,"group_billing_mode":"per_system"}'::jsonb
    || coalesce(s->'policy', '{}'::jsonb);
$$ language sql immutable;

-- Exact (activity, band, controller count) match; first in snapshot order.
create or replace function _pr_rate(s jsonb, p_act text, p_band text, p_cc int) returns jsonb as $$
  select r from jsonb_array_elements(coalesce(s->'rates', '[]'::jsonb)) with ordinality x(r, n)
   where r->>'activity_code' = p_act and r->>'band' = p_band
     and (r->>'controller_count')::int is not distinct from p_cc
   order by n limit 1;
$$ language sql immutable;

-- Prices [p_start, p_end] for one activity / controller count. Returns
--   {subtotal, amount, lines:[{start, end, band, played_seconds, billed_minutes,
--    units, unit_minutes, unit_price, amount}]}
-- or null where the device gets an error (end before start, no rate) — the
-- caller then leaves the piece unpriced, as SegmentBilling / GroupBilling do.
create or replace function _pr_quote(s jsonb, p_act text, p_cc int, p_start timestamptz, p_end timestamptz)
returns jsonb as $$
declare
  pol jsonb := _pr_policy(s);
  v_act jsonb;
  v_total bigint; v_min bigint; v_bend timestamptz;
  v_pts timestamptz[]; v_d date; v_hw tstzrange; v_mid timestamptz; v_band text;
  bs timestamptz[] := '{}'; be timestamptz[] := '{}'; bb text[] := '{}';
  n int := 0; i int;
  v_rate jsonb; v_price bigint; v_um int; v_us bigint; v_sec bigint; v_played bigint;
  v_num bigint; v_den bigint; v_billed bigint; v_units bigint; v_block int;
  v_sum_num bigint := 0; v_common bigint; v_mixed boolean := false; v_seg_sum bigint := 0;
  v_amount bigint; v_sub bigint;
  v_lines jsonb := '[]'::jsonb;
begin
  if p_end < p_start then return null; end if;
  select a into v_act from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a
   where a->>'code' = p_act limit 1;
  if v_act is null then return null; end if;

  v_total := _pr_secs(p_start, p_end);
  -- Grace: free when under the grace period.
  if v_total <= (pol->>'grace_minutes')::int * 60 then
    return jsonb_build_object('subtotal', 0, 'amount', 0, 'lines', '[]'::jsonb);
  end if;
  -- Minimum charge: bill at least this much by extending the billed interval.
  v_min := (pol->>'minimum_charge_minutes')::int * 60;
  v_bend := case when v_total < v_min then p_start + make_interval(secs => v_min) else p_end end;

  -- Band segments: split at every happy-hour boundary, label by midpoint, merge.
  if not coalesce((v_act->>'happy_eligible')::boolean, false) then
    bs := array[p_start]; be := array[v_bend]; bb := array['standard']; n := 1;
  else
    v_pts := array[p_start, v_bend];
    v_d := _pr_ist_date(p_start);
    while v_d <= _pr_ist_date(v_bend) loop
      v_hw := _pr_happy(s, v_d);
      if v_hw is not null then
        if lower(v_hw) > p_start and lower(v_hw) < v_bend then v_pts := v_pts || lower(v_hw); end if;
        if upper(v_hw) > p_start and upper(v_hw) < v_bend then v_pts := v_pts || upper(v_hw); end if;
      end if;
      v_d := v_d + 1;
    end loop;
    select array_agg(distinct x order by x) into v_pts from unnest(v_pts) x;
    for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
      continue when v_pts[i + 1] <= v_pts[i];
      v_mid := v_pts[i] + (v_pts[i + 1] - v_pts[i]) / 2;
      v_hw := _pr_happy(s, _pr_ist_date(v_mid));
      v_band := case when v_hw is not null and v_hw @> v_mid then 'happy' else 'standard' end;
      if n > 0 and bb[n] = v_band then
        be[n] := v_pts[i + 1];
      else
        n := n + 1; bs[n] := v_pts[i]; be[n] := v_pts[i + 1]; bb[n] := v_band;
      end if;
    end loop;
  end if;

  for i in 1 .. n loop
    v_rate := _pr_rate(s, p_act, bb[i], p_cc);
    if v_rate is null and bb[i] = 'happy' then
      v_rate := _pr_rate(s, p_act, 'standard', p_cc);   -- happy → standard fallback
    end if;
    if v_rate is null then return null; end if;
    v_price := (v_rate->>'price_paise')::bigint;
    v_um := (v_rate->>'unit_minutes')::int;
    v_us := v_um::bigint * 60;
    v_sec := _pr_secs(bs[i], be[i]);
    v_played := case when least(p_end, be[i]) > greatest(p_start, bs[i])
                     then _pr_secs(greatest(p_start, bs[i]), least(p_end, be[i])) else 0 end;
    v_units := 0;
    if v_act->>'duration_model' = 'unit' then
      case pol->>'vr_unit_rounding'
        when 'prorate' then
          v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
        when 'nearest' then
          v_units := _pr_div(v_sec, v_us);
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
        else -- up
          v_units := (v_sec + v_us - 1) / v_us;
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
      end case;
    elsif pol->>'billing_unit' = 'per_minute' then
      v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
    else
      v_block := case pol->>'billing_unit' when 'block_15' then 15 when 'block_30' then 30 else 60 end;
      v_billed := (v_sec + 59) / 60;   -- whole minutes first
      v_billed := case when pol->>'block_rounding' = 'up' then _pr_ceil_step(v_billed, v_block)
                       else _pr_round_step(v_billed, v_block) end;
      v_num := v_price * v_billed; v_den := v_um;
    end if;

    v_common := coalesce(v_common, v_den);
    if v_den <> v_common then v_mixed := true; end if;
    v_sum_num := v_sum_num + v_num;
    v_amount := _pr_div(v_num, v_den);
    v_seg_sum := v_seg_sum + v_amount;
    v_lines := v_lines || jsonb_build_object('start', bs[i], 'end', be[i], 'band', bb[i],
      'played_seconds', v_played, 'billed_minutes', v_billed, 'units', v_units,
      'unit_minutes', v_um, 'unit_price', v_price, 'amount', v_amount);
  end loop;

  v_sub := case when pol->>'rounding_scope' = 'segment' or v_mixed then v_seg_sum
                else _pr_div(v_sum_num, coalesce(v_common, 1)) end;
  return jsonb_build_object('subtotal', v_sub,
    'amount', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'lines', v_lines);
end;
$$ language plpgsql immutable;

-- One charge row's money-relevant identity, for comparing device and server
-- rows as multisets (ids and ordering are the device's business).
create or replace function _pr_charge_key(p_act text, p_res uuid, p_cc int, p_band text,
  p_start timestamptz, p_end timestamptz, p_played bigint, p_billed bigint, p_um int,
  p_price bigint, p_amount bigint) returns text as $$
  select concat_ws('|', p_act, coalesce(p_res::text, '-'), coalesce(p_cc::text, '-'), p_band,
    (extract(epoch from p_start) * 1000000)::bigint, (extract(epoch from p_end) * 1000000)::bigint,
    p_played, p_billed, p_um, p_price, p_amount);
$$ language sql immutable;

-- Appends one quote's charge keys.
create or replace function _pr_keys(q jsonb, p_act text, p_res uuid, p_cc int) returns text[] as $$
  select coalesce(array_agg(_pr_charge_key(p_act, p_res, p_cc, l->>'band',
      (l->>'start')::timestamptz, (l->>'end')::timestamptz, (l->>'played_seconds')::bigint / 60,
      (l->>'billed_minutes')::bigint, (l->>'unit_minutes')::int, (l->>'unit_price')::bigint,
      (l->>'amount')::bigint)), '{}')
    from jsonb_array_elements(q->'lines') l;
$$ language sql immutable;

-- =============================================================================
-- SegmentBilling.bill — a single session over all its segments
-- =============================================================================

-- {total, subtotal, keys (sorted)}. An open segment is priced up to p_open_end.
create or replace function _pr_session_bill(p_session uuid, p_open_end timestamptz) returns jsonb as $$
declare
  v_snap jsonb; seg record; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}'; pol jsonb;
begin
  select pricing_snapshot into v_snap from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  for seg in select * from session_segments where session_id = p_session order by idx loop
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      coalesce(seg.ended_at, p_open_end));
    continue when q is null;     -- no rate: contributes nothing (device warns)
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_keys := v_keys || _pr_keys(q, seg.activity_code, seg.resource_id, seg.controller_count);
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')));
end;
$$ language plpgsql stable security definer set search_path = public;

-- =============================================================================
-- GroupBilling.bill
-- =============================================================================

-- Sweeps one station's assignments, splitting at every controller-count change
-- (p_no_controllers: only assignments without controllers — pooled mode).
-- Returns {subtotal, keys}.
create or replace function _pr_sweep(v_snap jsonb, p_group uuid, p_res uuid,
  p_open_end timestamptz, p_no_controllers boolean) returns jsonb as $$
declare
  ws timestamptz[]; we timestamptz[]; wc int[]; wa text[];
  v_pts timestamptz[]; i int; j int; s timestamptz; e timestamptz;
  v_cc int; v_act text; v_n int; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}';
begin
  -- Windows in the device's list order (player, then index); empty ones dropped.
  select coalesce(array_agg(started_at order by player_number, idx), '{}'),
         coalesce(array_agg(coalesce(ended_at, p_open_end) order by player_number, idx), '{}'),
         coalesce(array_agg(controller_count order by player_number, idx), '{}'),
         coalesce(array_agg(activity_code order by player_number, idx), '{}')
    into ws, we, wc, wa
    from group_assignments
   where group_id = p_group and resource_id = p_res
     and (not p_no_controllers or controller_count is null)
     and coalesce(ended_at, p_open_end) > started_at;
  select array_agg(distinct x order by x) into v_pts
    from (select unnest(ws) as x union all select unnest(we)) t;
  for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
    s := v_pts[i]; e := v_pts[i + 1];
    continue when e <= s;
    v_n := 0; v_cc := 0; v_act := null;
    for j in 1 .. coalesce(array_length(ws, 1), 0) loop
      if ws[j] <= s and we[j] >= e then
        v_n := v_n + 1;
        v_cc := v_cc + coalesce(wc[j], 0);
        v_act := coalesce(v_act, wa[j]);
      end if;
    end loop;
    continue when v_n = 0;
    q := _pr_quote(v_snap, v_act, nullif(v_cc, 0), s, e);
    continue when q is null;     -- misconfigured rate: excluded, as on the device
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_keys := v_keys || _pr_keys(q, v_act, p_res, nullif(v_cc, 0));
  end loop;
  return jsonb_build_object('subtotal', v_sub, 'keys', to_jsonb(v_keys));
end;
$$ language plpgsql stable security definer set search_path = public;

create or replace function _pr_group_bill(p_group uuid, p_open_end timestamptz) returns jsonb as $$
declare
  g group_sessions; v_snap jsonb; pol jsonb; r uuid; part jsonb; q jsonb; v_act text;
  v_sub bigint := 0; v_keys text[] := '{}';
begin
  select * into g from group_sessions where id = p_group;
  v_snap := g.pricing_snapshot;
  pol := _pr_policy(v_snap);
  if g.billing_mode = 'shared_controller_pool' then
    -- The purchased controllers, once, over the whole group window.
    select activity_code into v_act from group_assignments
     where group_id = p_group and controller_count is not null
     order by player_number, idx limit 1;
    if g.purchased_controller_count > 0 and v_act is not null and p_open_end > g.started_at then
      q := _pr_quote(v_snap, v_act, g.purchased_controller_count, g.started_at, p_open_end);
      if q is not null then
        v_sub := v_sub + (q->>'subtotal')::bigint;
        v_keys := v_keys || _pr_keys(q, v_act, null, g.purchased_controller_count);
      end if;
    end if;
  end if;
  for r in select distinct resource_id from group_assignments where group_id = p_group loop
    part := _pr_sweep(v_snap, p_group, r, p_open_end, g.billing_mode = 'shared_controller_pool');
    v_sub := v_sub + (part->>'subtotal')::bigint;
    v_keys := v_keys || array(select jsonb_array_elements_text(part->'keys'));
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')));
end;
$$ language plpgsql stable security definer set search_path = public;

-- =============================================================================
-- The price list: what a device's snapshot must be
-- =============================================================================

-- The arena's current price list in PricingSnapshot.toJson() shape — exactly
-- what a device whose catalog is in sync would freeze into a new session.
create or replace function _pricing_snapshot(p_arena uuid) returns jsonb as $$
  select jsonb_build_object(
    'rate_card_name', 'Current',
    'rates', coalesce((select jsonb_agg(jsonb_build_object('activity_code', activity_code,
        'band', band, 'controller_count', controller_count, 'unit_minutes', unit_minutes,
        'price_paise', price_paise)) from sync_v_rates where arena_id = p_arena), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', code,
        'duration_model', duration_model, 'happy_eligible', happy_hour_eligible))
        from activities where arena_id = p_arena), '[]'::jsonb),
    'policy', coalesce((select jsonb_build_object('billing_unit', billing_unit,
        'block_rounding', block_rounding, 'grace_minutes', grace_minutes,
        'minimum_charge_minutes', minimum_charge_minutes, 'early_exit', early_exit,
        'rounding_scope', rounding_scope, 'late_arrival', late_arrival,
        'vr_unit_rounding', vr_unit_rounding, 'money_rounding_paise', money_rounding_paise,
        'money_rounding_dir', money_rounding_dir, 'payment_timing', payment_timing,
        'allow_extend_past_close', allow_extend_past_close,
        'cleaning_gap_minutes', cleaning_gap_minutes, 'group_billing_mode', group_billing_mode)
        from billing_policies where arena_id = p_arena and active order by created_at limit 1),
        _pr_policy('{}'::jsonb)),
    -- BusinessHours.current() when the owner never saved hours.
    'hours', coalesce((select json from settings where arena_id = p_arena and key = 'business_hours'),
      '{"open":{"1":null,"2":{"start":840,"end":1380},"3":{"start":840,"end":1380},
                "4":{"start":840,"end":1380},"5":{"start":840,"end":1380},
                "6":{"start":840,"end":1380},"7":{"start":840,"end":1380}},
        "happy":{"1":null,"2":{"start":840,"end":1020},"3":{"start":840,"end":1020},
                 "4":{"start":840,"end":1020},"5":{"start":840,"end":1020},"6":null,"7":null}}'::jsonb),
    'holidays', coalesce((select jsonb_agg(day::text) from holidays where arena_id = p_arena), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(day::text) from holidays
        where arena_id = p_arena and closed), '[]'::jsonb));
$$ language sql stable security definer set search_path = public;

-- A snapshot reduced to what pricing depends on, in a fixed order: the card
-- name and list order are ignored, absent keys read as the device reads them.
create or replace function _pricing_canon(s jsonb) returns jsonb as $$
  select jsonb_build_object(
    'rates', coalesce((select jsonb_agg(jsonb_build_object('a', r->>'activity_code',
        'b', r->>'band', 'c', (r->>'controller_count')::int, 'u', (r->>'unit_minutes')::int,
        'p', (r->>'price_paise')::bigint)
        order by r->>'activity_code', r->>'band', coalesce((r->>'controller_count')::int, -1),
                 (r->>'unit_minutes')::int, (r->>'price_paise')::bigint)
        from jsonb_array_elements(coalesce(s->'rates', '[]'::jsonb)) r), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', a->>'code',
        'model', a->>'duration_model', 'happy', (a->>'happy_eligible')::boolean)
        order by a->>'code', a->>'duration_model')
        from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a), '[]'::jsonb),
    'policy', _pr_policy(s),
    'hours', (select jsonb_object_agg(kind, (select jsonb_object_agg(d::text,
        case when jsonb_typeof(s->'hours'->kind->(d::text)) = 'object'
             then jsonb_build_object('start', (s->'hours'->kind->(d::text)->>'start')::int,
                                     'end', (s->'hours'->kind->(d::text)->>'end')::int)
             else 'null'::jsonb end) from generate_series(1, 7) d))
        from unnest(array['open', 'happy']) kind),
    'holidays', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'holidays', '[]'::jsonb)) x), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'closed_days', '[]'::jsonb)) x), '[]'::jsonb));
$$ language sql immutable;

-- Price lists an owner replaced, kept so a device that started a session
-- offline on the old list is not refused. Server-only (no client access).
create table pricing_catalog_history (
  arena_id   uuid not null references arenas(id) on delete cascade,
  canon      jsonb not null,
  canon_md5  text generated always as (md5(canon::text)) stored,
  retired_at timestamptz not null,
  primary key (arena_id, canon_md5)
);
alter table pricing_catalog_history enable row level security;
revoke all on pricing_catalog_history from anon, authenticated;

-- How long a replaced price list is still accepted at session start.
create or replace function _pricing_grace() returns interval as $$
  select interval '72 hours';
$$ language sql immutable;

create or replace function _assert_snapshot(p_arena uuid, s jsonb) returns void as $$
declare c jsonb := _pricing_canon(s);
begin
  if s is null or jsonb_typeof(s) <> 'object' then
    raise exception 'pricing_snapshot_mismatch' using hint = 'no price list was sent';
  end if;
  if c = _pricing_canon(_pricing_snapshot(p_arena)) then return; end if;
  if exists (select 1 from pricing_catalog_history
              where arena_id = p_arena and canon_md5 = md5(c::text) and canon = c
                and retired_at >= statement_timestamp() - _pricing_grace()) then
    return;
  end if;
  raise exception 'pricing_snapshot_mismatch'
    using hint = 'the price list on this device is not the arena''s; sync and start again';
end;
$$ language plpgsql stable security definer set search_path = public;

-- =============================================================================
-- Ops: keep the 0011 bodies, verify afterwards
-- =============================================================================

alter function op_session_start(uuid, jsonb)  rename to _op_session_start_v1;
alter function op_session_extend(uuid, jsonb) rename to _op_session_extend_v1;
alter function op_session_end(uuid, jsonb)    rename to _op_session_end_v1;
alter function op_group_create(uuid, jsonb)   rename to _op_group_create_v1;
alter function op_group_extend(uuid, jsonb)   rename to _op_group_extend_v1;
alter function op_group_end(uuid, jsonb)      rename to _op_group_end_v1;
alter function _sync_apply(uuid, text, jsonb) rename to _sync_apply_v1;

create or replace function _price_mismatch(p_what text, p_server bigint, p_device bigint) returns void as $$
begin
  raise exception 'price_mismatch'
    using hint = format('%s: server %s paise, device %s paise', p_what, p_server,
                        coalesce(p_device::text, 'none'));
end;
$$ language plpgsql immutable;

create or replace function op_session_start(p_arena uuid, p jsonb) returns jsonb as $$
declare v_res jsonb := _op_session_start_v1(p_arena, p);
begin
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function op_group_create(p_arena uuid, p jsonb) returns jsonb as $$
declare v_res jsonb := _op_group_create_v1(p_arena, p);
begin
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  if coalesce(nullif(p->>'billing_mode', ''), 'per_system')
     <> _pr_policy(p->'pricing_snapshot')->>'group_billing_mode' then
    raise exception 'pricing_snapshot_mismatch'
      using hint = 'billing_mode differs from the price list''s group billing mode';
  end if;
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

-- The device prices an extension as quote(start → new end) − quote(start → old
-- end) over the open segment's config (SessionPlanner.planExtension).
create or replace function op_session_extend(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_res jsonb := _op_session_extend_v1(p_arena, p);
  v_session uuid := (p->>'session_id')::uuid;
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_snap jsonb; v_start timestamptz; v_act text; v_cc int; q_old jsonb; q_new jsonb; v_added bigint;
begin
  select pricing_snapshot, started_at into v_snap, v_start from sessions where id = v_session;
  select activity_code, controller_count into v_act, v_cc from session_segments
   where session_id = v_session order by (ended_at is null) desc, idx desc limit 1;
  q_old := _pr_quote(v_snap, v_act, v_cc, v_start, v_old);
  q_new := _pr_quote(v_snap, v_act, v_cc, v_start, v_new);
  if q_old is null or q_new is null then
    raise exception 'no_rate' using hint = 'the session''s price list has no rate for this extension';
  end if;
  v_added := (q_new->>'amount')::bigint - (q_old->>'amount')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

-- GroupSessionActions.previewExtension: subtotal at the new end − at the old.
create or replace function op_group_extend(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_res jsonb := _op_group_extend_v1(p_arena, p);
  v_group uuid := (p->>'group_id')::uuid;
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_added bigint;
begin
  v_added := (_pr_group_bill(v_group, v_new)->>'subtotal')::bigint
           - (_pr_group_bill(v_group, v_old)->>'subtotal')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

-- After the 0011 body every segment is closed at ended_at and the device's
-- charge rows are stored; both must be the server's own bill.
create or replace function op_session_end(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_session uuid := (p->>'session_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_res jsonb; v_bill jsonb; v_keys text[];
begin
  v_res := _op_session_end_v1(p_arena, p);   -- permission, stale, then the writes
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended);
  if (v_bill->>'total')::bigint is distinct from (p->>'billed_amount_paise')::bigint then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, (p->>'billed_amount_paise')::bigint);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from session_charges where session_id = v_session) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function op_group_end(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_res jsonb; v_bill jsonb; v_keys text[];
begin
  v_res := _op_group_end_v1(p_arena, p);     -- permission, stale, then the writes
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  v_bill := _pr_group_bill(v_group, v_ended);
  if (v_bill->>'total')::bigint is distinct from (p->>'billed_amount_paise')::bigint then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, (p->>'billed_amount_paise')::bigint);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from group_charges where group_id = v_group) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

-- Every owner edit that can change the price list records the list it
-- replaced, so starts frozen on it stay acceptable for _pricing_grace().
create or replace function _sync_apply(p_arena uuid, p_kind text, p jsonb) returns jsonb as $$
declare v_before jsonb; v_res jsonb;
begin
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;
  v_res := _sync_apply_v1(p_arena, p_kind, p);
  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Grants: all internal, reachable only through sync_push
-- =============================================================================

do $$
declare f text;
begin
  foreach f in array array[
    '_pr_div(bigint,bigint)','_pr_ceil_step(bigint,int)','_pr_round_step(bigint,int)',
    '_pr_money(bigint,int,text)','_pr_secs(timestamptz,timestamptz)','_pr_ist_date(timestamptz)',
    '_pr_happy(jsonb,date)','_pr_policy(jsonb)','_pr_rate(jsonb,text,text,int)',
    '_pr_quote(jsonb,text,int,timestamptz,timestamptz)',
    '_pr_charge_key(text,uuid,int,text,timestamptz,timestamptz,bigint,bigint,int,bigint,bigint)',
    '_pr_keys(jsonb,text,uuid,int)','_pr_session_bill(uuid,timestamptz)',
    '_pr_sweep(jsonb,uuid,uuid,timestamptz,boolean)','_pr_group_bill(uuid,timestamptz)',
    '_pricing_snapshot(uuid)','_pricing_canon(jsonb)','_pricing_grace()',
    '_assert_snapshot(uuid,jsonb)','_price_mismatch(text,bigint,bigint)',
    'op_session_start(uuid,jsonb)','op_session_extend(uuid,jsonb)','op_session_end(uuid,jsonb)',
    'op_group_create(uuid,jsonb)','op_group_extend(uuid,jsonb)','op_group_end(uuid,jsonb)',
    '_sync_apply(uuid,text,jsonb)'
  ] loop
    execute format('revoke execute on function %s from anon, public, authenticated', f);
  end loop;
end $$;
