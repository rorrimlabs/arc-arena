-- op_attendance_review — sync op 'attendance.review': accept a flagged entry as it is
--
-- Permission: attendance_review; never on your own record unless role owner (own_record).
-- Payload: entry_id, note (optional).
-- Checks / errors: forbidden; not_found; own_record; not_pending (nothing to review).
-- Writes: attendance_entries.review = accepted; audit_log (action accept, the note).
-- Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_attendance_review (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_e attendance_entries;
begin
  perform _need(p_arena, 'attendance_review');
  select * into v_e from attendance_entries
    where id = (p->>'entry_id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'entry'; end if;
  perform _own_record(p_arena, v_e.staff_id);
  if v_e.review <> 'pending' or v_e.status <> 'active' then raise exception 'not_pending'; end if;
  update attendance_entries set review = 'accepted' where id = v_e.id;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'attendance_entry', v_e.id, 'accept',
            nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid(), statement_timestamp());
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_attendance_review(uuid, jsonb) is 'Sync op attendance.review: accept a flagged attendance entry as it is (audit_log keeps who and the note).';

grant execute on function "public"."op_attendance_review"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_attendance_review"(uuid, jsonb) from public;

revoke all on function "public"."op_attendance_review"(uuid, jsonb) from anon;

revoke all on function "public"."op_attendance_review"(uuid, jsonb) from authenticated;
