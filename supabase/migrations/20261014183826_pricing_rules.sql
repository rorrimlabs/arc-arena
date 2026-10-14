set local check_function_bodies = off;

drop function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
  with time zone);

create table "public"."pricing_rules" (
  "id"             uuid                     not null default gen_random_uuid(),
  "arena_id"       uuid                     not null,
  "name"           text                     not null,
  "priority"       integer                  not null default 0,
  "active"         boolean                  not null default true,
  "days"           smallint[]               not null,
  "start_min"      integer                  not null,
  "end_min"        integer                  not null,
  "holiday_mode"   text                     not null default 'any'::text,
  "valid_from"     date,
  "valid_until"    date,
  "activity_codes" text[]                   not null default '{}'::text[],
  "adjust_kind"    text                     not null,
  "adjust_value"   integer                  not null,
  "created_at"     timestamp with time zone not null default now(),
  "updated_at"     timestamp with time zone not null default now(),
  "sync_xid"       xid8                     not null default pg_current_xact_id(),
  constraint "pricing_rules_adjust_check"
    check
    ((((adjust_kind = 'percent'::text) AND (adjust_value >= '-100'::integer) AND (adjust_value <=
    500) AND (adjust_value <> 0)) OR
    ((adjust_kind = 'per_hour'::text) AND (adjust_value >= '-10000000'::integer) AND (adjust_value
    <= 10000000) AND (adjust_value <> 0)))),
  constraint "pricing_rules_days_check"
    check
    (((cardinality(days) >= 1) AND (days <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint,
    (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint]))),
  constraint "pricing_rules_holiday_mode_check"
    check ((holiday_mode = ANY (ARRAY['any'::text, 'only'::text, 'skip'::text]))),
  constraint "pricing_rules_name_check"
    check (((char_length(name) >= 1) AND (char_length(name) <= 40))),
  constraint "pricing_rules_pkey" primary key (id),
  constraint "pricing_rules_valid_check"
    check (((valid_from IS NULL) OR (valid_until IS NULL) OR (valid_from <= valid_until))),
  constraint "pricing_rules_window_check"
    check (((start_min >= 0) AND (start_min < end_min) AND (end_min <= 1440)))
);

alter table "public"."pricing_rules"
  enable row level security;

