-- _free_pads_at(p_arena, p_resource) — usable pads at a station with no open allocation.
--
-- Counts pads (_is_pad) whose current_resource_id is p_resource, status 'usable', and no open
-- controller_allocations row. Used by _single_supply for count-only (untracked) controller requests.
-- Server-only: not executable by anon/authenticated.
create or replace function public._free_pads_at (
  p_arena    uuid,
  p_resource uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::int from controllers c
   where c.arena_id = p_arena and c.current_resource_id = p_resource and c.status = 'usable'
     and _is_pad(c.kind_id)
     and not exists (select 1 from controller_allocations a
                      where a.controller_id = c.id and a.ended_at is null);
$function$;

comment on function public._free_pads_at(uuid, uuid) is 'Counts usable, unallocated controllers currently at a station.';

grant execute on function "public"."_free_pads_at"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_free_pads_at"(uuid, uuid) from public;

revoke all on function "public"._free_pads_at(p_arena uuid, p_resource uuid) from anon;

revoke all on function "public"._free_pads_at(p_arena uuid, p_resource uuid) from authenticated;
