-- session_quote() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.session_quote, which holds the
-- SECURITY DEFINER body and its checks (private/functions/session_quote.sql).
create or replace function public.session_quote (
  p_arena       uuid,
  p_resource    uuid,
  p_activity    text,
  p_controllers integer,
  p_from        timestamptz,
  p_to          timestamptz
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.session_quote(p_arena, p_resource, p_activity, p_controllers, p_from, p_to);
$function$;

comment on function public.session_quote(uuid, uuid, text, integer, timestamptz, timestamptz) is 'Client API (bill_record): the price of a missed single session before session.record adds it.';

grant execute
  on function "public"."session_quote"(uuid, uuid, text, integer, timestamptz, timestamptz)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."session_quote"(uuid, uuid, text, integer, timestamptz, timestamptz)
  from public;

revoke all on function "public".session_quote(p_arena uuid, p_resource uuid, p_activity text, p_controllers integer, p_from timestamptz, p_to timestamptz) from anon;
