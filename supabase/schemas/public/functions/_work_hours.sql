-- _work_hours(arena) — the arena's working-hours rules, defaults filled in
--
-- The stored 'work_hours' setting over the defaults: grace 10 min, early leave 15 min, break
-- after 300 min, exact rounding, full day 75 %, half day 40 %, standard day 480 min, extra
-- hours per day, week from Monday, auto clock-out 120 min after the shift end.
-- Server-only: not executable by anon/authenticated.
create or replace function public._work_hours (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('late_grace_min', 10, 'early_leave_min', 15, 'break_after_min', 300,
           'rounding', 'exact', 'full_day_pct', 75, 'half_day_pct', 40, 'standard_day_min', 480,
           'extra_basis', 'day', 'week_start', 1, 'auto_out_after_min', 120)
      || coalesce((select json from settings where arena_id = p_arena and key = 'work_hours'),
                  '{}'::jsonb);
$function$;

comment on function public._work_hours(uuid) is 'Internal: the arena''s work_hours setting merged over the defaults.';

grant execute on function "public"."_work_hours"(uuid) to "postgres", "service_role";

revoke all on function "public"."_work_hours"(uuid) from public;

revoke all on function "public"."_work_hours"(uuid) from anon;

revoke all on function "public"."_work_hours"(uuid) from authenticated;
