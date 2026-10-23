-- op_attendance_request_decide — sync op 'attendance.request_decide': approve or reject a
--   staff member's attendance request
--
-- Permission: attendance_review; never on your own request unless role owner (own_record).
-- Payload: id, approve (boolean), note? (at most 500 characters; recorded with a rejection).
-- Approve applies the request through op_attendance_correct with the request's reason:
--   'add' → action add {staff_id, in_at, out_at}; 'fix_out' → action edit {entry_id, in_at
--   (unchanged), out_at}. Its checks and errors apply (not_active, invalid_times, overlap,
--   period_finalised), and it writes the entry and its audit_log row.
-- Checks / errors: forbidden; not_found; own_record; invalid_state (not pending); note_too_long.
-- Writes: attendance_requests (status, decided_by / _at, decision_note, result_entry_id);
--   audit_log (entity attendance_request, action approve / reject, the note).
--   Returns: {status, entry_id?}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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

comment on function public.op_attendance_request_decide(uuid, jsonb) is 'Sync op attendance.request_decide: approve (applied via attendance.correct) or reject a staff attendance request; audited.';

grant execute on function "public"."op_attendance_request_decide"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_attendance_request_decide"(uuid, jsonb) from public;

revoke all on function "public".op_attendance_request_decide(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_attendance_request_decide(p_arena uuid, p jsonb) from authenticated;
