-- attendance_days(arena, from, to, staff) — attendance by person and IST day
--
-- Lives in `private`; clients reach it only through the SECURITY INVOKER wrapper
-- public.attendance_days.
--
-- One row per person and day in [p_from, p_to] (at most 62 days) from _att_day — the same
-- figures salary runs pay: {staff_id, staff_name, work_date, status, sched_min, worked_min,
-- regular_min, extra_min, late, early, present_units, absent_units, half_day, leave_paid,
-- leave_lop, holiday_name, flags, open, entries}. p_staff = one person; null = every staff
-- member who tracks attendance (active, or with entries in the range). Forgotten clock-ins are
-- closed first (_att_close_stale) so every reader sees the same stretches.
-- Who: your own p_staff always; anyone else (or null) needs attendance_review or payroll.
-- Errors: forbidden; invalid_period. SECURITY DEFINER.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.attendance_days (
  p_arena uuid,
  p_from  date,
  p_to    date,
  p_staff uuid default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_out jsonb;
begin
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from >= 62 then
    raise exception 'invalid_period' using hint = 'p_from to p_to, at most 62 days';
  end if;
  if (p_staff is null or not exists (select 1 from staff_profiles
        where id = p_staff and arena_id = p_arena and user_id = auth.uid()))
     and not exists (select 1 from private.app_arena_ids_with(array['attendance_review', 'payroll']) a
                      where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs attendance_review';
  end if;
  perform _att_close_stale(p_arena, p_staff, v_now);
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', s.id, 'staff_name', s.name,
           'work_date', f->>'day', 'status', f->>'status', 'sched_min', f->'sched_min',
           'worked_min', f->'worked_min', 'regular_min', f->'regular_min',
           'extra_min', f->'extra_min', 'late', f->'late', 'early', f->'early',
           'present_units', f->'present_units', 'absent_units', f->'absent_units',
           'half_day', f->'half_day', 'leave_paid', f->'leave_paid', 'leave_lop', f->'leave_lop',
           'holiday_name', f->'holiday', 'flags', f->'flags', 'open', f->'open',
           'entries', f->'entries') order by s.sort_order, s.name, d), '[]'::jsonb)
    into v_out
    from staff_profiles s
    cross join lateral generate_series(p_from, p_to, interval '1 day') d
    cross join lateral _att_day(s.id, d::date, v_now) f
   where s.arena_id = p_arena
     and (case when p_staff is not null then s.id = p_staff
               else (select h.tracks from _staff_hr(s.id) h)
                    and (s.active or exists (select 1 from attendance_entries e
                          where e.staff_id = s.id and e.work_date between p_from and p_to)) end);
  return v_out;
end;
$function$;

comment on function private.attendance_days(uuid, date, date, uuid) is 'Client API: attendance per person and IST day (status, scheduled / worked / extra minutes, leave, flags) — your own, or everyone''s with attendance_review / payroll.';

grant execute on function "private"."attendance_days"(uuid, date, date, uuid) to "authenticated", "postgres", "service_role";

revoke all on function "private"."attendance_days"(uuid, date, date, uuid) from public;

revoke all on function "private"."attendance_days"(uuid, date, date, uuid) from anon;
