-- op_attendance_correct — sync op 'attendance.correct': fix someone's attendance, keeping history
--
-- Permission: attendance_review; never on your own record unless role owner (own_record).
-- Payload, one of:
--   {action:'edit', entry_id, in_at, out_at|null, reason}: the entry becomes superseded and a
--     new active row with the corrected times replaces it (replaces_id, source manual, review
--     corrected; its punches and flags are kept as evidence);
--   {action:'void', entry_id, reason}: the entry becomes voided (it no longer counts);
--   {action:'add', staff_id, in_at, out_at, reason}: a missing stretch, added by hand.
-- Checks / errors: forbidden; reason_required; not_found (hint entry / staff); own_record;
--   not_active (already superseded or voided); invalid_times (out not after in, in the future,
--   or longer than 24 h); overlap (another active stretch of that person); period_finalised.
-- Writes: attendance_entries; audit_log (entity attendance_entry, action correct / void / add,
--   before / after times, the reason). Returns: {entry_id} — the new row, or the voided one.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_attendance_correct (
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
  v_action text := p->>'action';
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_old    attendance_entries;
  v_staff  uuid;
  v_in     timestamptz := (p->>'in_at')::timestamptz;
  v_out    timestamptz := (p->>'out_at')::timestamptz;
  v_day    date;
  v_id     uuid;
begin
  perform _need(p_arena, 'attendance_review');
  if v_action is null or v_action not in ('edit', 'void', 'add') then
    raise exception 'invalid_payload' using hint = 'action: edit, void or add';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;

  if v_action in ('edit', 'void') then
    select * into v_old from attendance_entries
      where id = (p->>'entry_id')::uuid and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'entry'; end if;
    v_staff := v_old.staff_id;
    perform _own_record(p_arena, v_staff);
    if v_old.status <> 'active' then raise exception 'not_active'; end if;
    if _period_finalised(p_arena, v_old.work_date, v_old.work_date) then
      raise exception 'period_finalised' using hint = v_old.work_date::text;
    end if;
  else
    v_staff := (p->>'staff_id')::uuid;
    if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
      raise exception 'not_found' using hint = 'staff';
    end if;
    perform _own_record(p_arena, v_staff);
  end if;

  if v_action = 'void' then
    update attendance_entries set status = 'voided', review = 'corrected' where id = v_old.id;
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, created_by, created_at)
      values (p_arena, 'attendance_entry', v_old.id, 'void', v_reason,
              jsonb_build_object('in_at', v_old.in_at, 'out_at', v_old.out_at), auth.uid(), v_now);
    return jsonb_build_object('entry_id', v_old.id);
  end if;

  if v_in is null or (v_action = 'add' and v_out is null) then
    raise exception 'invalid_times' using hint = 'in_at and out_at';
  end if;
  if v_in > v_now or (v_out is not null and (v_out <= v_in or v_out > v_now
                       or v_out - v_in > interval '24 hours')) then
    raise exception 'invalid_times'
      using hint = 'clock-out after clock-in, not in the future, at most 24 h';
  end if;
  -- The work day is the shift the stretch falls in (overnight shifts count on their start day).
  v_day := _att_work_date(v_staff, v_in);
  if _period_finalised(p_arena, v_day, v_day) then
    raise exception 'period_finalised' using hint = v_day::text;
  end if;

  if v_action = 'edit' then
    update attendance_entries set status = 'superseded' where id = v_old.id;
  end if;
  begin
    insert into attendance_entries(arena_id, staff_id, work_date, in_at, out_at, in_punch_id,
        out_punch_id, source, out_source, replaces_id, flags, review, reason, created_by)
      values (p_arena, v_staff, v_day, v_in, v_out,
        case when v_action = 'edit' then v_old.in_punch_id end,
        case when v_action = 'edit' then v_old.out_punch_id end,
        'manual',
        case when v_out is null then null
             when v_action = 'edit' and v_out is not distinct from v_old.out_at then v_old.out_source
             else 'manual' end,
        case when v_action = 'edit' then v_old.id end,
        case when v_action = 'edit' then v_old.flags else '{}'::text[] end,
        'corrected', v_reason, auth.uid())
      returning id into v_id;
  exception when exclusion_violation or unique_violation then
    raise exception 'overlap' using hint = 'another stretch of this person covers that time';
  end;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after, created_by, created_at)
    values (p_arena, 'attendance_entry', v_id, case when v_action = 'edit' then 'correct' else 'add' end,
            v_reason,
            case when v_action = 'edit'
                 then jsonb_build_object('entry_id', v_old.id, 'in_at', v_old.in_at, 'out_at', v_old.out_at) end,
            jsonb_build_object('in_at', v_in, 'out_at', v_out), auth.uid(), v_now);
  return jsonb_build_object('entry_id', v_id);
end;
$function$;

comment on function public.op_attendance_correct(uuid, jsonb) is 'Sync op attendance.correct: edit (supersede), void or add an attendance entry with a reason; history and audit_log kept.';

grant execute on function "public"."op_attendance_correct"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_attendance_correct"(uuid, jsonb) from public;

revoke all on function "public"."op_attendance_correct"(uuid, jsonb) from anon;

revoke all on function "public"."op_attendance_correct"(uuid, jsonb) from authenticated;