create or replace function public._pr_group_bill (
  p_group    uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
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
      q := _pr_quote(v_snap, v_act, g.purchased_controller_count, g.started_at, p_open_end,
        g.started_at);
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
$function$;

create or replace function public._pr_quote (
  s         jsonb,
  p_act     text,
  p_cc      integer,
  p_start   timestamp with time zone,
  p_end     timestamp with time zone,
  p_rule_at timestamp with time zone default null::timestamp with time zone
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
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
  v_rule jsonb;
begin
  if p_end < p_start then return null; end if;
  select a into v_act from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a
   where a->>'code' = p_act limit 1;
  if v_act is null then return null; end if;
  v_rule := _pr_rule(s, p_act, coalesce(p_rule_at, p_start));

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
    v_um := (v_rate->>'unit_minutes')::int;
    v_price := _pr_rule_price((v_rate->>'price_paise')::bigint, v_um, v_rule);
    v_us := v_um::bigint * 60;
    v_sec := _pr_secs(bs[i], be[i]);
    -- Played time counts only the real [p_start, p_end]; the billed piece may run past p_end.
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

    -- Rounding scope: keep the exact numerator over a common denominator so 'session' scope
    -- rounds once (below); 'segment' scope or mixed denominators sum the per-line paise.
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
    'lines', v_lines)
    || case when v_rule is null then '{}'::jsonb
            else jsonb_build_object('rule', jsonb_build_object('name', v_rule->>'name',
              'adjust_kind', v_rule->>'adjust_kind', 'adjust_value', (v_rule->>'adjust_value')::int)) end;
end;
$function$;

create or replace function public._pr_rule (
  s     jsonb,
  p_act text,
  p_at  timestamp with time zone
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  with t as (
    select _pr_ist_date(p_at) as d,
           (extract(epoch from (p_at at time zone 'UTC') + interval '330 minutes'
              - _pr_ist_date(p_at)::timestamp) / 60)::int as m
  )
  select r from t, jsonb_array_elements(coalesce(s->'rules', '[]'::jsonb)) r
   where r->'days' @> to_jsonb(extract(isodow from t.d)::int)
     and t.m >= (r->>'start_min')::int and t.m < (r->>'end_min')::int
     and (r->>'valid_from' is null or t.d >= (r->>'valid_from')::date)
     and (r->>'valid_until' is null or t.d <= (r->>'valid_until')::date)
     and case r->>'holiday_mode'
           when 'only' then coalesce(s->'holidays', '[]'::jsonb) ? t.d::text
           when 'skip' then not coalesce(s->'holidays', '[]'::jsonb) ? t.d::text
           else true end
     and (jsonb_array_length(coalesce(r->'activity_codes', '[]'::jsonb)) = 0
          or r->'activity_codes' ? p_act)
   order by (r->>'priority')::int, r->>'name', r->>'id'
   limit 1;
$function$;

create or replace function public._pr_rule_price (
  p_price        bigint,
  p_unit_minutes integer,
  r              jsonb
)
  returns bigint
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select case
    when r is null then p_price
    when r->>'adjust_kind' = 'percent'
      then greatest(0, _pr_div(p_price * (100 + (r->>'adjust_value')::int), 100))
    -- floor((2n + d) / 2d): half-up also for a negative (discount) value, where _pr_div's
    -- integer division would truncate toward zero.
    else greatest(0, p_price + floor((2 * (r->>'adjust_value')::bigint * p_unit_minutes + 60)::numeric
                                     / 120)::bigint)
  end;
$function$;

create or replace function public._pr_session_bill (
  p_session  uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; v_started timestamptz; seg record; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}'; pol jsonb;
begin
  select pricing_snapshot, started_at into v_snap, v_started from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  for seg in select * from session_segments where session_id = p_session order by idx loop
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      coalesce(seg.ended_at, p_open_end), v_started);   -- pricing rule judged at the session start
    continue when q is null;     -- no rate: contributes nothing (device warns)
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_keys := v_keys || _pr_keys(q, seg.activity_code, seg.resource_id, seg.controller_count);
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')));
end;
$function$;

create or replace function public._pr_sweep (
  v_snap           jsonb,
  p_group          uuid,
  p_res            uuid,
  p_open_end       timestamp with time zone,
  p_no_controllers boolean
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  ws timestamptz[]; we timestamptz[]; wc int[]; wa text[];
  v_pts timestamptz[]; i int; j int; s timestamptz; e timestamptz;
  v_cc int; v_act text; v_n int; q jsonb; v_started timestamptz;
  v_sub bigint := 0; v_keys text[] := '{}';
begin
  select started_at into v_started from group_sessions where id = p_group;
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
    q := _pr_quote(v_snap, v_act, nullif(v_cc, 0), s, e, v_started);   -- rule judged at the group start
    continue when q is null;     -- misconfigured rate: excluded, as on the device
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_keys := v_keys || _pr_keys(q, v_act, p_res, nullif(v_cc, 0));
  end loop;
  return jsonb_build_object('subtotal', v_sub, 'keys', to_jsonb(v_keys));
end;
$function$;

create or replace function public._pricing_canon (
  s jsonb
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
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
        from jsonb_array_elements_text(coalesce(s->'closed_days', '[]'::jsonb)) x), '[]'::jsonb))
  -- Rules only when the snapshot has any, so a rule-free canon is unchanged.
  || coalesce((select jsonb_build_object('rules', jsonb_agg(jsonb_build_object(
        'id', r->>'id', 'name', r->>'name', 'priority', (r->>'priority')::int,
        'days', (select jsonb_agg(distinct d::int order by d::int)
                   from jsonb_array_elements_text(r->'days') d),
        'start_min', (r->>'start_min')::int, 'end_min', (r->>'end_min')::int,
        'holiday_mode', r->>'holiday_mode', 'valid_from', r->>'valid_from',
        'valid_until', r->>'valid_until',
        'activity_codes', coalesce((select jsonb_agg(distinct c order by c)
                   from jsonb_array_elements_text(r->'activity_codes') c), '[]'::jsonb),
        'adjust_kind', r->>'adjust_kind', 'adjust_value', (r->>'adjust_value')::int)
        order by (r->>'priority')::int, r->>'name', r->>'id'))
        from jsonb_array_elements(coalesce(s->'rules', '[]'::jsonb)) r
        having count(*) > 0), '{}'::jsonb);
