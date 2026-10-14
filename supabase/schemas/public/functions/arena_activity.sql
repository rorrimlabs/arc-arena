-- arena_activity() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_activity, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_activity.sql).
create or replace function public.arena_activity (
  p_arena    uuid,
  p_resource uuid,
  p_customer uuid,
  p_since    timestamp with time zone,
  p_limit    integer default 6
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_activity(p_arena, p_resource, p_customer, p_since, p_limit);
$function$;

comment on function public.arena_activity(uuid, uuid, uuid, timestamp with time zone, integer) is 'Client API (owner level): a station''s or member''s newest bills and (for a member) minutes per game, read when the dashboard opens it.';

grant execute
  on function "public"."arena_activity"(uuid, uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_activity"(uuid, uuid, uuid, timestamp with time zone, integer)
  from public;

revoke all on function "public".arena_activity(p_arena uuid, p_resource uuid, p_customer uuid, p_since timestamp with time zone, p_limit integer) from anon;
