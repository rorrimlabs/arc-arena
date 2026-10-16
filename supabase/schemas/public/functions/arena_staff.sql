-- arena_staff() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_staff, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_staff.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.arena_staff (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_staff(p_arena);
$function$;

comment on function public.arena_staff(uuid) is 'Client API (owner level): the arena''s staff with login e-mail, never-signed-in flag and 30-day bills, net takings and refunds they recorded, for the admin dashboard''s Staff screen.';

grant execute on function "public"."arena_staff"(uuid) to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_staff"(uuid) from public;

revoke all on function "public".arena_staff(p_arena uuid) from anon;
