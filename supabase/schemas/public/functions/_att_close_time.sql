-- _att_close_time(staff, work_date, in_at) — when a forgotten clock-in counts as ended
--
-- The end of the person's last shift block that day still after the clock-in; without one (no
-- shift, or clocked in after it ended), clock-in + their standard day. Never later than
-- clock-in + the arena's max_open_hours. Used to close forgotten clock-ins (_att_close_stale,
-- op_attendance_punch); the entry is flagged auto_out and put up for review.
-- Server-only: not executable by anon/authenticated.
create or replace function public._att_close_time (
  p_staff     uuid,
  p_work_date date,
  p_in_at     timestamp with time zone
)
  returns timestamp with time zone
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select least(
    coalesce(
      (select max(b.end_at) from _att_blocks(p_staff, p_work_date) b where b.end_at > p_in_at),
      p_in_at + make_interval(mins => (select h.standard_day_min from _staff_hr(p_staff) h))),
    p_in_at + make_interval(hours => (_attendance_rules(
      (select arena_id from staff_profiles where id = p_staff))->>'max_open_hours')::int));
$function$;

comment on function public._att_close_time(uuid, date, timestamp with time zone) is 'Internal: when a forgotten clock-in counts as ended: the shift end that day, else clock-in + standard day, capped at max_open_hours.';

grant execute on function "public"."_att_close_time"(uuid, date, timestamp with time zone) to "postgres", "service_role";

revoke all on function "public"."_att_close_time"(uuid, date, timestamp with time zone) from public;

revoke all on function "public"."_att_close_time"(uuid, date, timestamp with time zone) from anon;

revoke all on function "public"."_att_close_time"(uuid, date, timestamp with time zone) from authenticated;
