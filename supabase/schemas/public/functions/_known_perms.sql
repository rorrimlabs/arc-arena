-- _known_perms() — the permission codes a staff profile may hold
--
-- Returns {start, bill, discount, members, stations, money, reports, settings,
-- attendance_review, leave_approve, payroll, payroll_finalise, bill_edit, bill_record,
-- time_request}.
-- Used by _assert_known_perms and by op_staff_update (an owner's profile is
-- kept holding all of them) and by _create_arena_with_owner (a new owner gets them all).
-- Server-only: not executable by anon/authenticated.
create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings',
               'attendance_review','leave_approve','payroll','payroll_finalise','bill_edit',
               'bill_record','time_request'];
$function$;

comment on function public._known_perms() is 'The permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise, bill_edit, bill_record, time_request.';

grant execute on function "public"."_known_perms"() to "postgres", "service_role";

revoke all on function "public"."_known_perms"() from public;

revoke all on function "public"._known_perms() from anon;

revoke all on function "public"._known_perms() from authenticated;
