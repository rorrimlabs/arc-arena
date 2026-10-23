set local check_function_bodies = off;

drop function "public"."_pr_group_bill"(uuid, timestamp with time zone);

drop function "public"."_pr_session_bill"(uuid, timestamp with time zone);

drop function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean);

create or replace function public._pr_group_bill (
  p_group    uuid,
  p_open_end timestamp with time zone,
  p_until    timestamp with time zone default null::timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  g group_sessions; v_snap jsonb; pol jsonb; r uuid; part jsonb; q jsonb; v_act text;
  v_sub bigint := 0; v_keys text[] := '{}'; v_by jsonb := '{}'::jsonb; v_k text;
begin
  select * into g from group_sessions where id = p_group;
  v_snap := g.pricing_snapshot;
  pol := _pr_policy(v_snap);
  if g.billing_mode = 'shared_controller_pool' then
    -- The purchased controllers, once, over the whole group window.
    select activity_code into v_act from group_assignments
     where group_id = p_group and controller_count is not null
     order by player_number, idx limit 1;
    if g.purchased_controller_count > 0 and v_act is not null
       and least(p_open_end, coalesce(p_until, 'infinity')) > g.started_at then
      q := _pr_quote(v_snap, v_act, g.purchased_controller_count, g.started_at,
        least(p_open_end, coalesce(p_until, 'infinity')), g.started_at);
      if q is not null then
        v_sub := v_sub + (q->>'subtotal')::bigint;
        v_by := jsonb_set(v_by, array[v_act], to_jsonb(coalesce((v_by->>v_act)::bigint, 0) + (q->>'subtotal')::bigint));
        v_keys := v_keys || _pr_keys(q, v_act, null, g.purchased_controller_count);
      end if;
    end if;
  end if;
  for r in select distinct resource_id from group_assignments where group_id = p_group loop
    part := _pr_sweep(v_snap, p_group, r, p_open_end, g.billing_mode = 'shared_controller_pool',
      p_until);
    v_sub := v_sub + (part->>'subtotal')::bigint;
    v_keys := v_keys || array(select jsonb_array_elements_text(part->'keys'));
    for v_k in select jsonb_object_keys(part->'by_activity') loop
      v_by := jsonb_set(v_by, array[v_k], to_jsonb(coalesce((v_by->>v_k)::bigint, 0) + (part->'by_activity'->>v_k)::bigint));
    end loop;
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')),
    'by_activity', v_by);
end;
$function$;

create or replace function public._pr_session_bill (
  p_session         uuid,
  p_open_end        timestamp with time zone,
  p_charge_overtime boolean                  default false
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; v_started timestamptz; seg record; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}'; pol jsonb; v_by jsonb := '{}'::jsonb;
  v_sched timestamptz; v_last timestamptz; v_until timestamptz; v_end timestamptz;
begin
  select pricing_snapshot, started_at, scheduled_end_at into v_snap, v_started, v_sched
    from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  select max(coalesce(ended_at, p_open_end)) into v_last
    from session_segments where session_id = p_session;
  -- Played past the booked end: bill to the booked end only, unless overtime is charged.
  if v_last > v_sched and not coalesce(p_charge_overtime, false) then
    v_until := v_sched;
  end if;
  for seg in select * from session_segments where session_id = p_session order by idx loop
    v_end := coalesce(seg.ended_at, p_open_end);
    if v_until is not null then
      continue when seg.started_at >= v_until;   -- wholly inside the forgiven overtime
      v_end := least(v_end, v_until);
    end if;
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      v_end, v_started);   -- pricing rule judged at the session start
    continue when q is null;     -- no rate: contributes nothing (device warns)
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_by := jsonb_set(v_by, array[seg.activity_code], to_jsonb(coalesce((v_by->>seg.activity_code)::bigint, 0) + (q->>'subtotal')::bigint));
    v_keys := v_keys || _pr_keys(q, seg.activity_code, seg.resource_id, seg.controller_count);
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')),
    'by_activity', v_by);
end;
$function$;

