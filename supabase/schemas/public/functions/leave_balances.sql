-- leave_balances() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.leave_balances, which holds the
-- SECURITY DEFINER body and its checks (private/functions/leave_balances.sql).
create or replace function public.leave_balances (
  p_arena uuid,
  p_staff uuid default null
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.leave_balances(p_arena, p_staff);
$function$;

comment on function public.leave_balances(uuid, uuid) is 'Client API: paid-leave balance per person for the current leave year — your own, or everyone''s with leave_approve / payroll.';

grant execute
  on function "public"."leave_balances"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."leave_balances"(uuid, uuid)
  from public;

revoke all on function "public".leave_balances(p_arena uuid, p_staff uuid) from anon;
