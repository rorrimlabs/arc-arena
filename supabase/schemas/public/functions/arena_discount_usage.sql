-- arena_discount_usage() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_discount_usage, which
-- holds the SECURITY DEFINER body and its checks
-- (private/functions/arena_discount_usage.sql).
create or replace function public.arena_discount_usage (
  p_arena    uuid,
  p_discount uuid,
  p_limit    integer default 40,
  p_cursor   text default null
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_discount_usage(p_arena, p_discount, p_limit, p_cursor);
$function$;

comment on function public.arena_discount_usage(uuid, uuid, integer, text) is 'Client API (owner level): the bills a preset discount or coupon was used on, newest first, paged by an (applied time, id) cursor, with use counts.';

grant execute
  on function "public"."arena_discount_usage"(uuid, uuid, integer, text)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_discount_usage"(uuid, uuid, integer, text)
  from public;

revoke all on function "public".arena_discount_usage(p_arena uuid, p_discount uuid, p_limit integer, p_cursor text) from anon;
