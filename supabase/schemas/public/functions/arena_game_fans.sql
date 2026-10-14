-- arena_game_fans() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_game_fans, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_game_fans.sql).
create or replace function public.arena_game_fans (
  p_arena uuid,
  p_game  uuid,
  p_since timestamp with time zone,
  p_limit integer default 4
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_game_fans(p_arena, p_game, p_since, p_limit);
$function$;

comment on function public.arena_game_fans(uuid, uuid, timestamp with time zone, integer) is 'Client API (owner level): the members who played a game the most since an instant, aggregated on the server.';

grant execute
  on function "public"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  from public;

revoke all on function "public".arena_game_fans(p_arena uuid, p_game uuid, p_since timestamp with time zone, p_limit integer) from anon;
