-- _attendance_rules(arena) — the arena's attendance rules, defaults filled in
--
-- The stored 'attendance' setting (validated by _attendance_settings) over the defaults a new
-- arena starts with: no geofence (every punch's position is unknown), outside_rule flag,
-- min_accuracy_m 50, mock_rule block, max_open_hours 14. op_attendance_punch reads it once per
-- punch and copies the part it used into the punch (geofence_snapshot).
-- Server-only: not executable by anon/authenticated.
create or replace function public._attendance_rules (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('geofence', null, 'outside_rule', 'flag', 'min_accuracy_m', 50,
                            'mock_rule', 'block', 'max_open_hours', 14)
      || coalesce((select json from settings where arena_id = p_arena and key = 'attendance'),
                  '{}'::jsonb);
$function$;

comment on function public._attendance_rules(uuid) is 'Internal: the arena''s attendance setting merged over the defaults (no geofence, flag, 50 m, block mock, 14 h).';

grant execute on function "public"."_attendance_rules"(uuid) to "postgres", "service_role";

revoke all on function "public"."_attendance_rules"(uuid) from public;

revoke all on function "public"._attendance_rules(p_arena uuid) from anon;

revoke all on function "public"._attendance_rules(p_arena uuid) from authenticated;
