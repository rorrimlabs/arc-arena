set local check_function_bodies = off;

create or replace function private.arena_bill_price (
  p_arena    uuid,
  p_id       uuid,
  p_ended_at timestamp with time zone
)
  returns bigint
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; v_started timestamptz; v_sched timestamptz; pol jsonb; seg record; q jsonb;
  v_sub bigint := 0; v_until timestamptz; v_end timestamptz; v_grace int; v_last_idx int;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can edit bills';
  end if;
  select pricing_snapshot, started_at, scheduled_end_at into v_snap, v_started, v_sched
    from sessions where id = p_id and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if p_ended_at is null or p_ended_at <= v_started then
    raise exception 'invalid_time' using hint = 'the end must be after the start';
  end if;
  pol := _pr_policy(v_snap);
  select max(idx) into v_last_idx from session_segments
   where session_id = p_id and started_at < p_ended_at;
  -- The overtime grace of the type it ends on, as _pr_session_bill reads it.
  select coalesce((a->>'overtime_grace_minutes')::int, 0) into v_grace
    from session_segments sg
    cross join lateral jsonb_array_elements(coalesce(v_snap->'activities', '[]'::jsonb)) a
   where sg.session_id = p_id and sg.idx = v_last_idx and a->>'code' = sg.activity_code;
  if coalesce(v_grace, 0) > 0 and p_ended_at > v_sched
     and p_ended_at - v_sched <= make_interval(mins => v_grace) then
    v_until := v_sched;
  end if;
  for seg in select * from session_segments where session_id = p_id and idx <= v_last_idx order by idx loop
    v_end := case when seg.idx = v_last_idx then p_ended_at
                  else least(coalesce(seg.ended_at, p_ended_at), p_ended_at) end;
    if v_until is not null then
      continue when seg.started_at >= v_until;
      v_end := least(v_end, v_until);
    end if;
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at, v_end, v_started);
    continue when q is null;
    v_sub := v_sub + (q->>'subtotal')::bigint;
  end loop;
  return _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir');
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
      when 'bill.adjust'          then op_bill_adjust(p_arena, p)
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
      when 'staff_details.save'   then op_staff_details_save(p_arena, p)
      when 'terms.publish'        then op_terms_publish(p_arena, p)
      when 'terms.accept'         then op_terms_accept(p_arena, p)
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

create or replace function public.arena_bill_price (
  p_arena    uuid,
  p_id       uuid,
  p_ended_at timestamp with time zone
)
  returns bigint
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_bill_price(p_arena, p_id, p_ended_at);
$function$;

create or replace function public.op_bill_adjust (
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
  v_group  boolean := coalesce(p->>'scope', 'single') = 'group';
  v_parent uuid := (p->>'parent_id')::uuid;
  v_new    bigint := (p->>'billed_amount_paise')::bigint;
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_method text := p->>'method';
  v_pay_id uuid := coalesce(nullif(p->>'payment_id', '')::uuid, gen_random_uuid());
  v_entity text := case when coalesce(p->>'scope', 'single') = 'group' then 'group_session'
                        else 'session' end;
  v_status text; v_pay text; v_old bigint; v_paid bigint; v_diff bigint;
begin
  perform _need(p_arena, 'money');
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say why the bill changes';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_new is null or v_new < 0 then
    raise exception 'invalid_total' using hint = 'the new total in whole paise, 0 or more';
  end if;

  -- Lock the bill (as op_payment does), so payments on it queue behind the change.
  if v_group then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_old
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_old
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
  end if;
  if v_status = 'voided' then raise exception 'voided' using hint = 'a voided bill has no total'; end if;
  if v_status <> 'completed' or v_old is null then
    raise exception 'not_ended' using hint = 'end the session first';
  end if;
  if v_pay = 'waived' then raise exception 'waived' using hint = 'a waived bill owes nothing'; end if;
  if v_new = v_old and v_paid = v_new then
    raise exception 'same_total' using hint = 'the bill is already that amount and paid';
  end if;

  -- What the bill says is what was collected: the difference goes in (or back) now.
  v_diff := v_new - v_paid;
  if v_diff <> 0 then
    if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
      raise exception 'invalid_method' using hint = 'how the difference was paid or given back';
    end if;
    if v_group then
      insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
          reason, created_by, created_at)
        values (v_pay_id, p_arena, v_parent, v_diff, v_method, v_diff < 0, 'Bill edited',
          v_reason, auth.uid(), v_now);
    else
      insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
          created_by, created_at)
        values (v_pay_id, p_arena, v_parent, v_diff, v_method,
          case when v_diff < 0 then 'refund' else 'payment' end, 'Bill edited',
          v_reason, auth.uid(), v_now);
    end if;
  end if;
  if v_group then
    update group_sessions set billed_amount_paise = v_new, payment_status = 'paid', updated_at = v_now
      where id = v_parent;
  else
    update sessions set billed_amount_paise = v_new, payment_status = 'paid', updated_at = v_now
      where id = v_parent;
  end if;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, v_entity, v_parent, 'bill_adjust', v_reason,
      jsonb_build_object('billed_paise', v_old, 'paid_paise', v_paid),
      jsonb_build_object('billed_paise', v_new, 'paid_paise', v_new), auth.uid(), v_now);
  return jsonb_build_object('payment_status', 'paid');
end;
$function$;

comment on column "public"."audit_log"."action" is 'What happened: void, waive, payment_correct, bill_adjust or duplicate_phone_on_sync.';

comment on function "private"."arena_bill_price"(uuid, uuid, timestamp
  with time zone) is 'Client API (owner level): the price of a closed single session had it ended at the given time, on its frozen price list, for the admin dashboard''s Edit bill.';

comment on function "public"."arena_bill_price"(uuid, uuid, timestamp
  with time zone) is 'Client API (owner level): the price of a closed single session had it ended at the given time, for the admin dashboard''s Edit bill.';

comment on function "public"."op_bill_adjust"(uuid, jsonb) is 'Sync op bill.adjust: sets a closed bill''s total (money permission, reason required) and records the difference as a payment or refund so collected matches it; audited; charges untouched.';

revoke all
  on function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone)
  from public;

grant execute
  on function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone) from public;

grant execute
  on function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."op_bill_adjust"(uuid, jsonb) from public;

grant execute on function "public"."op_bill_adjust"(uuid, jsonb) to "postgres", "service_role";
