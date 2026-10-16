-- _leave_rules(arena) — the arena's leave rules, defaults filled in
--
-- The stored 'leave_rules' setting over the defaults: 12 paid days per leave year, half days
-- allowed, unplanned leave up to 7 days back.
-- Server-only: not executable by anon/authenticated.
create or replace function public._leave_rules (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('paid_leave_days', 12, 'half_day_allowed', true,
           'unplanned_backdate_days', 7)
      || coalesce((select json from settings where arena_id = p_arena and key = 'leave_rules'),
                  '{}'::jsonb);
$function$;

comment on function public._leave_rules(uuid) is 'Internal: the arena''s leave_rules setting merged over the defaults.';

grant execute on function "public"."_leave_rules"(uuid) to "postgres", "service_role";

revoke all on function "public"."_leave_rules"(uuid) from public;

revoke all on function "public"."_leave_rules"(uuid) from anon;

revoke all on function "public"."_leave_rules"(uuid) from authenticated;
