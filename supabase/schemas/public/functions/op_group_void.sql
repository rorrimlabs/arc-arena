-- op_group_void — sync op 'group.void': void a group session (any status) with a reason.
--
-- Permission: owner level via app_is_owner (role owner, or holds money or reports); not a _need
--   perm.
-- Payload: group_id, reason, at? (default server time).
-- Checks / errors: forbidden ('void is owner-only'); not_found (hint group). Already voided:
--   success with adjusted=true.
-- Writes: group_assignments / controller_allocations (open rows ended at greatest(at,
--   started_at)), group_sessions (voided, void_reason), audit_log. Returns: {adjusted}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_void (
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
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from group_sessions where id = v_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  -- greatest(): never end a row before it started, whatever the device clock said.
  update group_assignments set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'group_session', v_group, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

comment on function public.op_group_void(uuid, jsonb) is
  'Sync op group.void: voids a group session (owner level only), closing open assignments and pads and auditing the reason.';

grant execute on function "public"."op_group_void"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_void"(uuid, jsonb) from public;

revoke all on function "public".op_group_void(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_void(p_arena uuid, p jsonb) from authenticated;
