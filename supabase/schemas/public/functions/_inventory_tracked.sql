-- _inventory_tracked(p_arena) — does the arena track physical pads?
--
-- True when the arena has any controller that is not 'retired'. Used by _single_supply.
-- Server-only: not executable by anon/authenticated.
create or replace function public._inventory_tracked (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (select 1 from controllers where arena_id = p_arena and status <> 'retired');
$function$;

comment on function public._inventory_tracked(uuid) is 'True when the arena has at least one non-retired controller.';

grant execute on function "public"."_inventory_tracked"(uuid) to "postgres", "service_role";

revoke all on function "public"."_inventory_tracked"(uuid) from public;

revoke all on function "public"._inventory_tracked(p_arena uuid) from anon;

revoke all on function "public"._inventory_tracked(p_arena uuid) from authenticated;
