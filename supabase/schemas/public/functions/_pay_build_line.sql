-- _pay_build_line(run, staff) — (re)build one person's line of a salary run
--
-- docs/STAFF.md §4.2. Reads the run's rules_snapshot (pay_policy, work_hours), the person's
-- _att_day for every day of the period, their effective-dated pay rates, the owner's keep /
-- waive decisions and the adjustments. Only people with a pay rate in force by period_end who
-- were employed for part of the period get a line (any other line is removed).
--   monthly: base = Σ rate/N over employed days (N = days in the period: prorates joins,
--            exits and mid-period raises); suggested deductions per day at the day rate
--            (rate / day divisor): absent × absent_factor, LOP × lop_factor, half day ×
--            half_day_factor.
--   daily:   base = Σ (present units + paid leave + paid holiday if daily_paid_holidays) × rate.
--   hourly:  base = Σ regular hours × rate + paid leave × standard hours × rate.
--   extra hours (holiday / week-off minutes, and minutes beyond the standard day — or per week
--   with extra_basis week): with extra_hours_paid, × (own extra rate, else derived: monthly
--   day rate / standard hours, daily rate / standard hours, hourly rate) × extra_multiplier;
--   without it, hourly staff are still paid them at their rate, others are not.
--   late rule: floor(lates / late_every) × late_penalty_days days, for the pay types it applies
--   to (early leaves count as lates when early_leave_counts_as_late).
-- Each money component is computed exactly and rounded once to whole paise (half up). Applied
-- deductions are capped at gross (noted); adjustments are added; net = gross − deductions +
-- adjustments. Returns true when the person has a line.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pay_build_line (
  p_run   uuid,
  p_staff uuid
)
  returns boolean
  language plpgsql
  set search_path to 'public'
  AS $function$
declare
  r         salary_runs;
  v_hr      record;
  v_pol     jsonb;
  v_wh      jsonb;
  v_now     timestamptz := statement_timestamp();
  v_n       int;
  v_std_h   numeric;
  v_mult    numeric;
  v_week    boolean;
  v_facts   jsonb[] := '{}';
  f         jsonb;
  d         date;
  i         int;
  v_rate    staff_pay_rates;
  v_last    staff_pay_rates;
  v_rates   jsonb := '[]'::jsonb;
  v_sched_days int := 0;
  v_div     numeric;
  v_dayrate numeric;
  v_hourly  numeric;
  v_units   numeric;
  -- tallies
  c_sched int := 0; c_present numeric := 0; c_late int := 0; c_early int := 0; c_half int := 0;
  c_absent numeric := 0; c_paid numeric := 0; c_lop numeric := 0; c_hol int := 0; c_off int := 0;
  v_worked int := 0; v_regular int := 0; v_extra int := 0;
  -- money (exact until the end)
  m_base numeric := 0; m_extra numeric := 0;
  m_absent numeric := 0; m_lop numeric := 0; m_half numeric := 0; m_late numeric := 0;
  u_absent numeric := 0; u_lop numeric := 0; u_half numeric := 0; u_late numeric := 0;
  v_no_rate_until date;
  -- week basis
  v_wend    date;
  v_wk_work int; v_wk_sched int; v_wk_off int; v_wx int;
  wf        jsonb;
  wd        date;
  -- out
  v_ded     jsonb := '[]'::jsonb;
  v_ded_sum bigint := 0;
  v_gross   bigint;
  v_adj     bigint;
  v_notes   jsonb := '[]'::jsonb;
  v_dec     salary_deduction_decisions;
  v_code    text; v_label text; v_amt numeric; v_u numeric; v_rp numeric;
