-- _work_hours_settings(p) — validate the arena's working-hours rules (settings key 'work_hours')
--
-- Shape (every key required, nothing else): late_grace_min 0–120, early_leave_min 0–240,
-- break_after_min 0–1440, rounding exact | nearest_15 | down_15, full_day_pct 1–100,
-- half_day_pct 1–99 (below full_day_pct), standard_day_min 60–1440, extra_basis day | week,
-- week_start 1–7 (ISO), auto_out_after_min 0–720; all whole numbers. These turn clocked time
-- into worked minutes and a day's status (_att_day) — the same number the salary run pays.
-- Returns the object as stored. Raises invalid_work_hours (hint names the field).
-- Server-only: used by op_settings_save; not executable by anon/authenticated.
create or replace function public._work_hours_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  c_ints constant text[][] := array[
    ['late_grace_min', '0', '120'], ['early_leave_min', '0', '240'],
    ['break_after_min', '0', '1440'], ['full_day_pct', '1', '100'], ['half_day_pct', '1', '99'],
    ['standard_day_min', '60', '1440'], ['week_start', '1', '7'],
    ['auto_out_after_min', '0', '720']];
  v_out jsonb := '{}'::jsonb;
  v_n numeric;
  i int;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('late_grace_min', 'early_leave_min', 'break_after_min', 'rounding',
                   'full_day_pct', 'half_day_pct', 'standard_day_min', 'extra_basis', 'week_start',
                   'auto_out_after_min'))
     or not (p ?& array['late_grace_min', 'early_leave_min', 'break_after_min', 'rounding',
                   'full_day_pct', 'half_day_pct', 'standard_day_min', 'extra_basis', 'week_start',
                   'auto_out_after_min']) then
    raise exception 'invalid_work_hours'
      using hint = 'every working-hours field, and nothing else';
  end if;
  for i in 1 .. array_length(c_ints, 1) loop
    if jsonb_typeof(p->c_ints[i][1]) is distinct from 'number' then
      raise exception 'invalid_work_hours' using hint = c_ints[i][1];
    end if;
    v_n := (p->>c_ints[i][1])::numeric;
    if v_n % 1 <> 0 or v_n < c_ints[i][2]::int or v_n > c_ints[i][3]::int then
      raise exception 'invalid_work_hours'
        using hint = c_ints[i][1] || ': ' || c_ints[i][2] || '–' || c_ints[i][3];
    end if;
    v_out := v_out || jsonb_build_object(c_ints[i][1], v_n::int);
  end loop;
  if (v_out->>'half_day_pct')::int >= (v_out->>'full_day_pct')::int then
    raise exception 'invalid_work_hours' using hint = 'half_day_pct must be below full_day_pct';
  end if;
  if p->>'rounding' is null or p->>'rounding' not in ('exact', 'nearest_15', 'down_15') then
    raise exception 'invalid_work_hours' using hint = 'rounding: exact, nearest_15 or down_15';
  end if;
  if p->>'extra_basis' is null or p->>'extra_basis' not in ('day', 'week') then
    raise exception 'invalid_work_hours' using hint = 'extra_basis: day or week';
  end if;
  return v_out || jsonb_build_object('rounding', p->>'rounding', 'extra_basis', p->>'extra_basis');
end;
$function$;

comment on function public._work_hours_settings(jsonb) is
  'Validates the work_hours setting (grace, early leave, break, rounding, full/half-day %, standard day, extra-hours basis, week start, auto clock-out grace); raises invalid_work_hours.';

grant execute on function "public"."_work_hours_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_work_hours_settings"(jsonb) from public;

revoke all on function "public"."_work_hours_settings"(jsonb) from anon;

revoke all on function "public"."_work_hours_settings"(jsonb) from authenticated;
