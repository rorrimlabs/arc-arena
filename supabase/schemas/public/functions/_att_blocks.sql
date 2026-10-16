-- _att_blocks(staff, day) — the shifts a person is scheduled for on an IST day, as instants
--
-- Every staff_shifts assignment in force on p_day whose shift runs on that ISO weekday, as
-- [start_at, end_at) in UTC; a shift whose end_min <= start_min ends the next day. None = a week
-- off. Used by _att_day (status, break, late / early, extra hours), _att_close_time and the
-- leave day count.
-- Server-only: not executable by anon/authenticated.
create or replace function public._att_blocks (
  p_staff uuid,
  p_day   date
)
  returns table (
    shift_id  uuid,
    start_at  timestamp with time zone,
    end_at    timestamp with time zone,
    break_min integer
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select s.id,
         (p_day::timestamp + make_interval(mins => s.start_min - 330)) at time zone 'UTC',
         ((p_day + case when s.end_min <= s.start_min then 1 else 0 end)::timestamp
            + make_interval(mins => s.end_min - 330)) at time zone 'UTC',
         s.break_min
    from staff_shifts a
    join shifts s on s.id = a.shift_id
   where a.staff_id = p_staff
     and a.effective_from <= p_day
     and (a.effective_to is null or a.effective_to >= p_day)
     and extract(isodow from p_day)::smallint = any (s.days)
   order by 2;
$function$;

comment on function public._att_blocks(uuid, date) is 'Internal: the shift blocks (UTC start/end, break) a staff profile is scheduled for on an IST day; none = week off.';

grant execute on function "public"."_att_blocks"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_att_blocks"(uuid, date) from public;

revoke all on function "public"."_att_blocks"(uuid, date) from anon;

revoke all on function "public"."_att_blocks"(uuid, date) from authenticated;
