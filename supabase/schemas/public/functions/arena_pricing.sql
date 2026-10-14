-- arena_pricing() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_pricing, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_pricing.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.arena_pricing (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_pricing(p_arena);
$function$;

comment on function public.arena_pricing(uuid) is 'Client API (owner level): the arena''s station types with station counts, active standard rates and opening hours, for the admin dashboard''s Pricing screen.';

grant execute on function "public"."arena_pricing"(uuid) to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_pricing"(uuid) from public;

revoke all on function "public".arena_pricing(p_arena uuid) from anon;
