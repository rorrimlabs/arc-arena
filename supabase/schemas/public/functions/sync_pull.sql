-- sync_pull() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.sync_pull, which holds the
-- SECURITY DEFINER body and its checks (private/functions/sync_pull.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.sync_pull (
  p_arena  uuid,
  p_cursor text    default '0'::text,
  p_limit  integer default 2000
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.sync_pull(p_arena, p_cursor, p_limit);
$function$;

comment on function public.sync_pull(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

grant execute on function "public"."sync_pull"(uuid, text, integer) to "authenticated", "postgres", "service_role";

revoke all on function "public"."sync_pull"(uuid, text, integer) from public;

revoke all on function "public".sync_pull(p_arena uuid, p_cursor text, p_limit integer) from anon;
