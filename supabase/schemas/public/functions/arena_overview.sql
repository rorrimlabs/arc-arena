-- arena_overview() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_overview, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_overview.sql).
create or replace function public.arena_overview (
  p_arena     uuid,
  p_from      timestamp with time zone,
  p_to        timestamp with time zone,
  p_prev_from timestamp with time zone,
  p_prev_to   timestamp with time zone,
  p_bucket    text,
  p_today     timestamp with time zone
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_overview(p_arena, p_from, p_to, p_prev_from, p_prev_to, p_bucket, p_today);
$function$;

comment on function public.arena_overview(uuid, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, text, timestamp with time zone) is 'Client API (owner level): the Overview''s aggregated figures for a period and the one before it (totals, takings buckets, payment split, by type, top games, by staff, latest bills).';

grant execute
  on function "public"."arena_overview"(uuid, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, text, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_overview"(uuid, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, text, timestamp with time zone)
  from public;

revoke all on function "public".arena_overview(p_arena uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_prev_from timestamp with time zone, p_prev_to timestamp with time zone, p_bucket text, p_today timestamp with time zone) from anon;
