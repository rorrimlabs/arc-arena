-- _att_work_date(staff, at) — the work day an entry starting at `at` belongs to
--
-- A shift counts from its start to its end on the day it starts, so a stretch belongs to the
-- shift it falls in, not to the calendar date of the clock-in: inside (or up to 2 hours before)
-- one of that IST day's shifts → that day; else inside the previous day's shift running past
-- midnight → the previous day; else up to 2 hours before a shift of the next day (one starting
-- just after midnight) → the next day; else the IST date of `at` (no shift: an unscheduled day).
-- Used by op_attendance_punch (clock-in) and op_attendance_correct, so _att_day, the dashboard
-- and salary all see one work day per shift.
-- Server-only: not executable by anon/authenticated.
create or replace function public._att_work_date (
  p_staff uuid,
  p_at    timestamptz
)
  returns date
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select coalesce(
    (select d from (values (0, _pr_ist_date(p_at)), (1, _pr_ist_date(p_at) - 1),
                           (2, _pr_ist_date(p_at) + 1)) v(n, d)
      where exists (select 1 from _att_blocks(p_staff, v.d) b
                     where p_at >= b.start_at - interval '2 hours' and p_at < b.end_at
                       and (v.n <> 1 or b.end_at > (v.d + 1)::timestamp at time zone 'Asia/Kolkata'))
      order by n limit 1),
    _pr_ist_date(p_at));
$function$;

comment on function public._att_work_date(uuid, timestamptz) is 'Internal: the work day of an entry starting at p_at: the shift it falls in (its start day), including an overnight shift from the day before; else the IST date.';

grant execute on function "public"."_att_work_date"(uuid, timestamptz) to "postgres", "service_role";

revoke all on function "public"."_att_work_date"(uuid, timestamptz) from public;

revoke all on function "public"."_att_work_date"(uuid, timestamptz) from anon;

revoke all on function "public"."_att_work_date"(uuid, timestamptz) from authenticated;
