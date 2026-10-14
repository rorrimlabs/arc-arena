set local check_function_bodies = off;

create or replace function private.arena_sale (
  p_arena uuid,
  p_id    uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_bill jsonb;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read sales';
  end if;
  select b into v_bill from _sales(p_arena, null, null, p_id) b;
  if v_bill is null then raise exception 'not_found' using hint = 'bill'; end if;

  if v_bill->>'kind' = 'single' then
    v_bill := v_bill || jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player', null, 'station', r.name, 'activity', coalesce(a.name, ch.activity_code),
            'band', ch.band_code, 'controllers', ch.controller_count,
            'start', ch.segment_start, 'end', ch.segment_end,
            'played_minutes', ch.played_minutes, 'billed_minutes', ch.billed_minutes,
            'unit_minutes', ch.unit_minutes, 'unit_price_paise', ch.unit_price_paise,
            'amount_paise', ch.amount_paise)
          order by ch.segment_start, ch.segment_index)
          from session_charges ch
          left join resources r on r.id = ch.resource_id
          left join activities a on a.arena_id = ch.arena_id and a.code = ch.activity_code
         where ch.session_id = p_id), '[]'::jsonb),
      'extensions', coalesce((
        select jsonb_agg(jsonb_build_object('at', e.created_at, 'added_minutes', e.added_minutes,
            'added_amount_paise', e.added_amount_paise, 'reason', e.reason, 'by', sp.name)
          order by e.created_at)
          from session_extensions e
          left join staff_profiles sp on sp.arena_id = e.arena_id and sp.user_id = e.created_by
         where e.session_id = p_id), '[]'::jsonb));
  else
    v_bill := v_bill || jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player', ch.player_number, 'station', r.name, 'activity', coalesce(a.name, ch.activity_code),
            'band', ch.band_code, 'controllers', ch.controller_count,
            'start', ch.segment_start, 'end', ch.segment_end,
            'played_minutes', ch.played_minutes, 'billed_minutes', ch.billed_minutes,
            'unit_minutes', ch.unit_minutes, 'unit_price_paise', ch.unit_price_paise,
            'amount_paise', ch.amount_paise)
          order by ch.segment_start, ch.player_number, ch.charge_index)
          from group_charges ch
          left join resources r on r.id = ch.resource_id
          left join activities a on a.arena_id = ch.arena_id and a.code = ch.activity_code
         where ch.group_id = p_id), '[]'::jsonb),
      'extensions', coalesce((
        select jsonb_agg(jsonb_build_object('at', e.created_at, 'added_minutes', e.added_minutes,
            'added_amount_paise', e.added_amount_paise, 'reason', e.reason, 'by', sp.name)
          order by e.created_at)
          from group_extensions e
          left join staff_profiles sp on sp.arena_id = e.arena_id and sp.user_id = e.created_by
         where e.group_id = p_id), '[]'::jsonb));
  end if;

  return v_bill || jsonb_build_object(
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('at', l.created_at, 'action', l.action, 'by', sp.name,
          'reason', l.reason, 'before', l.before, 'after', l.after)
        order by l.created_at, l.id)
        from audit_log l
        left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
       where l.arena_id = p_arena and l.entity_id = p_id
         and l.entity_type = case when v_bill->>'kind' = 'group' then 'group_session' else 'session' end),
      '[]'::jsonb),
    'voided', (
      select jsonb_build_object('at', l.created_at, 'by', sp.name, 'reason', l.reason)
        from audit_log l
        left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
       where l.arena_id = p_arena and l.entity_id = p_id and l.action = 'void'
       order by l.created_at limit 1));
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
      'started_at', s.started_at, 'ended_at', s.actual_ended_at, 'recorded_at', s.created_at,
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
      'voided_at', vd.at, 'voided_by', vd.by)
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
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from payments
                                where session_id = s.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.kind = 'refund', 'reason', q.reason, 'note', q.note,
                                 'by', sq.name)
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
   where s.arena_id = p_arena and s.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else s.id = p_id end)
  union all
  select jsonb_build_object(
      'kind', 'group', 'id', gs.id, 'at', b.at,
      'started_at', gs.started_at, 'ended_at', gs.actual_ended_at, 'recorded_at', gs.created_at,
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
      'voided_at', vd.at, 'voided_by', vd.by)
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
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from group_payments
                                where group_id = gs.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.is_refund, 'reason', q.reason, 'note', q.note,
                                 'by', sq.name)
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
   where gs.arena_id = p_arena and gs.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else gs.id = p_id end);
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
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove') then
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
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
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
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_group;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason; optional here so floor builds that do not send it still end the group).
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
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
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

