set local check_function_bodies = off;

create table "public"."attendance_requests" (
  "id"              uuid                     not null,
  "arena_id"        uuid                     not null,
  "staff_id"        uuid                     not null,
  "kind"            text                     not null,
  "entry_id"        uuid,
  "in_at"           timestamp with time zone not null,
  "out_at"          timestamp with time zone not null,
  "reason"          text                     not null,
  "status"          text                     not null default 'pending'::text,
  "decided_by"      uuid,
  "decided_at"      timestamp with time zone,
  "decision_note"   text,
  "result_entry_id" uuid,
  "created_by"      uuid                     not null,
  "created_at"      timestamp with time zone not null default now(),
  "updated_at"      timestamp with time zone not null default now(),
  constraint "attendance_requests_entry_check" check (((kind = 'fix_out'::text) = (entry_id IS
    NOT NULL))),
  constraint "attendance_requests_kind_check"
    check ((kind = ANY (ARRAY['add'::text, 'fix_out'::text]))),
  constraint "attendance_requests_pkey" primary key (id),
  constraint "attendance_requests_reason_check" check ((btrim(reason) <> ''::text)),
  constraint "attendance_requests_status_check"
    check ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
  constraint "attendance_requests_times_check" check ((out_at > in_at))
);

alter table "public"."attendance_requests"
  enable row level security;

