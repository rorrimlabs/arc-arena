-- arena_game_stats() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_game_stats, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_game_stats.sql).
create or replace function public.arena_game_stats (
  p_arena uuid,
  p_since timestamp with time zone
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_game_stats(p_arena, p_since);
$function$;

comment on function public.arena_game_stats(uuid, timestamp with time zone) is 'Client API (owner level): per-game minutes, bills and stations playing it now, aggregated on the server.';

grant execute
  on function "public"."arena_game_stats"(uuid, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_game_stats"(uuid, timestamp with time zone)
  from public;

revoke all on function "public".arena_game_stats(p_arena uuid, p_since timestamp with time zone) from anon;
