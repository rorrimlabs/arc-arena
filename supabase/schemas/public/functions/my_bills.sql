-- my_bills() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.my_bills, which holds the
-- SECURITY DEFINER body and its checks (private/functions/my_bills.sql).
create or replace function public.my_bills (
  p_arena uuid,
  p_day   date
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.my_bills(p_arena, p_day);
$function$;

comment on function public.my_bills(uuid, date) is 'Client API (bill_edit or bill_record): the caller''s own closed bills that closed on the given IST day, for the floor app''s My bills.';

grant execute
  on function "public"."my_bills"(uuid, date)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."my_bills"(uuid, date)
  from public;

revoke all on function "public".my_bills(p_arena uuid, p_day date) from anon;
