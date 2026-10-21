-- _leave_working_days(staff, from, to, half_day) — the days a leave request takes off
--
-- Each IST day in [p_from, p_to] on which the person is scheduled (_att_blocks) and that is not
-- a staff holiday: week-offs and holidays inside a leave are not leave. units is 1, or 0.5 for
-- a half-day request (single day). Used by op_leave_request (days) and op_leave_decide
-- (day_split).
-- Server-only: not executable by anon/authenticated.
create or replace function public._leave_working_days (
  p_staff    uuid,
  p_from     date,
  p_to       date,
  p_half_day text
)
  returns table (
    day   date,
    units numeric
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select d::date, case when p_half_day = 'none' then 1.0 else 0.5 end
    from generate_series(p_from, p_to, interval '1 day') d
   where exists (select 1 from _att_blocks(p_staff, d::date))
     and not exists (select 1 from staff_holidays h
                      where h.arena_id = (select arena_id from staff_profiles where id = p_staff)
                        and h.day = d::date)
   order by 1;
$function$;

comment on function public._leave_working_days(uuid, date, date, text) is 'Internal: the scheduled, non-holiday IST days of a leave request with their units (1, or 0.5 for a half day).';

grant execute on function "public"."_leave_working_days"(uuid, date, date, text) to "postgres", "service_role";

revoke all on function "public"."_leave_working_days"(uuid, date, date, text) from public;

revoke all on function "public"."_leave_working_days"(uuid, date, date, text) from anon;

revoke all on function "public"."_leave_working_days"(uuid, date, date, text) from authenticated;
