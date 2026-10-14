-- op_session_void — sync op 'session.void': void a single session (any status) with a reason.
--
-- Permission: owner level via app_is_owner (role owner, or holds money or reports); not a _need
--   perm.
-- Payload: session_id, reason (required: 1–500 characters after trimming), at? (default server
--   time).
-- Checks / errors: forbidden ('void is owner-only'); void_reason_required; reason_too_long;
--   not_found (hint session). Already voided: success with adjusted=true (the first reason is
--   kept).
-- Writes: session_segments / controller_allocations (open rows ended at greatest(at,
--   started_at)), sessions (voided, void_reason), audit_log (action void, who, when, reason).
--   Never refunds: money already collected stays on the bill until a refund is recorded
--   (payment.record with is_refund, allowed on a voided bill). Returns: {adjusted}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_session_void (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  -- A void changes the takings: it is never recorded without a reason.
  if v_reason is null then
    raise exception 'void_reason_required' using hint = 'say why the bill is voided';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update session_segments set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update sessions set status = 'voided', void_reason = v_reason, updated_at = v_now
    where id = v_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'session', v_session, 'void', v_reason, auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

comment on function public.op_session_void(uuid, jsonb) is
  'Sync op session.void: voids a single session (owner level only, reason required), closing open segments and pads and auditing who, when and why.';

grant execute on function "public"."op_session_void"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_void"(uuid, jsonb) from public;

revoke all on function "public".op_session_void(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_session_void(p_arena uuid, p jsonb) from authenticated;