create or replace function public._pr_sweep (
  v_snap           jsonb,
  p_group          uuid,
  p_res            uuid,
  p_open_end       timestamp with time zone,
  p_no_controllers boolean,
  p_until          timestamp with time zone default null::timestamp with time zone
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
  v_sub bigint := 0; v_keys text[] := '{}'; v_by jsonb := '{}'::jsonb;
begin
  select started_at into v_started from group_sessions where id = p_group;
  -- Windows in the device's list order (player, then index); empty ones dropped.
  select coalesce(array_agg(started_at order by player_number, idx), '{}'),
         coalesce(array_agg(least(coalesce(ended_at, p_open_end), coalesce(p_until, 'infinity'))
           order by player_number, idx), '{}'),
         coalesce(array_agg(controller_count order by player_number, idx), '{}'),
         coalesce(array_agg(activity_code order by player_number, idx), '{}')
    into ws, we, wc, wa
    from group_assignments
   where group_id = p_group and resource_id = p_res
     and (not p_no_controllers or controller_count is null)
     and least(coalesce(ended_at, p_open_end), coalesce(p_until, 'infinity')) > started_at;
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
    v_by := jsonb_set(v_by, array[v_act], to_jsonb(coalesce((v_by->>v_act)::bigint, 0) + (q->>'subtotal')::bigint));
    v_keys := v_keys || _pr_keys(q, v_act, p_res, nullif(v_cc, 0));
  end loop;
  return jsonb_build_object('subtotal', v_sub, 'keys', to_jsonb(v_keys), 'by_activity', v_by);
end;
$function$;

create or replace function public.op_group_end (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_end timestamptz; v_ids uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[]; v_disc bigint := 0; v_total bigint; pol jsonb;
begin
  perform _need(p_arena, 'bill');
  perform _client_time(p_arena, v_ended, 'ended_at');
  if v_waive then
    perform _need(p_arena, 'discount');
    if nullif(btrim(coalesce(p->>'waive_reason', '')), '') is null then
      raise exception 'waive_reason_required';
    end if;
  end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the group was changed on another device';
  end if;
  update group_assignments set ended_at = v_ended where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = v_ended where group_id = v_group and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into group_charges(id, arena_id, group_id, assignment_id, player_number, charge_index,
        band_code, activity_code, resource_id, controller_count, segment_start, segment_end,
        played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_group, nullif(v_c->>'assignment_id','')::uuid,
        nullif(v_c->>'player_number','')::int, (v_c->>'charge_index')::int, v_c->>'band_code',
        v_c->>'activity_code', nullif(v_c->>'resource_id','')::uuid,
        nullif(v_c->>'controller_count','')::int, (v_c->>'segment_start')::timestamptz,
        (v_c->>'segment_end')::timestamptz, (v_c->>'played_minutes')::int,
        (v_c->>'billed_minutes')::int, (v_c->>'unit_minutes')::int,
        (v_c->>'unit_price_paise')::bigint, (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_group;
  -- Payments may already have been taken against the running bill.
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now,
      ended_recorded_at = v_now
    where id = v_group;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason, required: waive_reason_required).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'group_session', v_group, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored assignments
  -- and refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  -- Overtime is billed only when staff chose to (charge_overtime): else capped at the booked end.
  v_bill := _pr_group_bill(v_group, v_ended,
    case when coalesce((p->>'charge_overtime')::boolean, false) then null else v_end end);
  v_total := (v_bill->>'total')::bigint;
  -- A discount (preset, coupon or manual) comes off the subtotal before cash rounding.
  if jsonb_typeof(p->'discount') = 'object' then
    if v_waive then raise exception 'invalid_discount' using hint = 'a waived bill takes no discount'; end if;
    v_disc := _discount_apply(p_arena, p->'discount', v_bill, v_ended,
      null, v_group);
    select _pr_policy(pricing_snapshot) into pol from group_sessions where id = v_group;
    v_total := _pr_money((v_bill->>'subtotal')::bigint - v_disc, (pol->>'money_rounding_paise')::int,
      pol->>'money_rounding_dir');
  end if;
  -- Below owner level a waive is capped like a manual discount.
  if v_waive then perform _waive_check(p_arena, v_billed, v_paid); end if;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from group_charges where group_id = v_group) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_session_end (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_status text; v_end timestamptz; v_segs uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[]; v_disc bigint := 0; v_total bigint; pol jsonb;
begin
  perform _need(p_arena, 'bill');
  perform _client_time(p_arena, v_ended, 'ended_at');
  if v_waive then
    perform _need(p_arena, 'discount');
    if nullif(btrim(coalesce(p->>'waive_reason', '')), '') is null then
      raise exception 'waive_reason_required';
    end if;
  end if;
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select coalesce(array_agg(id), '{}') into v_segs from session_segments where session_id = v_session;
  if not _same_ids(v_segs, _jsonb_uuids(p->'expected_segment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;

  update session_segments set ended_at = v_ended where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = v_ended where session_id = v_session and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into session_charges(id, arena_id, session_id, segment_id, segment_index, band_code,
        activity_code, resource_id, controller_count, segment_start, segment_end, played_minutes,
        billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_session, nullif(v_c->>'segment_id','')::uuid,
        (v_c->>'segment_index')::int, v_c->>'band_code', v_c->>'activity_code',
        nullif(v_c->>'resource_id','')::uuid, nullif(v_c->>'controller_count','')::int,
        (v_c->>'segment_start')::timestamptz, (v_c->>'segment_end')::timestamptz,
        (v_c->>'played_minutes')::int, (v_c->>'billed_minutes')::int,
        (v_c->>'unit_minutes')::int, (v_c->>'unit_price_paise')::bigint,
        (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_session;
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now,
      ended_recorded_at = v_now
    where id = v_session;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason, required: waive_reason_required).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'session', v_session, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored segments and
  -- refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended, coalesce((p->>'charge_overtime')::boolean, false));
  v_total := (v_bill->>'total')::bigint;
  -- A discount (preset, coupon or manual) comes off the subtotal before cash rounding.
  if jsonb_typeof(p->'discount') = 'object' then
    if v_waive then raise exception 'invalid_discount' using hint = 'a waived bill takes no discount'; end if;
    v_disc := _discount_apply(p_arena, p->'discount', v_bill, v_ended,
      v_session, null);
    select _pr_policy(pricing_snapshot) into pol from sessions where id = v_session;
    v_total := _pr_money((v_bill->>'subtotal')::bigint - v_disc, (pol->>'money_rounding_paise')::int,
      pol->>'money_rounding_dir');
  end if;
  -- Below owner level a waive is capped like a manual discount.
  if v_waive then perform _waive_check(p_arena, v_billed, v_paid); end if;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from session_charges where session_id = v_session) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

comment on function "public"."_pr_group_bill"(uuid, timestamp with time zone, timestamp
  with time zone) is 'Pricing: server-side bill of a group session (per-system sweeps or a shared controller pool); port of GroupBilling.bill.';

comment on function "public"."_pr_session_bill"(uuid, timestamp
  with time zone, boolean) is 'Pricing: server-side bill of a single session over all its segments on its frozen snapshot; port of SegmentBilling.bill.';

comment on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp
  with time zone, boolean, timestamp with time zone) is 'Pricing: sweeps one station''s group assignments into constant-controller stretches and quotes each; port of GroupBilling sweepResource.';

revoke all
  on function "public"."_pr_group_bill"(uuid, timestamp with time zone, timestamp with time zone)
  from public;

grant execute
  on function "public"."_pr_group_bill"(uuid, timestamp with time zone, timestamp with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_pr_session_bill"(uuid, timestamp with time zone, boolean)
  from public;

grant execute
  on function "public"."_pr_session_bill"(uuid, timestamp with time zone, boolean)
  to "postgres", "service_role";

revoke all
  on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean, timestamp
    with time zone)
  from public;

grant execute
  on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean, timestamp
    with time zone)
  to "postgres", "service_role";
