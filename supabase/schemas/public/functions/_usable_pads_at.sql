-- _usable_pads_at(p_arena, p_resource) — usable pads at a station, allocated or not.
--
-- Counts pads (_is_pad) whose current_resource_id is p_resource and status is 'usable'.
-- Used by _group_assignable (plus pads being borrowed) for 'controllers_unavailable'.
-- Server-only: not executable by anon/authenticated.
create or replace function public._usable_pads_at (
  p_arena    uuid,
  p_resource uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::int from controllers
   where arena_id = p_arena and current_resource_id = p_resource and status = 'usable'
     and _is_pad(kind_id);
$function$;

comment on function public._usable_pads_at(uuid, uuid) is 'Counts usable controllers currently at a station, whether allocated or not.';

grant execute on function "public"."_usable_pads_at"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_usable_pads_at"(uuid, uuid) from public;

revoke all on function "public"._usable_pads_at(p_arena uuid, p_resource uuid) from anon;

revoke all on function "public"._usable_pads_at(p_arena uuid, p_resource uuid) from authenticated;
