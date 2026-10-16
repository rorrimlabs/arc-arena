-- _pay_policy_settings(p) — validate a pay_policies.policy object
--
-- Every key required, nothing else (docs/STAFF_API.md): period_kind monthly | weekly | custom,
-- cycle_start_day 1–28, day_divisor calendar | 30 | 26 | scheduled, absent_factor 0–3,
-- lop_factor 0–3, half_day_factor 0–1, late_every 0–31 whole (0 = no late rule),
-- late_penalty_days 0–1, late_applies_to (a list of monthly / daily / hourly),
-- early_leave_counts_as_late bool, extra_multiplier 1–5, daily_paid_holidays bool.
-- Returns the object as stored. Raises invalid_pay_policy (hint names the field).
-- Server-only: used by op_pay_policy_add; not executable by anon/authenticated.
create or replace function public._pay_policy_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  c_keys constant text[] := array['period_kind', 'cycle_start_day', 'day_divisor', 'absent_factor',
    'lop_factor', 'half_day_factor', 'late_every', 'late_penalty_days', 'late_applies_to',
    'early_leave_counts_as_late', 'extra_multiplier', 'daily_paid_holidays'];
  c_nums constant text[][] := array[['cycle_start_day', '1', '28'], ['absent_factor', '0', '3'],
    ['lop_factor', '0', '3'], ['half_day_factor', '0', '1'], ['late_every', '0', '31'],
    ['late_penalty_days', '0', '1'], ['extra_multiplier', '1', '5']];
  v_out jsonb := '{}'::jsonb;
  v_n numeric;
  v_types text[];
  i int;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k where k <> all (c_keys))
     or not (p ?& c_keys) then
    raise exception 'invalid_pay_policy' using hint = 'every pay-rule field, and nothing else';
  end if;
  for i in 1 .. array_length(c_nums, 1) loop
    if jsonb_typeof(p->c_nums[i][1]) is distinct from 'number' then
      raise exception 'invalid_pay_policy' using hint = c_nums[i][1];
    end if;
    v_n := (p->>c_nums[i][1])::numeric;
    if v_n < c_nums[i][2]::numeric or v_n > c_nums[i][3]::numeric
       or (c_nums[i][1] in ('cycle_start_day', 'late_every') and v_n % 1 <> 0) then
      raise exception 'invalid_pay_policy'
        using hint = c_nums[i][1] || ': ' || c_nums[i][2] || '–' || c_nums[i][3];
    end if;
    v_out := v_out || jsonb_build_object(c_nums[i][1], v_n);
  end loop;
  if p->>'period_kind' not in ('monthly', 'weekly', 'custom') then
    raise exception 'invalid_pay_policy' using hint = 'period_kind: monthly, weekly or custom';
  end if;
  if p->>'day_divisor' not in ('calendar', '30', '26', 'scheduled') then
    raise exception 'invalid_pay_policy' using hint = 'day_divisor: calendar, 30, 26 or scheduled';
  end if;
  if jsonb_typeof(p->'late_applies_to') is distinct from 'array' then
    raise exception 'invalid_pay_policy' using hint = 'late_applies_to';
  end if;
  select coalesce(array_agg(distinct t order by t), '{}') into v_types
    from jsonb_array_elements_text(p->'late_applies_to') t;
  if not (v_types <@ array['daily', 'hourly', 'monthly']) then
    raise exception 'invalid_pay_policy' using hint = 'late_applies_to: monthly, daily, hourly';
  end if;
  if jsonb_typeof(p->'early_leave_counts_as_late') is distinct from 'boolean' then
    raise exception 'invalid_pay_policy' using hint = 'early_leave_counts_as_late';
  end if;
  if jsonb_typeof(p->'daily_paid_holidays') is distinct from 'boolean' then
    raise exception 'invalid_pay_policy' using hint = 'daily_paid_holidays';
  end if;
  return v_out || jsonb_build_object('period_kind', p->>'period_kind', 'day_divisor', p->>'day_divisor',
    'late_applies_to', to_jsonb(v_types), 'early_leave_counts_as_late', p->'early_leave_counts_as_late',
    'daily_paid_holidays', p->'daily_paid_holidays');
end;
$function$;

comment on function public._pay_policy_settings(jsonb) is
  'Validates a pay policy (period, day divisor, absent / LOP / half-day factors, late rule, extra-hours multiplier, daily holidays); raises invalid_pay_policy.';

grant execute on function "public"."_pay_policy_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_pay_policy_settings"(jsonb) from public;

revoke all on function "public"."_pay_policy_settings"(jsonb) from anon;

revoke all on function "public"."_pay_policy_settings"(jsonb) from authenticated;
