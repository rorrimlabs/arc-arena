-- op_hr_profile_save — sync op 'hr_profile.save': a staff member's HR facts
--
-- Permission: payroll.
-- Payload: staff_id, and any of joined_on, left_on, tracks_attendance, employee_code,
--   paid_leave_days (0–366 in halves), standard_day_min (60–1440). A key left out keeps its
--   value; an explicit null clears it (back to the default).
-- Checks / errors: forbidden; not_found (hint staff); invalid_payload (hint names the field).
-- Writes: staff_hr_profiles (upsert). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_hr_profile_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff uuid := (p->>'staff_id')::uuid;
  v_old   staff_hr_profiles;
  v_hr    record;
  v_new   staff_hr_profiles;
begin
  perform _need(p_arena, 'payroll');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  select * into v_old from staff_hr_profiles where staff_id = v_staff;
  select * into v_hr from _staff_hr(v_staff);
  v_new.staff_id := v_staff;
  v_new.arena_id := p_arena;
  v_new.joined_on := case when p ? 'joined_on' then (p->>'joined_on')::date else v_old.joined_on end;
  v_new.left_on := case when p ? 'left_on' then (p->>'left_on')::date else v_old.left_on end;
  v_new.tracks_attendance := case when p ? 'tracks_attendance'
    then coalesce((p->>'tracks_attendance')::boolean, true) else coalesce(v_old.tracks_attendance, v_hr.tracks) end;
  v_new.employee_code := case when p ? 'employee_code' then nullif(btrim(p->>'employee_code'), '')
    else v_old.employee_code end;
  v_new.paid_leave_days := case when p ? 'paid_leave_days' then (p->>'paid_leave_days')::numeric
    else v_old.paid_leave_days end;
  v_new.standard_day_min := case when p ? 'standard_day_min' then (p->>'standard_day_min')::int
    else v_old.standard_day_min end;
  if v_new.left_on is not null and v_new.joined_on is not null and v_new.left_on < v_new.joined_on then
    raise exception 'invalid_payload' using hint = 'left_on is before joined_on';
  end if;
  if v_new.paid_leave_days is not null
     and (v_new.paid_leave_days < 0 or v_new.paid_leave_days > 366 or (v_new.paid_leave_days * 2) % 1 <> 0) then
    raise exception 'invalid_payload' using hint = 'paid_leave_days: 0–366, in halves';
  end if;
  if v_new.standard_day_min is not null and v_new.standard_day_min not between 60 and 1440 then
    raise exception 'invalid_payload' using hint = 'standard_day_min: 60–1440';
  end if;
  insert into staff_hr_profiles(staff_id, arena_id, joined_on, left_on, tracks_attendance,
      employee_code, paid_leave_days, standard_day_min)
    values (v_new.staff_id, v_new.arena_id, v_new.joined_on, v_new.left_on, v_new.tracks_attendance,
      v_new.employee_code, v_new.paid_leave_days, v_new.standard_day_min)
  on conflict (staff_id) do update set joined_on = excluded.joined_on, left_on = excluded.left_on,
      tracks_attendance = excluded.tracks_attendance, employee_code = excluded.employee_code,
      paid_leave_days = excluded.paid_leave_days, standard_day_min = excluded.standard_day_min;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_hr_profile_save(uuid, jsonb) is 'Sync op hr_profile.save: a staff member''s joining/leaving dates, tracking, employee code and standard-day / paid-leave overrides (payroll).';

grant execute on function "public"."op_hr_profile_save"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_hr_profile_save"(uuid, jsonb) from public;

revoke all on function "public"."op_hr_profile_save"(uuid, jsonb) from anon;

revoke all on function "public"."op_hr_profile_save"(uuid, jsonb) from authenticated;
