-- arena_members() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_members, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_members.sql).
create or replace function public.arena_members (
  p_arena    uuid,
  p_since    timestamp with time zone,
  p_since_30 timestamp with time zone,
  p_search   text default null,
  p_limit    integer default 50,
  p_offset   integer default 0
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_members(p_arena, p_since, p_since_30, p_search, p_limit, p_offset);
$function$;

comment on function public.arena_members(uuid, timestamp with time zone, timestamp with time zone, text, integer, integer) is 'Client API (owner level): one searched page of registered members with their visits, minutes, 30-day spend and last visit, aggregated on the server.';

grant execute
  on function "public"."arena_members"(uuid, timestamp with time zone, timestamp with time zone, text, integer, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_members"(uuid, timestamp with time zone, timestamp with time zone, text, integer, integer)
  from public;

revoke all on function "public".arena_members(p_arena uuid, p_since timestamp with time zone, p_since_30 timestamp with time zone, p_search text, p_limit integer, p_offset integer) from anon;
