-- attendance_days() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.attendance_days, which holds the
-- SECURITY DEFINER body and its checks (private/functions/attendance_days.sql).
create or replace function public.attendance_days (
  p_arena uuid,
  p_from  date,
  p_to    date,
  p_staff uuid default null
)
  returns jsonb
  language sql
  security invoker
  set search_path to ''
  AS $function$
  select private.attendance_days(p_arena, p_from, p_to, p_staff);
$function$;

comment on function public.attendance_days(uuid, date, date, uuid) is 'Client API: attendance per person and IST day (status, minutes, leave, flags) — your own, or everyone''s with attendance_review / payroll.';

grant execute
  on function "public"."attendance_days"(uuid, date, date, uuid)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."attendance_days"(uuid, date, date, uuid)
  from public;

revoke all on function "public".attendance_days(p_arena uuid, p_from date, p_to date, p_staff uuid) from anon;
