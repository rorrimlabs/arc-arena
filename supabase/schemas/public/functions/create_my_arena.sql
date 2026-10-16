-- create_my_arena() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.create_my_arena, which holds the
-- SECURITY DEFINER body and its checks (private/functions/create_my_arena.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.create_my_arena (
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language sql
  security invoker
  set search_path to ''
  AS $function$
  select private.create_my_arena(p_arena_name, p_owner_name);
$function$;

comment on function public.create_my_arena(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

grant execute on function "public"."create_my_arena"(text, text) to "authenticated", "postgres", "service_role";

revoke all on function "public"."create_my_arena"(text, text) from public;

revoke all on function "public".create_my_arena(p_arena_name text, p_owner_name text) from anon;
