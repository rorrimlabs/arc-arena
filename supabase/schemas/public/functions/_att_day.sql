-- _att_day(staff, day, now) — one person's attendance on one IST day: status and minutes
--
-- The single calculation behind the floor's history, the dashboard calendar and the salary run
-- (docs/STAFF.md §4.1), so they can never disagree:
--   blocks   = the person's shifts that day (_att_block); sched = their length − the largest
--              break; none = a week off.
--   worked   = the day's active entries (an open one runs to p_now), whole minutes each,
--              minus the shift break once the total reaches work_hours.break_after_min (unless
--              a gap between entries already covers it), then rounded (work_hours.rounding).
--   extra    = every minute on a staff holiday or a week off; else the minutes beyond the
--              person's standard day.
--   leave    = the approved split for that day (leave_requests.day_split): units, paid units.
--   status   = holiday | week_off | on_leave (a whole day) | half_leave | present | late |
--              half_day | absent | upcoming (later days, or today before the shift has ended
--              with no clock-in; with one it reads present / late until the shift is over) |
--              not_employed (before joining / after leaving).
--              Present at >= full_day_pct of the scheduled minutes (half of them on a half-day
--              leave), half_day at >= half_day_pct, else absent. late = first clock-in after the
--              first shift start + grace; early = last clock-out before the last shift end −
--              early_leave_min (not on an automatic close).
--   units    = present_units (1, 0.5) and absent_units (1, 0.5) for the salary run.
-- Returns {day, status, sched_min, worked_min, regular_min, extra_min, late, early,
-- present_units, absent_units, half_day, leave_units, leave_paid, leave_lop, holiday,
-- holiday_paid, flags, open, entries}.
-- Server-only: not executable by anon/authenticated.
create or replace function public._att_day (
  p_staff uuid,
  p_day   date,
  p_now   timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
declare
  v_hr       record;
  v_wh       jsonb;
  v_blocks   int := 0;
  v_first    timestamptz;
  v_last_end timestamptz;
  v_len      int := 0;
  v_brk_max  int := 0;
  v_sched    int := 0;
  v_hol      staff_holidays;
  v_units    numeric := 0;
  v_paid     numeric := 0;
  e          attendance_entries;
  v_end      timestamptz;
  v_prev     timestamptz;
  v_gross    int := 0;
  v_gap      int := 0;
  v_first_in timestamptz;
  v_last_out timestamptz;
  v_open     boolean := false;
  v_auto     boolean := false;
  v_n        int := 0;
  v_flags    text[] := '{}';
  v_net      int;
  v_worked   int;
  v_extra    int;
  v_late     boolean := false;
  v_early    boolean := false;
  v_target   numeric;
  v_status   text;
  v_present  numeric := 0;
  v_absent   numeric := 0;
  v_halfday  boolean := false;
  v_today    date := _pr_ist_date(p_now);
begin
  select * into v_hr from _staff_hr(p_staff);
  if not found then return null; end if;
  if p_day < v_hr.joined_on or (v_hr.left_on is not null and p_day > v_hr.left_on) then
    return jsonb_build_object('day', p_day, 'status', 'not_employed', 'sched_min', 0,
      'worked_min', 0, 'regular_min', 0, 'extra_min', 0, 'late', false, 'early', false,
      'present_units', 0, 'absent_units', 0, 'half_day', false, 'leave_units', 0,
      'leave_paid', 0, 'leave_lop', 0, 'holiday', null, 'holiday_paid', false,
      'flags', '[]'::jsonb, 'open', false, 'entries', 0);
  end if;
  v_wh := _work_hours(v_hr.arena_id);

  select count(*), min(b.start_at), max(b.end_at),
         coalesce(sum(extract(epoch from b.end_at - b.start_at) / 60), 0)::int,
         coalesce(max(b.break_min), 0)
    into v_blocks, v_first, v_last_end, v_len, v_brk_max
    from _att_blocks(p_staff, p_day) b;
  v_sched := case when v_blocks > 0 then greatest(0, v_len - v_brk_max) else 0 end;

  select * into v_hol from staff_holidays where arena_id = v_hr.arena_id and day = p_day;

  select coalesce(sum((x->>'units')::numeric), 0), coalesce(sum((x->>'paid_units')::numeric), 0)
    into v_units, v_paid
    from leave_requests r, jsonb_array_elements(r.day_split) x
   where r.staff_id = p_staff and r.status in ('approved', 'cancel_pending')
     and r.from_date <= p_day and r.to_date >= p_day
     and (x->>'day')::date = p_day;

  for e in select * from attendance_entries
            where staff_id = p_staff and work_date = p_day and status = 'active'
            order by in_at loop
    v_n := v_n + 1;
    v_end := coalesce(e.out_at, greatest(p_now, e.in_at));
    if e.out_at is null then v_open := true; end if;
    if e.out_source = 'auto' then v_auto := true; end if;
    v_gross := v_gross + floor(extract(epoch from v_end - e.in_at) / 60)::int;
    if v_prev is not null then
      v_gap := greatest(v_gap, floor(extract(epoch from e.in_at - v_prev) / 60)::int);
    end if;
    v_prev := v_end;
    v_first_in := coalesce(v_first_in, e.in_at);
    v_last_out := v_end;
    v_flags := v_flags || e.flags;
  end loop;

  -- Break: once a day, when the day is long enough and no gap between entries already took it.
  v_net := greatest(0, v_gross - case
    when v_blocks > 0 and v_brk_max > 0 and v_gross >= (v_wh->>'break_after_min')::int
         and v_gap < v_brk_max then v_brk_max else 0 end);
  v_worked := case v_wh->>'rounding'
    when 'nearest_15' then (floor((v_net + 7.5) / 15) * 15)::int
    when 'down_15' then (floor(v_net / 15.0) * 15)::int
    else v_net end;

  if v_blocks > 0 and v_first_in is not null then
    v_late := v_first_in > v_first + make_interval(mins => (v_wh->>'late_grace_min')::int);
    v_early := not v_open and not v_auto
      and v_last_out < v_last_end - make_interval(mins => (v_wh->>'early_leave_min')::int);
  end if;

  if v_hol.id is not null or v_blocks = 0 then
    v_extra := v_worked;
  else
    v_extra := greatest(0, v_worked - v_hr.standard_day_min);
  end if;

  if v_hol.id is not null then
    v_status := 'holiday';
  elsif v_blocks = 0 then
    v_status := 'week_off';
  elsif v_units >= 1 then
    v_status := 'on_leave';
    if v_worked > 0 then v_flags := v_flags || 'worked_on_leave'::text; end if;
  elsif p_day > v_today or (p_day = v_today and p_now < v_last_end) then
    -- Not over yet: judged once the shift has ended (no absent / half-day before then).
    v_status := case when v_units > 0 then 'half_leave'
                     when v_n > 0 and v_late then 'late'
                     when v_n > 0 then 'present'
                     else 'upcoming' end;
  else
    v_target := case when v_units > 0 then v_sched / 2.0 else v_sched end;
    if v_units > 0 then
      v_status := 'half_leave';
      if v_worked >= v_target * (v_wh->>'half_day_pct')::int / 100 then v_present := 0.5;
      else v_absent := 0.5; end if;
    elsif v_worked >= v_target * (v_wh->>'full_day_pct')::int / 100 then
      v_status := case when v_late then 'late' else 'present' end;
      v_present := 1;
    elsif v_worked >= v_target * (v_wh->>'half_day_pct')::int / 100 then
      v_status := 'half_day';
      v_present := 0.5;
      v_halfday := true;
    else
      v_status := 'absent';
      v_absent := 1;
    end if;
  end if;

  return jsonb_build_object('day', p_day, 'status', v_status, 'sched_min', v_sched,
    'worked_min', v_worked, 'regular_min', v_worked - v_extra, 'extra_min', v_extra,
    'late', v_late and v_status in ('present', 'late', 'half_day', 'half_leave'),
    'early', v_early and v_status in ('present', 'late', 'half_day', 'half_leave'),
    'present_units', v_present, 'absent_units', v_absent, 'half_day', v_halfday,
    'leave_units', v_units, 'leave_paid', v_paid, 'leave_lop', v_units - v_paid,
    'holiday', v_hol.name, 'holiday_paid', coalesce(v_hol.paid, false),
    'flags', to_jsonb(array(select distinct f from unnest(v_flags) f order by f)),
    'open', v_open, 'entries', v_n);
end;
$function$;

comment on function public._att_day(uuid, date, timestamp with time zone) is 'Internal: one staff profile''s IST day: status, scheduled / worked / regular / extra minutes, late / early, present and absent units, leave split, holiday, flags. Shared by the floor, the dashboard and salary runs.';

grant execute on function "public"."_att_day"(uuid, date, timestamp with time zone) to "postgres", "service_role";

revoke all on function "public"."_att_day"(uuid, date, timestamp with time zone) from public;

revoke all on function "public"."_att_day"(uuid, date, timestamp with time zone) from anon;

revoke all on function "public"."_att_day"(uuid, date, timestamp with time zone) from authenticated;