begin
  select * into r from salary_runs where id = p_run;
  select * into v_hr from _staff_hr(p_staff);
  delete from salary_run_lines where run_id = p_run and staff_id = p_staff;
  if not exists (select 1 from staff_pay_rates where staff_id = p_staff and effective_from <= r.period_end)
     or v_hr.joined_on > r.period_end
     or (v_hr.left_on is not null and v_hr.left_on < r.period_start) then
    return false;
  end if;

  v_pol := r.rules_snapshot->'pay_policy';
  v_wh := r.rules_snapshot->'work_hours';
  v_n := r.period_end - r.period_start + 1;
  v_std_h := v_hr.standard_day_min / 60.0;
  v_mult := (v_pol->>'extra_multiplier')::numeric;
  v_week := v_wh->>'extra_basis' = 'week';

  for d in select g::date from generate_series(r.period_start, r.period_end, interval '1 day') g loop
    f := _att_day(p_staff, d, v_now);
    v_facts := v_facts || f;
    if (f->>'sched_min')::int > 0 and f->>'status' not in ('holiday', 'not_employed') then
      v_sched_days := v_sched_days + 1;
    end if;
  end loop;
  v_div := case v_pol->>'day_divisor' when 'calendar' then v_n when '30' then 30
                                      when '26' then 26 else greatest(v_sched_days, 1) end;

  for i in 1 .. array_length(v_facts, 1) loop
    f := v_facts[i];
    d := (f->>'day')::date;
    continue when f->>'status' = 'not_employed';
    -- Tallies (whatever the pay type).
    if (f->>'sched_min')::int > 0 and f->>'status' <> 'holiday' then c_sched := c_sched + 1; end if;
    c_present := c_present + (f->>'present_units')::numeric;
    c_absent := c_absent + (f->>'absent_units')::numeric;
    c_paid := c_paid + (f->>'leave_paid')::numeric;
    c_lop := c_lop + (f->>'leave_lop')::numeric;
    if (f->>'late')::boolean then c_late := c_late + 1; end if;
    if (f->>'early')::boolean then c_early := c_early + 1; end if;
    if (f->>'half_day')::boolean then c_half := c_half + 1; end if;
    if f->>'status' = 'holiday' then c_hol := c_hol + 1; end if;
    if f->>'status' = 'week_off' then c_off := c_off + 1; end if;
    v_worked := v_worked + (f->>'worked_min')::int;
    if not v_week then
      v_regular := v_regular + (f->>'regular_min')::int;
      v_extra := v_extra + (f->>'extra_min')::int;
    end if;

    select * into v_rate from staff_pay_rates
     where staff_id = p_staff and effective_from <= d order by effective_from desc limit 1;
    if not found then
      v_no_rate_until := d;
      continue;
    end if;
    v_last := v_rate;
    if not v_rates @> jsonb_build_array(jsonb_build_object('effective_from', v_rate.effective_from)) then
      v_rates := v_rates || jsonb_build_array(jsonb_build_object('effective_from', v_rate.effective_from,
        'pay_type', v_rate.pay_type, 'base_paise', v_rate.base_paise,
        'extra_hours_paid', v_rate.extra_hours_paid, 'extra_hourly_paise', v_rate.extra_hourly_paise));
    end if;
    v_dayrate := case v_rate.pay_type when 'monthly' then v_rate.base_paise / v_div
                                      when 'daily' then v_rate.base_paise::numeric
                                      else v_rate.base_paise * v_std_h end;

    if v_rate.pay_type = 'monthly' then
      m_base := m_base + v_rate.base_paise::numeric / v_n;
      u_absent := u_absent + (f->>'absent_units')::numeric;
      m_absent := m_absent + (f->>'absent_units')::numeric * v_dayrate * (v_pol->>'absent_factor')::numeric;
      u_lop := u_lop + (f->>'leave_lop')::numeric;
      m_lop := m_lop + (f->>'leave_lop')::numeric * v_dayrate * (v_pol->>'lop_factor')::numeric;
      if (f->>'half_day')::boolean then
        u_half := u_half + 1;
        m_half := m_half + v_dayrate * (v_pol->>'half_day_factor')::numeric;
      end if;
    elsif v_rate.pay_type = 'daily' then
      v_units := (f->>'present_units')::numeric + (f->>'leave_paid')::numeric
        + case when f->>'status' = 'holiday' and (f->>'holiday_paid')::boolean
                    and (v_pol->>'daily_paid_holidays')::boolean then 1 else 0 end;
      m_base := m_base + v_units * v_rate.base_paise;
    else
      m_base := m_base + (case when v_week then (f->>'worked_min')::int else (f->>'regular_min')::int end)
                         / 60.0 * v_rate.base_paise
                       + (f->>'leave_paid')::numeric * v_std_h * v_rate.base_paise;
    end if;

    if not v_week then
      v_hourly := coalesce(v_rate.extra_hourly_paise::numeric, case v_rate.pay_type
        when 'monthly' then v_rate.base_paise / v_div / v_std_h
        when 'daily' then v_rate.base_paise / v_std_h else v_rate.base_paise::numeric end);
      if v_rate.extra_hours_paid then
        m_extra := m_extra + (f->>'extra_min')::int / 60.0 * v_hourly * v_mult;
      elsif v_rate.pay_type = 'hourly' then
        m_extra := m_extra + (f->>'extra_min')::int / 60.0 * v_rate.base_paise;
      end if;
    end if;
  end loop;

  -- Extra hours per week: each week ending inside the period, priced at that day's rate.
  if v_week then
    for v_wend in select g::date from generate_series(r.period_start, r.period_end, interval '1 day') g
                   where extract(isodow from g)::int = ((v_wh->>'week_start')::int + 5) % 7 + 1 loop
      v_wk_work := 0; v_wk_sched := 0; v_wk_off := 0;
      for wd in select g::date from generate_series(v_wend - 6, v_wend, interval '1 day') g loop
        wf := case when wd >= r.period_start then v_facts[wd - r.period_start + 1]
                   else _att_day(p_staff, wd, v_now) end;
        continue when wf->>'status' = 'not_employed';
        if wf->>'status' in ('holiday', 'week_off') then
          v_wk_off := v_wk_off + (wf->>'worked_min')::int;
        else
          v_wk_work := v_wk_work + (wf->>'worked_min')::int;
          v_wk_sched := v_wk_sched + 1;
        end if;
      end loop;
      v_wx := greatest(0, v_wk_work - v_hr.standard_day_min * v_wk_sched) + v_wk_off;
      v_extra := v_extra + v_wx;
      select * into v_rate from staff_pay_rates
       where staff_id = p_staff and effective_from <= v_wend order by effective_from desc limit 1;
      continue when not found or v_wx = 0;
      v_hourly := coalesce(v_rate.extra_hourly_paise::numeric, case v_rate.pay_type
        when 'monthly' then v_rate.base_paise / v_div / v_std_h
        when 'daily' then v_rate.base_paise / v_std_h else v_rate.base_paise::numeric end);
      if v_rate.pay_type = 'hourly' then
        -- Base paid every hour; the extra ones move to the extra line.
        m_base := m_base - v_wx / 60.0 * v_rate.base_paise;
        m_extra := m_extra + v_wx / 60.0 * case when v_rate.extra_hours_paid
          then v_hourly * v_mult else v_rate.base_paise end;
      elsif v_rate.extra_hours_paid then
        m_extra := m_extra + v_wx / 60.0 * v_hourly * v_mult;
      end if;
    end loop;
    v_regular := v_worked - v_extra;
  end if;

  if v_last.id is null then
    select * into v_last from staff_pay_rates
     where staff_id = p_staff and effective_from <= r.period_end order by effective_from desc limit 1;
  end if;

  -- Late rule, by the pay type in force at the end of the period.
  if (v_pol->>'late_every')::int > 0 and v_last.id is not null
     and v_pol->'late_applies_to' ? v_last.pay_type then
    u_late := floor((c_late + case when (v_pol->>'early_leave_counts_as_late')::boolean
                                   then c_early else 0 end)::numeric / (v_pol->>'late_every')::int)
              * (v_pol->>'late_penalty_days')::numeric;
    m_late := u_late * case v_last.pay_type when 'monthly' then v_last.base_paise / v_div
                                            when 'daily' then v_last.base_paise::numeric
                                            else v_last.base_paise * v_std_h end;
  end if;

  -- Suggested deductions with the owner's keep / waive decision (no decision = kept).
  foreach v_code in array array['absent', 'lop_leave', 'half_day', 'late'] loop
    v_u := case v_code when 'absent' then u_absent when 'lop_leave' then u_lop
                       when 'half_day' then u_half else u_late end;
    v_amt := case v_code when 'absent' then m_absent when 'lop_leave' then m_lop
                         when 'half_day' then m_half else m_late end;
    continue when round(v_amt) = 0;
    v_label := case v_code when 'absent' then 'Absent' when 'lop_leave' then 'Leave without pay (LOP)'
                           when 'half_day' then 'Half days'
                           else 'Late marks (' || (c_late + case when (v_pol->>'early_leave_counts_as_late')::boolean
                                  then c_early else 0 end) || ')' end;
    v_rp := case when v_u = 0 then 0 else v_amt / v_u end;
    select * into v_dec from salary_deduction_decisions
     where run_id = p_run and staff_id = p_staff and code = v_code;
    v_ded := v_ded || jsonb_build_array(jsonb_build_object('code', v_code, 'label', v_label,
      'units', v_u, 'rate_paise', round(v_rp), 'amount_paise', round(v_amt)::bigint,
      'applied', coalesce(v_dec.applied, true), 'note', v_dec.note));
    if coalesce(v_dec.applied, true) then v_ded_sum := v_ded_sum + round(v_amt)::bigint; end if;
  end loop;

  v_gross := round(m_base)::bigint + round(m_extra)::bigint;
  if v_ded_sum > v_gross then
    v_notes := v_notes || to_jsonb('Deductions capped at gross pay'::text);
    v_ded_sum := v_gross;
  end if;
  if v_no_rate_until is not null then
    v_notes := v_notes || to_jsonb(('No pay rate before ' || to_char(v_no_rate_until + 1, 'DD Mon YYYY'))::text);
  end if;
  select coalesce(sum(amount_paise), 0) into v_adj from salary_adjustments
   where run_id = p_run and staff_id = p_staff;

  insert into salary_run_lines(arena_id, run_id, staff_id, staff_name, pay_type, rates, day_counts,
      worked_min, regular_min, extra_min, base_paise, extra_paise, gross_paise, deductions,
      deductions_paise, adjustments_paise, net_paise, days, notes)
    values (r.arena_id, p_run, p_staff, v_hr.name, v_last.pay_type, v_rates,
      jsonb_build_object('scheduled', c_sched, 'present', c_present, 'late', c_late,
        'half_day', c_half, 'absent', c_absent, 'paid_leave', c_paid, 'lop_leave', c_lop,
        'holiday', c_hol, 'week_off', c_off, 'early', c_early),
      v_worked, v_regular, v_extra, round(m_base)::bigint, round(m_extra)::bigint, v_gross, v_ded,
      v_ded_sum, v_adj, v_gross - v_ded_sum + v_adj, to_jsonb(v_facts), v_notes);
  return true;
end;
$function$;

comment on function public._pay_build_line(uuid, uuid) is 'Internal: (re)build one staff member''s salary-run line: timesheet, base, extra hours, suggested deductions with keep / waive, adjustments and net, in paise.';

grant execute on function "public"."_pay_build_line"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_pay_build_line"(uuid, uuid) from public;

revoke all on function "public"."_pay_build_line"(uuid, uuid) from anon;

revoke all on function "public"."_pay_build_line"(uuid, uuid) from authenticated;
