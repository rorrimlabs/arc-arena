-- app_is_owner() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.app_is_owner, which holds the
-- SECURITY DEFINER body and its checks (private/functions/app_is_owner.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.app_is_owner (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.app_is_owner(p_arena);
$function$;

comment on function public.app_is_owner(uuid) is 'True when the signed-in user is owner level in the arena: an active profile with role owner, or holding the money or reports permission.';

grant execute on function "public"."app_is_owner"(uuid) to "authenticated", "postgres", "service_role";

revoke all on function "public"."app_is_owner"(uuid) from public;

revoke all on function "public".app_is_owner(p_arena uuid) from anon;
