-- my_arenas() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.my_arenas, which holds the
-- SECURITY DEFINER body and its checks (private/functions/my_arenas.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.my_arenas()
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.my_arenas();
$function$;

comment on function public.my_arenas() is 'Client API: the signed-in user''s staff profiles across arenas (including inactive ones) as a jsonb array of {arena_id, arena_name, name, role, perms, active}.';

grant execute on function "public"."my_arenas"() to "authenticated", "postgres", "service_role";

revoke all on function "public"."my_arenas"() from public;

revoke all on function "public".my_arenas() from anon;
