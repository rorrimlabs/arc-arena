-- _group_active(p_arena, p_group) — lock a group session and require it to be active.
--
-- SELECT ... FOR UPDATE on group_sessions; raises 'not_found' (hint 'group') or 'not_active'
-- (hint: the status). Used by op_group_add, op_group_switch, op_group_extend, op_group_end and
-- op_group_end_player.
-- Server-only: not executable by anon/authenticated.
create or replace function public._group_active (
  p_arena uuid,
  p_group uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  select status into v_status from group_sessions where id = p_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
end;
$function$;

comment on function public._group_active(uuid, uuid) is 'Locks a group session row and raises not_found or not_active unless it is active.';

grant execute on function "public"."_group_active"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_group_active"(uuid, uuid) from public;

revoke all on function "public"._group_active(p_arena uuid, p_group uuid) from anon;

revoke all on function "public"._group_active(p_arena uuid, p_group uuid) from authenticated;
