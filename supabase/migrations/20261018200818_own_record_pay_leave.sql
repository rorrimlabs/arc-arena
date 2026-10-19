set local check_function_bodies = off;

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
  perform _own_record(p_arena, v_staff);
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

create or replace function public.op_leave_adjust (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff  uuid := (p->>'staff_id')::uuid;
  v_days   numeric := (p->>'days')::numeric;
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_ys     date;
begin
  perform _need(p_arena, 'leave_approve');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  perform _own_record(p_arena, v_staff);
  if v_reason is null then raise exception 'reason_required'; end if;
  if v_days is null or v_days = 0 or (v_days * 2) % 1 <> 0 or abs(v_days) > 366 then
    raise exception 'invalid_payload' using hint = 'days: a non-zero number of half days';
  end if;
  v_ys := _leave_year_start(v_staff, _pr_ist_date(statement_timestamp()));
  insert into leave_adjustments(arena_id, staff_id, year_start, days, reason, created_by)
    values (p_arena, v_staff, v_ys, v_days, v_reason, auth.uid());
  return jsonb_build_object('year_start', v_ys);
end;
$function$;

create or replace function public.op_pay_rate_add (
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
  v_from  date := (p->>'effective_from')::date;
  v_type  text := p->>'pay_type';
  v_base  numeric := (p->>'base_paise')::numeric;
  v_paid  boolean := coalesce((p->>'extra_hours_paid')::boolean, false);
  v_xrate numeric := (p->>'extra_hourly_paise')::numeric;
begin
  perform _need(p_arena, 'payroll');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  perform _own_record(p_arena, v_staff);
  if v_from is null then raise exception 'invalid_rate' using hint = 'effective_from'; end if;
  if v_type is null or v_type not in ('monthly', 'daily', 'hourly') then
    raise exception 'invalid_rate' using hint = 'pay_type: monthly, daily or hourly';
  end if;
  if v_base is null or v_base < 0 or v_base % 1 <> 0 then
    raise exception 'invalid_rate' using hint = 'base_paise: whole paise';
  end if;
  if v_xrate is not null and (not v_paid or v_xrate < 0 or v_xrate % 1 <> 0) then
    raise exception 'invalid_rate' using hint = 'extra_hourly_paise: whole paise, with extra_hours_paid';
  end if;
  if exists (select 1 from salary_runs where arena_id = p_arena and status = 'finalised'
              and period_end >= v_from) then
    raise exception 'rate_in_finalised_period'
      using hint = 'pay up to ' || (select max(period_end) from salary_runs
                                    where arena_id = p_arena and status = 'finalised') || ' is finalised';
  end if;
  insert into staff_pay_rates(id, arena_id, staff_id, effective_from, pay_type, base_paise,
      extra_hours_paid, extra_hourly_paise, note, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff, v_from, v_type, v_base::bigint, v_paid,
      v_xrate::bigint, nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid());
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_salary_adjustment_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  r       salary_runs;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_kind  text := p->>'kind';
  v_amt   numeric := (p->>'amount_paise')::numeric;
  v_note  text := nullif(btrim(coalesce(p->>'note', '')), '');
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'run_id')::uuid);
  if v_note is null then raise exception 'note_required'; end if;
  if v_kind is null or v_kind not in ('bonus', 'advance', 'deduction') then
    raise exception 'invalid_payload' using hint = 'kind: bonus, advance or deduction';
  end if;
  if v_amt is null or v_amt <= 0 or v_amt % 1 <> 0 then
    raise exception 'invalid_payload' using hint = 'amount_paise: whole paise above 0';
  end if;
  if not exists (select 1 from salary_run_lines where run_id = r.id and staff_id = v_staff) then
    raise exception 'not_found' using hint = 'line';
  end if;
  perform _own_record(p_arena, v_staff);
  insert into salary_adjustments(id, arena_id, run_id, staff_id, kind, amount_paise, note, created_by)
    values ((p->>'id')::uuid, p_arena, r.id, v_staff, v_kind,
            case when v_kind = 'bonus' then v_amt else -v_amt end::bigint, v_note, auth.uid());
  perform _pay_rebuild_run(r.id, v_staff);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = v_staff));
end;
$function$;

create or replace function public.op_salary_adjustment_reverse (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  a      salary_adjustments;
  r      salary_runs;
  v_note text := nullif(btrim(coalesce(p->>'note', '')), '');
begin
  perform _need(p_arena, 'payroll');
  select * into a from salary_adjustments
   where id = (p->>'reverses_id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'adjustment'; end if;
  perform _own_record(p_arena, a.staff_id);
  r := _pay_draft(p_arena, a.run_id);
  if v_note is null then raise exception 'note_required'; end if;
  if a.kind = 'reversal' then raise exception 'invalid_payload' using hint = 'a reversal cannot be reversed'; end if;
  begin
    insert into salary_adjustments(id, arena_id, run_id, staff_id, kind, amount_paise, note,
        reverses_id, created_by)
      values ((p->>'id')::uuid, p_arena, a.run_id, a.staff_id, 'reversal', -a.amount_paise,
              v_note, a.id, auth.uid());
  exception when unique_violation then
    if exists (select 1 from salary_adjustments where reverses_id = a.id) then
      raise exception 'already_reversed';
    end if;
    raise;
  end;
  perform _pay_rebuild_run(r.id, a.staff_id);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = a.staff_id));
end;
$function$;

create or replace function public.op_salary_run_set_deduction (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  r       salary_runs;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_code  text := p->>'code';
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'run_id')::uuid);
  if v_code is null or v_code not in ('absent', 'lop_leave', 'half_day', 'late')
     or (p->>'applied') is null then
    raise exception 'invalid_payload' using hint = 'code and applied';
  end if;
  if not exists (select 1 from salary_run_lines where run_id = r.id and staff_id = v_staff) then
    raise exception 'not_found' using hint = 'line';
  end if;
  perform _own_record(p_arena, v_staff);
  insert into salary_deduction_decisions(arena_id, run_id, staff_id, code, applied, note, decided_by)
    values (p_arena, r.id, v_staff, v_code, (p->>'applied')::boolean,
            nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid())
  on conflict (run_id, staff_id, code) do update set applied = excluded.applied,
      note = excluded.note, decided_by = excluded.decided_by, decided_at = statement_timestamp();
  perform _pay_rebuild_run(r.id, v_staff);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = v_staff));
end;
$function$;
