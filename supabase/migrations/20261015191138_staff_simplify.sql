set local check_function_bodies = off;

create or replace function public._create_arena_with_owner (
  p_user       uuid,
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_arena uuid;
begin
  insert into arenas(name) values (coalesce(nullif(btrim(p_arena_name), ''), 'Arena'))
    returning id into v_arena;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, p_user, coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      _known_perms(), true);
  insert into settings(arena_id, key, json)
    values (v_arena, 'attendance', jsonb_build_object('geofence', null, 'outside_rule', 'allow',
      'min_accuracy_m', 50, 'mock_rule', 'block', 'max_open_hours', 14));
  return v_arena;
end;
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
      when 'discount.upsert'      then op_discount_upsert(p_arena, p)
      when 'discount.set_active'  then op_discount_set_active(p_arena, p)
      when 'discount.delete'      then op_discount_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      when 'attendance.punch'     then op_attendance_punch(p_arena, p)
      when 'attendance.correct'   then op_attendance_correct(p_arena, p)
      when 'attendance.review'    then op_attendance_review(p_arena, p)
      when 'shift.upsert'         then op_shift_upsert(p_arena, p)
      when 'shift.assign'         then op_shift_assign(p_arena, p)
      when 'shift.unassign'       then op_shift_unassign(p_arena, p)
      when 'staff_holiday.upsert' then op_staff_holiday_upsert(p_arena, p)
      when 'staff_holiday.delete' then op_staff_holiday_delete(p_arena, p)
      when 'hr_profile.save'      then op_hr_profile_save(p_arena, p)
      when 'leave.request'        then op_leave_request(p_arena, p)
      when 'leave.cancel'         then op_leave_cancel(p_arena, p)
      when 'leave.decide'         then op_leave_decide(p_arena, p)
      when 'leave.adjust'         then op_leave_adjust(p_arena, p)
      when 'leave.record'         then op_leave_record(p_arena, p)
      when 'pay_rate.add'         then op_pay_rate_add(p_arena, p)
      when 'pay_policy.add'       then op_pay_policy_add(p_arena, p)
      when 'salary_run.create'    then op_salary_run_create(p_arena, p)
      when 'salary_run.recalculate' then op_salary_run_recalculate(p_arena, p)
      when 'salary_run.set_deduction' then op_salary_run_set_deduction(p_arena, p)
      when 'salary_run.finalise'  then op_salary_run_finalise(p_arena, p)
      when 'salary_run.discard'   then op_salary_run_discard(p_arena, p)
      when 'salary_adjustment.add' then op_salary_adjustment_add(p_arena, p)
      when 'salary_adjustment.reverse' then op_salary_adjustment_reverse(p_arena, p)
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

create or replace function public.op_leave_record (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_today  date := _pr_ist_date(statement_timestamp());
  v_rules  jsonb := _leave_rules(p_arena);
  v_staff  uuid := (p->>'staff_id')::uuid;
  v_from   date := (p->>'from_date')::date;
  v_to     date := (p->>'to_date')::date;
  v_half   text := coalesce(p->>'half_day', 'none');
  v_paid_b boolean := (p->>'paid')::boolean;
  v_reason text := coalesce(nullif(btrim(coalesce(p->>'reason', '')), ''), 'Recorded by a manager');
  v_days   numeric;
  v_paid   numeric;
  v_split  jsonb;
begin
  perform _need(p_arena, 'leave_approve');
  if v_staff is null or not exists (select 1 from staff_profiles
                                     where id = v_staff and arena_id = p_arena and active) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  perform _own_record(p_arena, v_staff);
  if v_paid_b is null then raise exception 'invalid_payload' using hint = 'paid'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 92 then
    raise exception 'invalid_dates' using hint = 'from_date to to_date, at most 93 days';
  end if;
  if v_half not in ('none', 'first_half', 'second_half') then
    raise exception 'invalid_payload' using hint = 'half_day';
  end if;
  if v_half <> 'none' and (v_from <> v_to or not (v_rules->>'half_day_allowed')::boolean) then
    raise exception 'half_day_not_allowed';
  end if;
  if _period_finalised(p_arena, v_from, v_to) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;
  if exists (select 1 from leave_requests where staff_id = v_staff
              and status in ('pending', 'approved', 'cancel_pending')
              and from_date <= v_to and to_date >= v_from) then
    raise exception 'leave_overlap';
  end if;
  select sum(units) into v_days from _leave_working_days(v_staff, v_from, v_to, v_half);
  if coalesce(v_days, 0) = 0 then
    raise exception 'no_working_days' using hint = 'those days are week-offs or holidays';
  end if;
  v_paid := case when v_paid_b then v_days else 0 end;
  -- Pin the paid days to the earliest working days, the rest is LOP (as op_leave_decide).
  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'units', d.units,
           'paid_units', greatest(0, least(d.units, v_paid - d.before))) order by d.day), '[]'::jsonb)
    into v_split
    from (select w.day, w.units,
                 coalesce(sum(w.units) over (order by w.day rows between unbounded preceding and 1 preceding), 0) as before
            from _leave_working_days(v_staff, v_from, v_to, v_half) w) d;
  insert into leave_requests(id, arena_id, staff_id, kind, from_date, to_date, half_day, days,
      paid_days, lop_days, day_split, reason, status, decided_by, decided_at, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff,
      case when v_from >= v_today then 'planned' else 'unplanned' end,
      v_from, v_to, v_half, v_days, v_paid, v_days - v_paid, v_split, v_reason, 'approved',
      auth.uid(), statement_timestamp(), auth.uid());
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
    values (p_arena, 'leave_request', (p->>'id')::uuid, 'record', v_reason,
            jsonb_build_object('paid_days', v_paid, 'lop_days', v_days - v_paid),
            auth.uid(), statement_timestamp());
  return jsonb_build_object('days', v_days, 'paid_days', v_paid, 'lop_days', v_days - v_paid);
end;
$function$;

comment on function "public"."_create_arena_with_owner"(uuid, text, text) is
  'Internal: create an empty arena (no catalog: the owner adds station types, prices, stations, games and controllers on the dashboard; attendance location checks off) and make the given login its owner with every permission. Shared by bootstrap_owner and create_my_arena; callers validate the login first.';

comment on function "public"."op_leave_record"(uuid, jsonb) is 'Sync op leave.record: a leave approver records a staff member''s leave directly as approved, all paid or all loss of pay, pinned to dates.';

revoke all on function "public"."op_leave_record"(uuid, jsonb) from public;

grant execute on function "public"."op_leave_record"(uuid, jsonb) to "postgres", "service_role";
