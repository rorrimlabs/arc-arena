-- op_leave_request — sync op 'leave.request': apply for leave (for yourself)
--
-- Permission: any active member, for their own staff profile.
-- Payload: id (client uuid), kind (planned | unplanned), from_date, to_date, half_day
--   (none | first_half | second_half; single day only), reason.
-- Rules: leave_rules: a half day needs half_day_allowed; planned leave starts today (IST) or
--   later; unplanned leave may start up to unplanned_backdate_days back. days = the working days
--   it covers (_leave_working_days: scheduled, not a staff holiday).
-- Checks / errors: not_found (hint staff); reason_required; invalid_dates; half_day_not_allowed;
--   planned_in_past; too_far_back; no_working_days; leave_overlap (another pending / approved
--   request of yours covers some of those days); period_finalised; duplicate (id reused).
-- Writes: leave_requests (pending). Returns: {days}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_leave_request (
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
  v_staff  uuid;
  v_kind   text := p->>'kind';
  v_from   date := (p->>'from_date')::date;
  v_to     date := (p->>'to_date')::date;
  v_half   text := coalesce(p->>'half_day', 'none');
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_days   numeric;
begin
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;
  if v_kind is null or v_kind not in ('planned', 'unplanned') then
    raise exception 'invalid_payload' using hint = 'kind: planned or unplanned';
  end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 92 then
    raise exception 'invalid_dates' using hint = 'from_date to to_date, at most 93 days';
  end if;
  if v_half not in ('none', 'first_half', 'second_half') then
    raise exception 'invalid_payload' using hint = 'half_day';
  end if;
  if v_half <> 'none' and (v_from <> v_to or not (v_rules->>'half_day_allowed')::boolean) then
    raise exception 'half_day_not_allowed';
  end if;
  if v_kind = 'planned' and v_from < v_today then
    raise exception 'planned_in_past' using hint = 'planned leave starts today or later';
  end if;
  if v_kind = 'unplanned'
     and v_from < v_today - (v_rules->>'unplanned_backdate_days')::int then
    raise exception 'too_far_back'
      using hint = 'at most ' || (v_rules->>'unplanned_backdate_days') || ' days back';
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
  insert into leave_requests(id, arena_id, staff_id, kind, from_date, to_date, half_day, days,
      reason, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff, v_kind, v_from, v_to, v_half, v_days, v_reason,
      auth.uid());
  return jsonb_build_object('days', v_days);
end;
$function$;

comment on function public.op_leave_request(uuid, jsonb) is 'Sync op leave.request: the caller applies for planned or unplanned leave; working days are counted by the server.';

grant execute on function "public"."op_leave_request"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_request"(uuid, jsonb) from public;

revoke all on function "public"."op_leave_request"(uuid, jsonb) from anon;

revoke all on function "public"."op_leave_request"(uuid, jsonb) from authenticated;
