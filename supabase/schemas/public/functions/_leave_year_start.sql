-- _leave_year_start(staff, day) — first day of the leave year that p_day falls in
--
-- Leave years run from the person's joining date (_staff_hr.joined_on) to the day before each
-- anniversary (OWNER_CONFIRMATION S5); a 29 February joiner's later years start 28 February.
-- A day before joining belongs to the first year.
-- Server-only: not executable by anon/authenticated.
create or replace function public._leave_year_start (
  p_staff uuid,
  p_day   date
)
  returns date
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select case when p_day <= h.joined_on then h.joined_on
              else (h.joined_on + make_interval(years => date_part('year', age(p_day, h.joined_on))::int))::date
         end
    from _staff_hr(p_staff) h;
$function$;

comment on function public._leave_year_start(uuid, date) is 'Internal: the joining anniversary that starts the leave year containing an IST day.';

grant execute on function "public"."_leave_year_start"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_leave_year_start"(uuid, date) from public;

revoke all on function "public"."_leave_year_start"(uuid, date) from anon;

revoke all on function "public"."_leave_year_start"(uuid, date) from authenticated;
