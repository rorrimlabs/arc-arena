-- op_leave_adjust — sync op 'leave.adjust': add or take paid-leave days for the current year
--
-- Permission: leave_approve.
-- Payload: staff_id, days (signed, in halves, not 0), reason. Counts in the person's leave
--   year containing today (IST).
-- Checks / errors: forbidden; not_found (hint staff); reason_required; invalid_payload.
-- Writes: leave_adjustments. Returns: {year_start}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_leave_adjust (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff  uuid := (p->>'staff_id')::uuid;
  v_days   numeric := (p->>'days')::numeric;
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_ys     date;
begin
  perform _need(p_arena, 'leave_approve');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if v_days is null or v_days = 0 or (v_days * 2) % 1 <> 0 or abs(v_days) > 366 then
    raise exception 'invalid_payload' using hint = 'days: a non-zero number of half days';
  end if;
  v_ys := _leave_year_start(v_staff, _pr_ist_date(statement_timestamp()));
  insert into leave_adjustments(arena_id, staff_id, year_start, days, reason, created_by)
    values (p_arena, v_staff, v_ys, v_days, v_reason, auth.uid());
  return jsonb_build_object('year_start', v_ys);
end;
$function$;

comment on function public.op_leave_adjust(uuid, jsonb) is 'Sync op leave.adjust: add (or take) paid-leave days in a staff member''s current leave year, with a reason.';

grant execute on function "public"."op_leave_adjust"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_adjust"(uuid, jsonb) from public;

revoke all on function "public"."op_leave_adjust"(uuid, jsonb) from anon;

revoke all on function "public"."op_leave_adjust"(uuid, jsonb) from authenticated;
