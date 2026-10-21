set local check_function_bodies = off;

alter table "public"."group_sessions"
  add column "ended_recorded_at" timestamp with time zone;

alter table "public"."sessions"
  add column "ended_recorded_at" timestamp with time zone;

create or replace function public._client_time (
  p_at    timestamp with time zone,
  p_field text
)
  returns void
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
begin
  if p_at > statement_timestamp() + interval '2 minutes' then
    raise exception 'time_in_future' using hint = p_field || ' is after the server''s time';
  end if;
  if p_at < statement_timestamp() - interval '24 hours' then
    raise exception 'time_too_old' using hint = p_field || ' is more than 24 hours old';
  end if;
end;
$function$;

create or replace function public._sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone,
  p_id    uuid                     default null::uuid
)
  returns SETOF jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
      'kind', 'single', 'id', s.id, 'at', b.at,
      'started_at', s.started_at, 'ended_at', s.actual_ended_at, 'recorded_at', s.created_at, 'end_recorded_at', s.ended_recorded_at,
      'status', s.status, 'payment_status', s.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = s.customer_id and o.arena_id = s.arena_id
                   and o.id <> s.id and o.status = 'completed' and o.started_at < s.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = s.customer_id and o.arena_id = s.arena_id
                      and o.status = 'completed' and o.started_at < s.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', seg.players, 'player_minutes', seg.player_minutes,
      'billed_paise', s.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', s.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by,
      'discount_paise', coalesce(dsc.amount, 0), 'discount', dsc.j)
    from sessions s
    cross join lateral (select coalesce(s.actual_ended_at, s.updated_at) as at) b
    join customers c on c.id = s.customer_id
    left join staff_profiles sp on sp.arena_id = s.arena_id and sp.user_id = s.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.idx) as first
                                 from session_segments g join resources r on r.id = g.resource_id
                                where g.session_id = s.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.idx) as first
                                 from session_segments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.session_id = s.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.idx) as first
                                 from session_segments g join games gm on gm.id = g.game_id
                                where g.session_id = s.id group by gm.name) x), '[]'::jsonb) as games,
             coalesce((select max(g.controller_count) from session_segments g
                        where g.session_id = s.id), 1) as players,
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0 * coalesce(g.controller_count, 1)))::int
                         from session_segments g where g.session_id = s.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from payments
                                where session_id = s.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.kind = 'refund', 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.session_id = s.id), '[]'::jsonb) as ledger
        from payments p where p.session_id = s.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
    left join lateral (
      select d.amount_paise as amount,
             jsonb_build_object('source', d.source, 'name', d.name, 'code', d.code,
               'discount_id', d.discount_id, 'value_kind', d.value_kind, 'value', d.value,
               'base_paise', d.base_paise, 'amount_paise', d.amount_paise, 'reason', d.reason,
               'by', sd.name) as j
        from bill_discounts d
        left join staff_profiles sd on sd.arena_id = d.arena_id and sd.user_id = d.applied_by
       where d.session_id = s.id
    ) dsc on true
   where s.arena_id = p_arena and s.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else s.id = p_id end)
  union all
  select jsonb_build_object(
      'kind', 'group', 'id', gs.id, 'at', b.at,
      'started_at', gs.started_at, 'ended_at', gs.actual_ended_at, 'recorded_at', gs.created_at, 'end_recorded_at', gs.ended_recorded_at,
      'status', gs.status, 'payment_status', gs.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                   and o.status = 'completed' and o.started_at < gs.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                      and o.id <> gs.id and o.status = 'completed' and o.started_at < gs.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', gs.player_count, 'player_minutes', seg.player_minutes,
      'billed_paise', gs.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', gs.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by,
      'discount_paise', coalesce(dsc.amount, 0), 'discount', dsc.j)
    from group_sessions gs
    cross join lateral (select coalesce(gs.actual_ended_at, gs.updated_at) as at) b
    join customers c on c.id = gs.primary_customer_id
    left join staff_profiles sp on sp.arena_id = gs.arena_id and sp.user_id = gs.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join resources r on r.id = g.resource_id
                                where g.group_id = gs.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.group_id = gs.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join games gm on gm.id = g.game_id
                                where g.group_id = gs.id group by gm.name) x), '[]'::jsonb) as games,
             -- Each assignment is one player's stretch on one station.
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0))::int
                         from group_assignments g where g.group_id = gs.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from group_payments
                                where group_id = gs.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.is_refund, 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from group_payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.group_id = gs.id), '[]'::jsonb) as ledger
        from group_payments p where p.group_id = gs.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
    left join lateral (
      select d.amount_paise as amount,
             jsonb_build_object('source', d.source, 'name', d.name, 'code', d.code,
               'discount_id', d.discount_id, 'value_kind', d.value_kind, 'value', d.value,
               'base_paise', d.base_paise, 'amount_paise', d.amount_paise, 'reason', d.reason,
               'by', sd.name) as j
        from bill_discounts d
        left join staff_profiles sd on sd.arena_id = d.arena_id and sd.user_id = d.applied_by
       where d.group_id = gs.id
    ) dsc on true
   where gs.arena_id = p_arena and gs.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else gs.id = p_id end);