create or replace function private.session_quote (
  p_arena       uuid,
  p_resource    uuid,
  p_activity    text,
  p_controllers integer,
  p_from        timestamp with time zone,
  p_to          timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; q jsonb; pol jsonb; v_sub bigint;
begin
  if auth.uid() is null or p_arena is null or not private.app_has_perm(p_arena, 'bill_edit') then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs bill_edit';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '24 hours' then
    raise exception 'invalid_time' using hint = 'the end must be after the start, at most 24 h later';
  end if;
  if not exists (select 1 from resources where id = p_resource and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'station';
  end if;
  v_snap := _pricing_snapshot(p_arena);
  perform _seg_priced(p_arena, p_resource, v_snap, p_activity, p_controllers);
  q := _pr_quote(v_snap, p_activity, p_controllers, p_from, p_to, p_from);
  pol := _pr_policy(v_snap);
  v_sub := coalesce((q->>'subtotal')::bigint, 0);
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'));
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
      when 'session.record'       then op_session_record(p_arena, p)
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
      when 'attendance.request'   then op_attendance_request(p_arena, p)
      when 'attendance.request_decide' then op_attendance_request_decide(p_arena, p)
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

create or replace function public.op_attendance_request (
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
  v_id     uuid := (p->>'id')::uuid;
  v_kind   text := p->>'kind';
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_in     timestamptz := (p->>'in_at')::timestamptz;
  v_out    timestamptz := (p->>'out_at')::timestamptz;
  v_entry  attendance_entries;
  v_staff  uuid;
  v_day    date;
begin
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;
  if v_id is null or v_kind is null or v_kind not in ('add', 'fix_out') then
    raise exception 'invalid_payload' using hint = 'id; kind: add or fix_out';
  end if;

  if v_kind = 'fix_out' then
    select * into v_entry from attendance_entries
      where id = (p->>'entry_id')::uuid and arena_id = p_arena and staff_id = v_staff;
    if not found then raise exception 'not_found' using hint = 'entry'; end if;
    if v_entry.status <> 'active' then raise exception 'not_active'; end if;
    v_in := v_entry.in_at;
  end if;
  if v_in is null or v_out is null or v_out <= v_in or v_out > v_now
     or v_out - v_in > interval '24 hours' then
    raise exception 'invalid_times'
      using hint = 'clock-out after clock-in, not in the future, at most 24 h';
  end if;
  v_day := case when v_kind = 'fix_out' then v_entry.work_date else _att_work_date(v_staff, v_in) end;
  if _period_finalised(p_arena, v_day, v_day) then
    raise exception 'period_finalised' using hint = v_day::text;
  end if;
  if v_kind = 'add' and exists (
       select 1 from attendance_entries
        where staff_id = v_staff and status = 'active'
          and tstzrange(in_at, coalesce(out_at, 'infinity')) && tstzrange(v_in, v_out)) then
    raise exception 'overlap' using hint = 'you already have time recorded then';
  end if;

  insert into attendance_requests(id, arena_id, staff_id, kind, entry_id, in_at, out_at, reason,
      created_by, created_at)
    values (v_id, p_arena, v_staff, v_kind, v_entry.id, v_in, v_out, v_reason, auth.uid(), v_now);
  return jsonb_build_object('id', v_id);
end;
$function$;

create or replace function public.op_attendance_request_decide (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now     timestamptz := statement_timestamp();
  v_req     attendance_requests;
  v_approve boolean := (p->>'approve')::boolean;
  v_note    text := nullif(btrim(coalesce(p->>'note', '')), '');
  v_entry   uuid;
begin
  perform _need(p_arena, 'attendance_review');
  if v_approve is null then raise exception 'invalid_payload' using hint = 'approve: true or false'; end if;
  if length(v_note) > 500 then raise exception 'note_too_long'; end if;
  select * into v_req from attendance_requests
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'request'; end if;
  perform _own_record(p_arena, v_req.staff_id);
  if v_req.status <> 'pending' then raise exception 'invalid_state' using hint = v_req.status; end if;

  if v_approve then
    v_entry := (op_attendance_correct(p_arena,
      case when v_req.kind = 'add'
           then jsonb_build_object('action', 'add', 'staff_id', v_req.staff_id,
                  'in_at', v_req.in_at, 'out_at', v_req.out_at, 'reason', v_req.reason)
           else jsonb_build_object('action', 'edit', 'entry_id', v_req.entry_id,
                  'in_at', v_req.in_at, 'out_at', v_req.out_at, 'reason', v_req.reason) end)
      ->>'entry_id')::uuid;
  end if;
  update attendance_requests
     set status = case when v_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = v_now, decision_note = v_note,
         result_entry_id = v_entry
   where id = v_req.id;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
    values (p_arena, 'attendance_request', v_req.id,
            case when v_approve then 'approve' else 'reject' end, v_note,
            jsonb_build_object('kind', v_req.kind, 'in_at', v_req.in_at, 'out_at', v_req.out_at,
              'entry_id', v_entry),
            auth.uid(), v_now);
  return jsonb_build_object('status', case when v_approve then 'approved' else 'rejected' end)
    || case when v_entry is null then '{}'::jsonb else jsonb_build_object('entry_id', v_entry) end;
end;
$function$;

create or replace function public.op_session_record (
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
  v_id       uuid := (p->>'session_id')::uuid;
  v_pay_id   uuid := (p->>'payment_id')::uuid;
  v_customer uuid := (p->>'customer_id')::uuid;
  v_res      uuid := (p->>'resource_id')::uuid;
  v_act      text := p->>'activity_code';
  v_game     uuid := nullif(p->>'game_id', '')::uuid;
  v_cc       integer := nullif(p->>'controller_count', '')::int;
  v_start    timestamptz := (p->>'started_at')::timestamptz;
  v_end      timestamptz := (p->>'ended_at')::timestamptz;
  v_method   text := p->>'method';
  v_billed   bigint := (p->>'billed_amount_paise')::bigint;
  v_reason   text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_snap jsonb; v_seg uuid := gen_random_uuid(); q jsonb; l jsonb; v_bill jsonb;
  v_total bigint; v_pay text;
begin
  perform _need(p_arena, 'bill_edit');
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say why the bill is added later';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_id is null or v_pay_id is null or v_customer is null or v_res is null or v_act is null
     or v_start is null or v_end is null or v_billed is null or v_billed < 0
     or (v_cc is not null and v_cc not between 1 and 4) then
    raise exception 'invalid_payload';
  end if;
  if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
    raise exception 'invalid_method' using hint = 'how the bill was paid';
  end if;
  if v_end > v_now + interval '2 minutes' then
    raise exception 'time_in_future' using hint = 'ended_at';
  end if;
  if v_end <= v_start or v_end - v_start > interval '24 hours' then
    raise exception 'invalid_time' using hint = 'the end must be after the start, at most 24 h later';
  end if;
  if not exists (select 1 from customers where id = v_customer and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'customer';
  end if;
  -- Lock the station so two missed bills for the same time cannot both pass the overlap check.
  perform 1 from resources where id = v_res and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'station'; end if;
  if v_game is not null and not exists (select 1 from games where id = v_game and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  if exists (select 1 from session_segments
              where resource_id = v_res and arena_id = p_arena
                and tstzrange(started_at, coalesce(ended_at, 'infinity')) && tstzrange(v_start, v_end))
     or exists (select 1 from group_assignments
              where resource_id = v_res and arena_id = p_arena
                and tstzrange(started_at, coalesce(ended_at, 'infinity')) && tstzrange(v_start, v_end)) then
    raise exception 'overlap' using hint = 'the station already has play recorded in that time';
  end if;

  v_snap := _pricing_snapshot(p_arena);
  perform _seg_priced(p_arena, v_res, v_snap, v_act, v_cc);

  insert into sessions(id, arena_id, customer_id, status, payment_status, started_at,
      scheduled_end_at, actual_ended_at, pricing_snapshot, policy_snapshot, billed_amount_paise,
      created_at, updated_at, created_by, ended_recorded_at)
    values (v_id, p_arena, v_customer, 'completed', 'unpaid', v_start, v_end, v_end, v_snap,
      v_snap->'policy', v_billed, v_now, v_now, auth.uid(), v_now);
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code, game_id,
      controller_count, started_at, ended_at, created_at)
    values (v_seg, p_arena, v_id, 0, v_res, v_act, v_game, v_cc, v_start, v_end, v_now);

  -- Charge rows straight from the server's quote (the same lines _pr_session_bill keys).
  q := _pr_quote(v_snap, v_act, v_cc, v_start, v_end, v_start);
  for l in select value from jsonb_array_elements(coalesce(q->'lines', '[]'::jsonb)) loop
    insert into session_charges(id, arena_id, session_id, segment_id, segment_index, band_code,
        activity_code, resource_id, controller_count, segment_start, segment_end, played_minutes,
        billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values (gen_random_uuid(), p_arena, v_id, v_seg, 0, l->>'band', v_act, v_res, v_cc,
        (l->>'start')::timestamptz, (l->>'end')::timestamptz,
        ((l->>'played_seconds')::bigint / 60)::int, (l->>'billed_minutes')::int,
        (l->>'unit_minutes')::int, (l->>'unit_price')::bigint, (l->>'amount')::bigint, v_now);
  end loop;
  v_bill := _pr_session_bill(v_id, v_end, true);
  v_total := (v_bill->>'total')::bigint;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
  end if;

  if v_total > 0 then
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values (v_pay_id, p_arena, v_id, v_total, v_method, 'payment', 'Added later', v_reason,
        auth.uid(), v_now);
  end if;
  v_pay := _payment_status(v_total, v_total);
  update sessions set payment_status = v_pay where id = v_id;

  update customers set last_visit_at = greatest(coalesce(last_visit_at, v_start), v_start)
    where id = v_customer;
  if v_game is not null then
    update games set last_played_at = greatest(coalesce(last_played_at, v_start), v_start)
      where id = v_game;
  end if;

  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, 'session', v_id, 'record', v_reason, null,
      jsonb_build_object('billed_paise', v_total, 'method', v_method, 'resource_id', v_res,
        'started_at', v_start, 'ended_at', v_end),
      auth.uid(), v_now);
  return jsonb_build_object('session_id', v_id, 'billed_amount_paise', v_total,
    'payment_status', v_pay);
end;
$function$;

create or replace function public.session_quote (
  p_arena       uuid,
  p_resource    uuid,
  p_activity    text,
  p_controllers integer,
  p_from        timestamp with time zone,
  p_to          timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.session_quote(p_arena, p_resource, p_activity, p_controllers, p_from, p_to);
$function$;

alter table "public"."attendance_requests"
  add constraint "attendance_requests_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."attendance_requests"
  add constraint "attendance_requests_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."attendance_requests"
  add constraint "attendance_requests_decided_by_fkey" foreign key (decided_by)
    references auth.users(id);

alter table "public"."attendance_requests"
  add constraint "attendance_requests_entry_id_fkey" foreign key (entry_id)
    references public.attendance_entries(id);

alter table "public"."attendance_requests"
  add constraint "attendance_requests_result_entry_id_fkey" foreign key (result_entry_id)
    references public.attendance_entries(id);

alter table "public"."attendance_requests"
  add constraint "attendance_requests_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

create index ix_attendance_requests_arena_status on public.attendance_requests
  using btree (arena_id, status);

create index ix_attendance_requests_created_by on public.attendance_requests
  using btree (created_by);

create index ix_attendance_requests_decided_by on public.attendance_requests
  using btree (decided_by);

create index ix_attendance_requests_entry_id on public.attendance_requests using btree (entry_id);

create index ix_attendance_requests_result_entry_id on public.attendance_requests
  using btree (result_entry_id);

create index ix_attendance_requests_staff on public.attendance_requests
  using btree (staff_id, in_at);

create trigger t_attendance_requests_updated
  before update on public.attendance_requests
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.attendance_requests
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create policy "p_sel_attendance_requests" on "public"."attendance_requests"
  for select
  to "authenticated"
  using
    (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in (
    select private.app_arena_ids_with(ARRAY['attendance_review'::text]) as app_arena_ids_with))));

comment on column "public"."attendance_requests"."kind" is 'add (a stretch never punched) or fix_out (a clock-out for entry_id).';

comment on column "public"."attendance_requests"."result_entry_id" is 'The attendance_entries row the approval created.';

comment on column "public"."attendance_requests"."status" is 'pending, approved (applied: result_entry_id) or rejected (decision_note).';

comment on function "private"."session_quote"(uuid, uuid, text, integer, timestamp
  with time zone, timestamp with time zone) is 'Client API (bill_edit): the price session.record would bill for a past single session on the current price list, {subtotal, total}.';

comment on function "public"."op_attendance_request"(uuid, jsonb) is 'Sync op attendance.request: a member asks to add a missed stretch or fix a missed clock-out on their own attendance; pending until a reviewer decides.';

comment on function "public"."op_attendance_request_decide"(uuid, jsonb) is
  'Sync op attendance.request_decide: approve (applied via attendance.correct) or reject a staff attendance request; audited.';

comment on function "public"."op_session_record"(uuid, jsonb) is 'Sync op session.record: add a missed single session after the fact (bill_edit), already ended, priced on the current price list and paid in full; overlap-checked against the station''s recorded play; audited with the required reason.';

comment on function "public"."session_quote"(uuid, uuid, text, integer, timestamp
  with time zone, timestamp with time zone) is 'Client API (bill_edit): the price of a missed single session before session.record adds it.';

comment on table "public"."attendance_requests" is 'Staff requests to fix their own attendance (a missed stretch, or a missed clock-out on an entry); applied through attendance.correct only when a reviewer approves.';

revoke all
  on function "private"."session_quote"(uuid, uuid, text, integer, timestamp
    with time zone, timestamp with time zone)
  from public;

grant execute
  on function "private"."session_quote"(uuid, uuid, text, integer, timestamp
    with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."op_attendance_request"(uuid, jsonb) from public;

grant execute
  on function "public"."op_attendance_request"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_attendance_request_decide"(uuid, jsonb) from public;

grant execute
  on function "public"."op_attendance_request_decide"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_session_record"(uuid, jsonb) from public;

grant execute on function "public"."op_session_record"(uuid, jsonb) to "postgres", "service_role";

revoke all
  on function "public"."session_quote"(uuid, uuid, text, integer, timestamp
    with time zone, timestamp with time zone)
  from public;

grant execute
  on function "public"."session_quote"(uuid, uuid, text, integer, timestamp
    with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

grant select on table "public"."attendance_requests" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."attendance_requests"
  to "postgres", "service_role";
