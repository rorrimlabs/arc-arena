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
  v_status text;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update session_segments set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'session', v_session, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

grant execute on function "public"."op_session_void"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_void"(uuid, jsonb) from public;

revoke all on function "public".op_session_void(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_session_void(p_arena uuid, p jsonb) from authenticated;