$function$;

create or replace function public._seg_priced (
  p_arena    uuid,
  p_resource uuid,
  p_snapshot jsonb,
  p_act      text,
  p_cc       integer
)
  returns void
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
begin
  if exists (select 1 from resource_activities where resource_id = p_resource)
     and not exists (select 1 from resource_activities ra join activities a on a.id = ra.activity_id
                      where ra.resource_id = p_resource and a.arena_id = p_arena and a.code = p_act) then
    raise exception 'activity_not_offered' using hint = coalesce(p_act, 'null');
  end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_snapshot->'rates', '[]'::jsonb)) r
                  where r->>'activity_code' = p_act
                    and (r->>'controller_count')::int is not distinct from p_cc) then
    raise exception 'no_rate'
      using hint = coalesce(p_act, 'null') || ' with ' || coalesce(p_cc::text, 'no') || ' controllers';
  end if;
end;
$function$;

create or replace function public.op_group_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  a jsonb := p->'assignment';
  v_player int := (p->'assignment'->>'player_number')::int;
  v_idx int; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _client_time(v_at, 'at');
  perform _group_active(p_arena, v_group);
  if exists (select 1 from group_assignments
              where group_id = v_group and player_number = v_player and ended_at is null) then
    raise exception 'player_busy';
  end if;
  perform _group_lock(p_arena, jsonb_build_array(a));
  -- Next index in this player's assignment history (a re-added player continues it).
  select coalesce(max(idx), -1) + 1 into v_idx from group_assignments
    where group_id = v_group and player_number = v_player;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx, null);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_group_create (
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
  v_group uuid := (p->>'id')::uuid;
  v_started timestamptz := (p->>'started_at')::timestamptz;
  v_skipped int := 0; a jsonb;
begin
  perform _need(p_arena, 'start');
  perform _client_time(v_started, 'started_at');
  if jsonb_array_length(coalesce(p->'assignments', '[]'::jsonb)) = 0 then
    raise exception 'no_assignments';
  end if;
  -- Every target station and borrowed-pad origin, then the pads, in uuid order.
  perform _group_lock(p_arena, p->'assignments');
  insert into group_sessions(id, arena_id, primary_customer_id, player_count,
      purchased_controller_count, status, payment_status, started_at, scheduled_end_at,
      pricing_snapshot, policy_snapshot, billing_mode, created_by, created_at, updated_at)
    values (v_group, p_arena, (p->>'primary_customer_id')::uuid, (p->>'player_count')::int,
      coalesce((p->>'purchased_controller_count')::int, 0), 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      p->'pricing_snapshot'->'policy', coalesce(nullif(p->>'billing_mode',''), 'per_system'),
      auth.uid(), v_now, v_now);
  -- Device order: each check sees the players placed before it (as on device).
  for a in select value from jsonb_array_elements(p->'assignments') loop
    v_skipped := v_skipped + _group_place(p_arena, v_group, a, v_started,
      coalesce((a->>'idx')::int, 0), null);
  end loop;
  update customers set last_visit_at = v_started, updated_at = v_now
    where id = (p->>'primary_customer_id')::uuid and arena_id = p_arena;

  -- The frozen price list must be this arena's current one, and the group's
  -- billing mode must be the one that price list prescribes (0013).
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  if coalesce(nullif(p->>'billing_mode', ''), 'per_system')
     <> _pr_policy(p->'pricing_snapshot')->>'group_billing_mode' then
    raise exception 'pricing_snapshot_mismatch'
      using hint = 'billing_mode differs from the price list''s group billing mode';
  end if;
  return jsonb_build_object('group_id', v_group, 'adjusted', v_skipped > 0);
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
  perform _client_time(v_ended, 'ended_at');
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
  v_bill := _pr_group_bill(v_group, v_ended);
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

create or replace function public.op_group_end_player (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_open uuid; v_start timestamptz;
begin
  perform _need(p_arena, 'start');
  perform _client_time(v_at, 'at');
  perform _group_active(p_arena, v_group);
  select id, started_at into v_open, v_start from group_assignments
   where group_id = v_group and player_number = (p->>'player_number')::int and ended_at is null
   for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_group_switch (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_player int := (p->>'player_number')::int;
  a jsonb := p->'assignment';
  v_open uuid; v_open_res uuid; v_start timestamptz; v_idx int; v_label text; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _client_time(v_at, 'at');
  perform _group_active(p_arena, v_group);
  select id, resource_id, started_at, idx, player_label
    into v_open, v_open_res, v_start, v_idx, v_label
    from group_assignments
   where group_id = v_group and player_number = v_player and ended_at is null for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  -- Also lock the station the player is leaving.
  perform _group_lock(p_arena, jsonb_build_array(a), array[v_open_res]);
  -- The player keeps their label across a switch (as on the device).
  a := a || jsonb_build_object('player_number', v_player, 'player_label', v_label);
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx + 1, v_player);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
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
  perform _client_time(v_ended, 'ended_at');
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
  v_bill := _pr_session_bill(v_session, v_ended);
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

create or replace function public.op_session_reconfigure (
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
  v_at timestamptz := (p->>'at')::timestamptz;
  v_resource uuid := (p->>'resource_id')::uuid;
  v_game uuid := nullif(p->>'game_id','')::uuid;
  v_act text := p->>'activity_code';
  v_cc int := nullif(p->>'controller_count','')::int;
  v_new uuid := (p->>'new_segment_id')::uuid;
  v_borrow uuid[] := _pad_ids(p->'moves');
  v_pads uuid[] := _pad_ids(p->'allocations');
  v_status text; v_open uuid; v_open_res uuid; v_open_start timestamptz; v_idx int; v_open_cc int;
  v_skipped int;
  v_origins uuid[];
begin
  perform _need(p_arena, 'start');
  perform _client_time(v_at, 'at');
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select id, resource_id, started_at, idx, controller_count
    into v_open, v_open_res, v_open_start, v_idx, v_open_cc
    from session_segments where session_id = v_session and ended_at is null;
  if not found then raise exception 'no_open_segment'; end if;
  if v_open is distinct from nullif(p->>'expected_segment_id','')::uuid then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;
  if v_at < v_open_start then raise exception 'invalid_time'; end if;

  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, array[v_resource, v_open_res] || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  if not (_pad_origins(p_arena, v_borrow) <@ (array[v_resource, v_open_res] || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;

  if v_resource <> v_open_res then
    perform _station_usable(p_arena, v_resource);
    perform _station_free_for_single(v_resource);
  end if;
  perform _game_playable(v_game, v_resource);
  perform _single_supply(p_arena, v_resource, v_act, v_game,
    coalesce(array_length(v_pads, 1), 0), v_cc, v_open_res, v_open_cc);
  perform _seg_priced(p_arena, v_resource,
    (select pricing_snapshot from sessions where id = v_session), v_act, v_cc);

  update session_segments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where segment_id = v_open and ended_at is null;
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
      game_id, controller_count, started_at, created_at)
    values (v_new, p_arena, v_session, v_idx + 1, v_resource, v_act, v_game, v_cc, v_at, v_now);
  v_skipped := _pad_borrow(p_arena, p->'moves', v_resource, 's:' || v_session::text, v_at);
  perform _pad_allocate(p_arena, p->'allocations', 'single', v_session, null, v_new, null,
    null, null, v_resource, v_act, v_game, v_at);
  update sessions set updated_at = v_now where id = v_session;
  if v_game is not null then
    update games set last_played_at = v_at, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;
  return jsonb_build_object('segment_id', v_new, 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_session_start (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now      timestamptz := statement_timestamp();
  v_session  uuid := (p->>'id')::uuid;
  v_segment  uuid := (p->>'segment_id')::uuid;
  v_resource uuid := (p->>'resource_id')::uuid;
  v_game     uuid := nullif(p->>'game_id','')::uuid;
  v_started  timestamptz := (p->>'started_at')::timestamptz;
  v_customer uuid := (p->>'customer_id')::uuid;
  v_booking  uuid := nullif(p->>'booking_id','')::uuid;
  v_act      text := p->>'activity_code';
  v_cc       int  := nullif(p->>'controller_count','')::int;
  v_borrow   uuid[] := _pad_ids(p->'moves');
  v_pads     uuid[] := _pad_ids(p->'allocations');
  v_bstatus  text;
  v_skipped  int;
  v_origins  uuid[];
begin
  perform _need(p_arena, 'start');
  perform _client_time(v_started, 'started_at');
  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, array[v_resource] || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  -- A pad that moved between the read and the lock sits at a station we do not
  -- hold: retry rather than check it unlocked.
  if not (_pad_origins(p_arena, v_borrow) <@ (array[v_resource] || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;

  perform _station_usable(p_arena, v_resource);
  perform _game_playable(v_game, v_resource);
  perform _single_supply(p_arena, v_resource, v_act, v_game,
    coalesce(array_length(v_pads, 1), 0), v_cc);
  perform _station_free_for_single(v_resource);
  perform _seg_priced(p_arena, v_resource, p->'pricing_snapshot', v_act, v_cc);

  if v_booking is not null then
    select status into v_bstatus from bookings
      where id = v_booking and arena_id = p_arena for update;
    if not found then raise exception 'booking_missing'; end if;
    if v_bstatus <> 'booked' then raise exception 'booking_not_open' using hint = v_bstatus; end if;
    update bookings set status = 'checked_in', updated_at = v_now where id = v_booking;
  end if;

  insert into sessions(id, arena_id, booking_id, customer_id, status, payment_status,
      started_at, scheduled_end_at, pricing_snapshot, policy_snapshot, request_id,
      created_by, created_at, updated_at)
    values (v_session, p_arena, v_booking, v_customer, 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      coalesce(p->'pricing_snapshot'->'policy', '{}'::jsonb), null, auth.uid(), v_now, v_now);
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
      game_id, controller_count, started_at, created_at)
    values (v_segment, p_arena, v_session, 0, v_resource, v_act, v_game, v_cc, v_started, v_now);

  v_skipped := _pad_borrow(p_arena, p->'moves', v_resource, 's:' || v_session::text, v_started);
  perform _pad_allocate(p_arena, p->'allocations', 'single', v_session, null, v_segment, null,
    null, null, v_resource, v_act, v_game, v_started);

  update customers set last_visit_at = v_started, updated_at = v_now
    where id = v_customer and arena_id = p_arena;
  if v_game is not null then
    update games set last_played_at = v_started, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;

  -- The price list the device froze into the session must be this arena's
  -- current one (0013); checked last so earlier errors keep their precedence.
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  return jsonb_build_object('session_id', v_session, 'adjusted', v_skipped > 0);
end;
$function$;

comment on column "public"."group_sessions"."ended_recorded_at" is 'Server time the end reached the server (actual_ended_at is the device''s); the dashboard flags an end recorded more than 15 minutes later. Null while active and for bills ended before it was recorded.';

comment on column "public"."sessions"."ended_recorded_at" is 'Server time the end reached the server (actual_ended_at is the device''s); the dashboard flags an end recorded more than 15 minutes later. Null while active and for bills ended before it was recorded.';

comment on function "public"."_client_time"(timestamp
  with time zone, text) is 'Internal: raise time_in_future (> now + 2 min) or time_too_old (> 24 h ago) for a device-stamped billing instant.';

comment on function "public"."_seg_priced"(uuid, uuid, jsonb, text, integer) is
  'Internal: raise activity_not_offered or no_rate unless a single-session segment can be billed from the snapshot.';

revoke all on function "public"."_client_time"(timestamp with time zone, text) from public;

grant execute
  on function "public"."_client_time"(timestamp with time zone, text)
  to "postgres", "service_role";

revoke all on function "public"."_seg_priced"(uuid, uuid, jsonb, text, integer) from public;

grant execute
  on function "public"."_seg_priced"(uuid, uuid, jsonb, text, integer)
  to "postgres", "service_role";
