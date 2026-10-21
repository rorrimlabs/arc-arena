-- op_leave_cancel — sync op 'leave.cancel': withdraw your own leave request
--
-- Permission: the request's own staff member.
-- Payload: id, reason (optional). pending → cancelled at once; approved → cancel_pending (an
--   approver confirms it with leave.decide; until then the leave still counts).
-- Checks / errors: not_found; invalid_state (rejected / cancelled / already cancel_pending);
--   period_finalised.
-- Writes: leave_requests.status, cancel_reason. Returns: {status}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_leave_cancel (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_r leave_requests; v_status text;
begin
  select r.* into v_r from leave_requests r
    join staff_profiles sp on sp.id = r.staff_id
   where r.id = (p->>'id')::uuid and r.arena_id = p_arena and sp.user_id = auth.uid()
   for update of r;
  if not found then raise exception 'not_found' using hint = 'leave request'; end if;
  if v_r.status not in ('pending', 'approved') then raise exception 'invalid_state'; end if;
  if _period_finalised(p_arena, v_r.from_date, v_r.to_date) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;
  v_status := case when v_r.status = 'pending' then 'cancelled' else 'cancel_pending' end;
  update leave_requests set status = v_status,
      cancel_reason = nullif(btrim(coalesce(p->>'reason', '')), '')
   where id = v_r.id;
  return jsonb_build_object('status', v_status);
end;
$function$;

comment on function public.op_leave_cancel(uuid, jsonb) is 'Sync op leave.cancel: the requester cancels a pending request, or asks to cancel an approved one (cancel_pending).';

grant execute on function "public"."op_leave_cancel"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_cancel"(uuid, jsonb) from public;

revoke all on function "public"."op_leave_cancel"(uuid, jsonb) from anon;

revoke all on function "public"."op_leave_cancel"(uuid, jsonb) from authenticated;