$function$;

create or replace function public._pricing_snapshot (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
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
        where arena_id = p_arena and closed), '[]'::jsonb))
  -- Active pricing rules, only when there are any: an arena without rules keeps
  -- exactly the snapshot (and canon) floor apps built before rules produce.
  || coalesce((select jsonb_build_object('rules', jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'priority', r.priority, 'days', to_jsonb(r.days),
        'start_min', r.start_min, 'end_min', r.end_min, 'holiday_mode', r.holiday_mode,
        'valid_from', r.valid_from, 'valid_until', r.valid_until,
        'activity_codes', to_jsonb(r.activity_codes), 'adjust_kind', r.adjust_kind,
        'adjust_value', r.adjust_value)
        order by r.priority, r.name, r.id))
        from pricing_rules r where r.arena_id = p_arena and r.active
        having count(*) > 0), '{}'::jsonb);
$function$;

create or replace function public._sync_apply (
  p_arena uuid,
  p_kind  text,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_before jsonb; v_res jsonb;
begin
  -- A price-list change retires the previous catalog into
  -- pricing_catalog_history, so a session priced on it still validates.
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove',
                'rule.upsert', 'rule.delete', 'rule.reorder') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;

  -- Dispatch: one op kind -> one op_* function. Unknown kinds return null and
  -- sync_push rejects them.
  v_res := case p_kind
      when 'session.start'        then op_session_start(p_arena, p)
      when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
      when 'session.extend'       then op_session_extend(p_arena, p)
      when 'session.end'          then op_session_end(p_arena, p)
      when 'session.void'         then op_session_void(p_arena, p)
      when 'payment.record'       then op_payment(p_arena, p)
      when 'payment.correct'      then op_payment_correct(p_arena, p)
      when 'group.create'         then op_group_create(p_arena, p)
      when 'group.add'            then op_group_add(p_arena, p)
      when 'group.switch'         then op_group_switch(p_arena, p)
      when 'group.end_player'     then op_group_end_player(p_arena, p)
      when 'group.extend'         then op_group_extend(p_arena, p)
      when 'group.end'            then op_group_end(p_arena, p)
      when 'group.void'           then op_group_void(p_arena, p)
      when 'controller.move'      then op_controller_move(p_arena, p)
      when 'controller.upsert'    then op_controller_upsert(p_arena, p)
      when 'controller.set_status' then op_controller_set_status(p_arena, p)
      when 'accessory_kind.upsert' then op_accessory_kind_upsert(p_arena, p)
      when 'accessory_kind.remove' then op_accessory_kind_remove(p_arena, p)
      when 'customer.create'      then op_customer_create(p_arena, p)
      when 'customer.update'      then op_customer_update(p_arena, p)
      when 'booking.create'       then op_booking_create(p_arena, p)
      when 'booking.update'       then op_booking_update(p_arena, p)
      when 'booking.set_status'   then op_booking_set_status(p_arena, p)
      when 'game.upsert'          then op_game_upsert(p_arena, p)
      when 'game.set_active'      then op_game_set_active(p_arena, p)
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'rule.upsert'          then op_rule_upsert(p_arena, p)
      when 'rule.delete'          then op_rule_delete(p_arena, p)
      when 'rule.reorder'         then op_rule_reorder(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      else null
    end;

  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$function$;

create or replace function public._sync_sources()
  returns table (
    name text,
    rel  text
  )
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  values
    ('arenas','sync_v_arenas'), ('staff_profiles','staff_profiles'),
    ('activities','activities'), ('resources','resources'),
    ('resource_activities','sync_v_resource_activities'), ('controllers','controllers'),
    ('customers','customers'), ('rates','sync_v_rates'),
    ('billing_policies','billing_policies'), ('holidays','holidays'),
    ('game_categories','game_categories'), ('games','games'),
    ('game_controls','game_controls'), ('game_resources','game_resources'),
    ('bookings','sync_v_bookings'), ('sessions','sessions'),
    ('session_segments','session_segments'), ('session_extensions','session_extensions'),
    ('session_charges','session_charges'), ('payments','payments'),
    ('group_sessions','group_sessions'), ('group_assignments','group_assignments'),
    ('group_extensions','group_extensions'), ('group_charges','group_charges'),
    ('group_payments','group_payments'), ('controller_allocations','controller_allocations'),
    ('controller_moves','controller_moves'), ('settings','settings'),
    ('accessory_kinds','accessory_kinds'), ('pricing_rules','pricing_rules')
$function$;

create or replace function public.op_rule_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from pricing_rules where id = (p->>'id')::uuid and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'rule';
  end if;
  delete from pricing_rules where id = (p->>'id')::uuid and arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_rule_reorder (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_ids uuid[] := _jsonb_uuids(p->'ids');
begin
  perform _need(p_arena, 'settings');
  perform 1 from pricing_rules where arena_id = p_arena for update;
  if not _same_ids(coalesce((select array_agg(id) from pricing_rules where arena_id = p_arena), '{}'),
                   v_ids)
     or cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'stale' using hint = 'the rules were changed on another device';
  end if;
  update pricing_rules r set priority = o.n, updated_at = statement_timestamp()
    from unnest(v_ids) with ordinality o(id, n)
   where r.id = o.id and r.arena_id = p_arena and r.priority <> o.n;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_rule_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_name  text := btrim(coalesce(p->>'name', ''));
  v_days  smallint[] := array(select distinct x::smallint from jsonb_array_elements_text(
                          coalesce(p->'days', '[]'::jsonb)) x order by 1);
  v_codes text[] := array(select distinct upper(btrim(x)) from jsonb_array_elements_text(
                          coalesce(p->'activity_codes', '[]'::jsonb)) x order by 1);
  v_start int := (p->>'start_min')::int;
  v_end   int := (p->>'end_min')::int;
  v_from  date := nullif(p->>'valid_from', '')::date;
  v_until date := nullif(p->>'valid_until', '')::date;
  v_kind  text := p->>'adjust_kind';
  v_value int := (p->>'adjust_value')::int;
  v_bad   text;
  v_prio  int;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from pricing_rules where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'rule';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if cardinality(v_days) = 0 or not v_days <@ array[1,2,3,4,5,6,7]::smallint[]
     or v_start is null or v_end is null or v_start < 0 or v_start >= v_end or v_end > 1440
     or (v_from is not null and v_until is not null and v_until < v_from) then
    raise exception 'invalid_window';
  end if;
  if v_value is null or v_value = 0
     or not ((v_kind = 'percent' and v_value between -100 and 500)
          or (v_kind = 'per_hour' and v_value between -10000000 and 10000000)) then
    raise exception 'invalid_adjustment';
  end if;
  select c into v_bad from unnest(v_codes) c
   where not exists (select 1 from activities where arena_id = p_arena and code = c) limit 1;
  if v_bad is not null then raise exception 'unknown_type' using hint = v_bad; end if;

  select priority into v_prio from pricing_rules where id = v_id for update;
  v_prio := coalesce((p->>'priority')::int, v_prio,
    (select coalesce(max(priority), 0) + 1 from pricing_rules where arena_id = p_arena));

  insert into pricing_rules(id, arena_id, name, priority, active, days, start_min, end_min,
      holiday_mode, valid_from, valid_until, activity_codes, adjust_kind, adjust_value)
    values (v_id, p_arena, v_name, v_prio, coalesce((p->>'active')::boolean, true), v_days,
      v_start, v_end, coalesce(p->>'holiday_mode', 'any'), v_from, v_until, v_codes, v_kind, v_value)
  on conflict (id) do update set
    name = excluded.name, priority = excluded.priority, active = excluded.active,
    days = excluded.days, start_min = excluded.start_min, end_min = excluded.end_min,
    holiday_mode = excluded.holiday_mode, valid_from = excluded.valid_from,
    valid_until = excluded.valid_until, activity_codes = excluded.activity_codes,
    adjust_kind = excluded.adjust_kind, adjust_value = excluded.adjust_value,
    updated_at = statement_timestamp()
  where pricing_rules.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

alter table "public"."pricing_rules"
  add constraint "pricing_rules_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

create index ix_pricing_rules_arena_priority on public.pricing_rules
  using btree (arena_id, priority);

create index ix_pricing_rules_sync on public.pricing_rules using btree (arena_id, sync_xid);

create trigger t_pricing_rules_sync
  before insert or update on public.pricing_rules
  for each row
  execute function public.sync_stamp();

create trigger t_pricing_rules_tomb
  after delete on public.pricing_rules
  for each row
  execute function public.sync_record_delete();

create trigger t_pricing_rules_updated
  before update on public.pricing_rules
  for each row
  execute function public.set_updated_at();

create policy "p_sel_pricing_rules" on "public"."pricing_rules"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

comment on column "public"."pricing_rules"."activity_codes" is 'Station types (activities.code) the rule applies to; empty = every type.';

comment on column "public"."pricing_rules"."adjust_kind" is 'percent: unit price × (100 + adjust_value) / 100; per_hour: unit price + adjust_value paise per 60 minutes of the rate''s unit.';

comment on column "public"."pricing_rules"."adjust_value" is 'Signed: positive raises the price, negative lowers it. Percent −100…500, per_hour in paise; never 0.';

comment on column "public"."pricing_rules"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."pricing_rules"."days" is 'ISO weekdays the rule applies on (1 = Monday … 7 = Sunday), judged on the IST date of the session start.';

comment on column "public"."pricing_rules"."end_min" is 'Window end in minutes after IST midnight (exclusive, at most 1440).';

comment on column "public"."pricing_rules"."holiday_mode" is 'any = holidays do not matter; only = applies only on a listed holiday; skip = never on a listed holiday.';

comment on column "public"."pricing_rules"."priority" is 'Lower wins: when several active rules match a session start, only the lowest priority (then name, then id) applies.';

comment on column "public"."pricing_rules"."start_min" is 'Window start in minutes after IST midnight (inclusive); the session start minute must be in [start_min, end_min).';

comment on column "public"."pricing_rules"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."pricing_rules"."valid_from" is 'First IST date the rule applies (inclusive); null = no start.';

comment on column "public"."pricing_rules"."valid_until" is 'Last IST date the rule applies (inclusive); null = no end.';

comment on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
  with time zone, timestamp with time zone) is 'Pricing: quotes one interval for one activity and controller count on a snapshot (lines, subtotal, cash-rounded amount); port of PricingService.quote.';

comment on function "public"."_pr_rule"(jsonb, text, timestamp
  with time zone) is 'Pricing: the snapshot''s first-priority rule matching an activity started at an instant (IST weekday, minute, dates, holidays), or null.';

comment on function "public"."_pr_rule_price"(bigint, integer, jsonb) is 'Pricing: a unit price after a pricing rule (percent or paise per hour, never below 0).';

comment on function "public"."op_rule_delete"(uuid, jsonb) is 'Sync op rule.delete: deletes a pricing rule; sessions already started keep it in their snapshot.';

comment on function "public"."op_rule_reorder"(uuid, jsonb) is 'Sync op rule.reorder: renumbers every pricing rule of the arena in the given order (first wins).';

comment on function "public"."op_rule_upsert"(uuid, jsonb) is 'Sync op rule.upsert: creates or edits a day/time pricing rule (percent or paise per hour, by session start).';

comment on table "public"."pricing_rules" is 'Day/time price adjustments: the first active match by priority, judged at the session start (IST), changes every unit price of the session by a percent or paise per hour. Part of the pricing snapshot.';

revoke all
  on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
    with time zone, timestamp with time zone)
  from public;

grant execute
  on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
    with time zone, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_rule"(jsonb, text, timestamp with time zone) from public;

grant execute
  on function "public"."_pr_rule"(jsonb, text, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_rule_price"(bigint, integer, jsonb) from public;

grant execute
  on function "public"."_pr_rule_price"(bigint, integer, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_rule_delete"(uuid, jsonb) from public;

grant execute on function "public"."op_rule_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rule_reorder"(uuid, jsonb) from public;

grant execute on function "public"."op_rule_reorder"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rule_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_rule_upsert"(uuid, jsonb) to "postgres", "service_role";

grant select on table "public"."pricing_rules" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."pricing_rules"
  to "postgres", "service_role";
