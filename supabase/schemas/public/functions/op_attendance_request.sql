-- op_attendance_request — sync op 'attendance.request': ask to fix your own attendance
--
-- Permission: time_request (an owner passes), for their own profile only.
-- Payload: id (client uuid: a resend replays), kind, reason (required, 1–500 characters), and
--   kind 'add': in_at, out_at — a stretch that was never punched;
--   kind 'fix_out': entry_id, out_at — the clock-out of your entry (still open, or closed
--     automatically / at the wrong time).
-- Checks / errors: forbidden; not_found (hint staff / entry); reason_required; reason_too_long;
--   invalid_payload; not_active (the entry was already corrected); invalid_times (out not after
--   in, in the future, or longer than 24 h); overlap (add: another active stretch of yours covers
--   that time); period_finalised; duplicate (id reused).
-- Writes: one pending attendance_requests row. Nothing counts until a reviewer approves it
--   (attendance.request_decide). Returns: {id}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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
  perform _need(p_arena, 'time_request');
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

comment on function public.op_attendance_request(uuid, jsonb) is 'Sync op attendance.request: a member with time_request asks to add a missed stretch or fix a missed clock-out on their own attendance; pending until a reviewer decides.';

grant execute on function "public"."op_attendance_request"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_attendance_request"(uuid, jsonb) from public;

revoke all on function "public".op_attendance_request(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_attendance_request(p_arena uuid, p jsonb) from authenticated;