create or replace function public.op_group_void (
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
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  -- A void changes the takings: it is never recorded without a reason.
  if v_reason is null then
    raise exception 'void_reason_required' using hint = 'say why the bill is voided';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  select status into v_status from group_sessions where id = v_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  -- greatest(): never end a row before it started, whatever the device clock said.
  update group_assignments set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = v_reason, updated_at = v_now
    where id = v_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'group_session', v_group, 'void', v_reason, auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_payment (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now    timestamptz := statement_timestamp();
  v_scope  text    := coalesce(p->>'scope', 'single');
  v_parent uuid    := (p->>'parent_id')::uuid;
  v_refund boolean := coalesce((p->>'is_refund')::boolean, false);
  v_amount bigint  := (p->>'amount_paise')::bigint;
  v_status text; v_pay text; v_billed bigint; v_paid bigint;
begin
  -- Permission refusals keep their own code, ahead of any balance check.
  perform _need(p_arena, 'bill');
  if v_refund then perform _need(p_arena, 'discount'); end if;

  -- Balance (0016). Lock the parent so two pushes for the same bill queue here
  -- and the second sees the first one's payment.
  if v_scope = 'group' then
    select payment_status, billed_amount_paise into v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from group_payments where group_id = v_parent;
    end if;
  else
    select payment_status, billed_amount_paise into v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from payments where session_id = v_parent;
    end if;
  end if;

  -- v_paid is null when the parent was not found; not_found is raised further down.
  if v_paid is not null and coalesce(v_amount, 0) <> 0 then
    if v_refund then
      if v_paid - abs(v_amount) < 0 then
        raise exception 'refund_exceeds_paid'
          using hint = 'only ' || _rupees(greatest(v_paid, 0)) || ' was collected';
      end if;
    elsif v_amount > 0 and v_billed is not null and v_pay <> 'waived'
          and v_paid + v_amount > v_billed then
      raise exception 'overpayment'
        using hint = case when v_billed - v_paid <= 0 then 'this bill is already paid'
                          else 'only ' || _rupees(v_billed - v_paid) || ' is due' end;
    end if;
  end if;

  -- Amount, sign, refund reason and method.
  if v_amount is null or v_amount = 0 then raise exception 'amount_zero'; end if;
  if v_refund then
    if coalesce(btrim(p->>'reason'), '') = '' then raise exception 'refund_reason_required'; end if;
    v_amount := -abs(v_amount);
  elsif v_amount < 0 then
    raise exception 'amount_negative';
  end if;
  if (p->>'method') not in ('cash','upi','card','other') then raise exception 'invalid_method'; end if;

  -- Record the payment and recompute the parent's payment status (a waived bill
  -- keeps 'waived').
  if v_scope = 'group' then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    if v_status = 'voided' and not v_refund then
      raise exception 'voided' using hint = 'a voided bill takes no payments; a refund is allowed';
    end if;
    insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
        reason, created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method', v_refund,
        p->>'note', p->>'reason', auth.uid(), v_now);
    if v_pay <> 'waived' and v_status <> 'voided' then
      select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update group_sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    if v_status = 'voided' and not v_refund then
      raise exception 'voided' using hint = 'a voided bill takes no payments; a refund is allowed';
    end if;
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method',
        case when v_refund then 'refund' else 'payment' end, p->>'note', p->>'reason',
        auth.uid(), v_now);
    if v_pay <> 'waived' and v_status <> 'voided' then
      select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_payment_correct (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now       timestamptz := statement_timestamp();
  v_group     boolean := coalesce(p->>'scope', 'single') = 'group';
  v_parent    uuid := (p->>'parent_id')::uuid;
  v_payment   uuid := (p->>'payment_id')::uuid;
  v_method    text := p->>'method';
  v_reason    text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_refund_id uuid := coalesce(nullif(p->>'refund_id', '')::uuid, gen_random_uuid());
  v_new_id    uuid := coalesce(nullif(p->>'new_payment_id', '')::uuid, gen_random_uuid());
  v_entity    text := case when coalesce(p->>'scope', 'single') = 'group' then 'group_session'
                           else 'session' end;
  v_old_method text; v_old_amount bigint; v_was_refund boolean;
  v_moved bigint; v_left bigint; v_amount bigint;
begin
  perform _need(p_arena, 'money');
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say what was recorded wrongly';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
    raise exception 'invalid_method';
  end if;

  -- Lock the bill (as op_payment does), so payments and corrections on it queue here.
  if v_group then
    perform 1 from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    select method, amount_paise, is_refund into v_old_method, v_old_amount, v_was_refund
      from group_payments where id = v_payment and group_id = v_parent and arena_id = p_arena;
  else
    perform 1 from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    select method, amount_paise, kind = 'refund' into v_old_method, v_old_amount, v_was_refund
      from payments where id = v_payment and session_id = v_parent and arena_id = p_arena;
  end if;
  if not found then raise exception 'not_found' using hint = 'payment'; end if;
  if v_was_refund then
    raise exception 'not_a_payment' using hint = 'only a payment can be moved to another method';
  end if;
  if v_method = v_old_method then
    raise exception 'same_method' using hint = 'that payment is already recorded as ' || v_old_method;
  end if;

  -- What earlier corrections already moved out of this payment.
  select coalesce(sum((after->>'amount_paise')::bigint), 0) into v_moved
    from audit_log
   where arena_id = p_arena and entity_type = v_entity and entity_id = v_parent
     and action = 'payment_correct' and before->>'payment_id' = v_payment::text;
  v_left := v_old_amount - v_moved;
  if v_left <= 0 then
    raise exception 'already_corrected' using hint = 'all of this payment was already moved';
  end if;
  v_amount := coalesce((p->>'amount_paise')::bigint, v_left);
  if v_amount <= 0 or v_amount > v_left then
    raise exception 'amount_invalid' using hint = 'at most ' || _rupees(v_left) || ' can be moved';
  end if;

  if v_group then
    insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
        reason, created_by, created_at)
      values
        (v_refund_id, p_arena, v_parent, -v_amount, v_old_method, true, 'Method correction',
          v_reason, auth.uid(), v_now),
        (v_new_id, p_arena, v_parent, v_amount, v_method, false, 'Method correction',
          v_reason, auth.uid(), v_now);
  else
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values
        (v_refund_id, p_arena, v_parent, -v_amount, v_old_method, 'refund', 'Method correction',
          v_reason, auth.uid(), v_now),
        (v_new_id, p_arena, v_parent, v_amount, v_method, 'payment', 'Method correction',
          v_reason, auth.uid(), v_now);
  end if;

  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, v_entity, v_parent, 'payment_correct', v_reason,
      jsonb_build_object('payment_id', v_payment, 'method', v_old_method,
        'amount_paise', v_old_amount),
      jsonb_build_object('method', v_method, 'amount_paise', v_amount,
        'refund_id', v_refund_id, 'payment_id', v_new_id),
      auth.uid(), v_now);
  return jsonb_build_object('moved_paise', v_amount, 'refund_id', v_refund_id,
    'payment_id', v_new_id);
