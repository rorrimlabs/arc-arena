-- _pay_policy(arena, day) — the pay rules in force on an IST day, defaults filled in
--
-- The newest pay_policies row with effective_from <= p_day over the defaults: monthly from day
-- 1, calendar-day divisor, absent / LOP 1 day, half day 0.5, every 3 lates = 0.5 day for
-- monthly and daily staff (early leaves count), extra-hours multiplier 1, daily staff unpaid on
-- holidays.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pay_policy (
  p_arena uuid,
  p_day   date
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('period_kind', 'monthly', 'cycle_start_day', 1,
           'day_divisor', 'calendar', 'absent_factor', 1, 'lop_factor', 1, 'half_day_factor', 0.5,
           'late_every', 3, 'late_penalty_days', 0.5, 'late_applies_to', '["daily","monthly"]'::jsonb,
           'early_leave_counts_as_late', true, 'extra_multiplier', 1, 'daily_paid_holidays', false)
      || coalesce((select policy from pay_policies where arena_id = p_arena and effective_from <= p_day
                    order by effective_from desc limit 1), '{}'::jsonb);
$function$;

comment on function public._pay_policy(uuid, date) is 'Internal: the pay rules in force on an IST day, merged over the defaults.';

grant execute on function "public"."_pay_policy"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_pay_policy"(uuid, date) from public;

revoke all on function "public"."_pay_policy"(uuid, date) from anon;

revoke all on function "public"."_pay_policy"(uuid, date) from authenticated;
