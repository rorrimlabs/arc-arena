-- arena_station_stats() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_station_stats, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_station_stats.sql).
create or replace function public.arena_station_stats (
  p_arena uuid,
  p_today timestamp with time zone,
  p_since timestamp with time zone,
  p_to    timestamp with time zone
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_station_stats(p_arena, p_today, p_since, p_to);
$function$;

comment on function public.arena_station_stats(uuid, timestamp with time zone, timestamp with time zone, timestamp with time zone) is 'Client API (owner level): per-station billed today / 30 days, sessions today, minutes played and accessory count, aggregated on the server.';

grant execute
  on function "public"."arena_station_stats"(uuid, timestamp with time zone, timestamp with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_station_stats"(uuid, timestamp with time zone, timestamp with time zone, timestamp with time zone)
  from public;

revoke all on function "public".arena_station_stats(p_arena uuid, p_today timestamp with time zone, p_since timestamp with time zone, p_to timestamp with time zone) from anon;