end;
$function$;

revoke all
  on function "public"."op_payment_correct"(uuid, jsonb)
  from public, "anon", "authenticated";

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
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
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
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_session;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason; optional here so floor builds that do not send it still end the session).
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
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
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

create or replace function public.op_session_void (
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
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  -- A void changes the takings: it is never recorded without a reason.
  if v_reason is null then
    raise exception 'void_reason_required' using hint = 'say why the bill is voided';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update session_segments set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update sessions set status = 'voided', void_reason = v_reason, updated_at = v_now
    where id = v_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'session', v_session, 'void', v_reason, auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

comment on column "public"."audit_log"."action" is 'What happened: void, waive, payment_correct or duplicate_phone_on_sync.';

comment on column "public"."audit_log"."reason" is 'Human reason (the void or correction reason, the waive reason when given, or a system explanation).';

comment on function "private"."arena_sale"(uuid, uuid) is 'Client API (owner level): one closed bill with its charge lines, extensions, payments ledger, audit history and void record, for the admin dashboard''s Sales detail.';

comment on function "public"."_sales"(uuid, timestamp with time zone, timestamp
  with time zone, uuid) is 'Closed bills (completed or voided sessions and groups) of an arena as jsonb summaries with their payments ledger, by close time range or by id. Server-only body of arena_sales / arena_sale.';

comment on function "public"."op_group_void"(uuid, jsonb) is 'Sync op group.void: voids a group session (owner level only, reason required), closing open assignments and pads and auditing who, when and why.';

comment on function "public"."op_payment_correct"(uuid, jsonb) is 'Sync op payment.correct: moves all or part of a recorded payment to another method (money permission, reason required) as an append-only refund + payment pair, audited; the bill''s net never changes.';

comment on function "public"."op_session_void"(uuid, jsonb) is 'Sync op session.void: voids a single session (owner level only, reason required), closing open segments and pads and auditing who, when and why.';

comment on table "public"."audit_log" is 'Append-only audit trail of voids, waives, payment-method corrections and sync-time data adjustments, per arena. Not part of the sync change feed.';

revoke all on function "public"."op_payment_correct"(uuid, jsonb) from "postgres";

grant execute on function "public"."op_payment_correct"(uuid, jsonb) to "postgres";

grant execute on function "public"."op_payment_correct"(uuid, jsonb) to "service_role";
