-- _attendance_settings(p) — validate and normalise the arena's attendance rules (settings key
--   'attendance').
--
-- Shape: {geofence, outside_rule, min_accuracy_m, mock_rule, max_open_hours}, nothing else.
--   geofence: null (not set yet) or {lat: -90..90, lng: -180..180, radius_m: 20–5000 whole}
--     — the arena's location and how far from it a punch still counts as inside;
--   outside_rule: block | flag | allow — what happens to a punch that is outside the geofence
--     or whose position is unknown (no fix, location off, accuracy too poor): refused, accepted
--     and queued for review, or accepted with only a badge. block needs a geofence;
--   min_accuracy_m: 5–500 whole — a fix less accurate than this counts as unknown;
--   mock_rule: block | flag — what happens when the phone reports a mock (fake) location;
--   max_open_hours: 4–24 whole — a clock-in left open longer than this is closed automatically
--     at clock-in + max_open_hours and flagged.
-- Returns the same object (lat/lng rounded to 6 decimals). Raises invalid_attendance_settings
-- (hint names the bad field) otherwise.
-- Server-only: used by op_settings_save; not executable by anon/authenticated.
create or replace function public._attendance_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  v_fence  jsonb := p->'geofence';
  v_lat    numeric; v_lng numeric; v_radius numeric;
  v_acc    numeric; v_open numeric;
  v_outside text := p->>'outside_rule';
  v_mock    text := p->>'mock_rule';
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('geofence', 'outside_rule', 'min_accuracy_m', 'mock_rule',
                                 'max_open_hours'))
     or not (p ?& array['geofence', 'outside_rule', 'min_accuracy_m', 'mock_rule',
                        'max_open_hours']) then
    raise exception 'invalid_attendance_settings'
      using hint = 'an object of geofence, outside_rule, min_accuracy_m, mock_rule and max_open_hours';
  end if;

  if jsonb_typeof(v_fence) = 'null' then
    v_fence := null;
  elsif jsonb_typeof(v_fence) = 'object'
        and not exists (select 1 from jsonb_object_keys(v_fence) k where k not in ('lat', 'lng', 'radius_m'))
        and jsonb_typeof(v_fence->'lat') = 'number' and jsonb_typeof(v_fence->'lng') = 'number'
        and jsonb_typeof(v_fence->'radius_m') = 'number' then
    v_lat := (v_fence->>'lat')::numeric;
    v_lng := (v_fence->>'lng')::numeric;
    v_radius := (v_fence->>'radius_m')::numeric;
    if v_lat < -90 or v_lat > 90 or v_lng < -180 or v_lng > 180 then
      raise exception 'invalid_attendance_settings' using hint = 'geofence: lat -90..90, lng -180..180';
    end if;
    if v_radius % 1 <> 0 or v_radius < 20 or v_radius > 5000 then
      raise exception 'invalid_attendance_settings' using hint = 'geofence.radius_m: 20–5000 metres';
    end if;
    v_fence := jsonb_build_object('lat', round(v_lat, 6), 'lng', round(v_lng, 6),
                                  'radius_m', v_radius::int);
  else
    raise exception 'invalid_attendance_settings' using hint = 'geofence: null or {lat, lng, radius_m}';
  end if;

  if v_outside is null or v_outside not in ('block', 'flag', 'allow') then
    raise exception 'invalid_attendance_settings' using hint = 'outside_rule: block, flag or allow';
  end if;
  if v_outside = 'block' and v_fence is null then
    raise exception 'invalid_attendance_settings'
      using hint = 'outside_rule block needs the arena location (geofence)';
  end if;

  if jsonb_typeof(p->'min_accuracy_m') is distinct from 'number' then
    raise exception 'invalid_attendance_settings' using hint = 'min_accuracy_m';
  end if;
  v_acc := (p->>'min_accuracy_m')::numeric;
  if v_acc % 1 <> 0 or v_acc < 5 or v_acc > 500 then
    raise exception 'invalid_attendance_settings' using hint = 'min_accuracy_m: 5–500 metres';
  end if;

  if v_mock is null or v_mock not in ('block', 'flag') then
    raise exception 'invalid_attendance_settings' using hint = 'mock_rule: block or flag';
  end if;

  if jsonb_typeof(p->'max_open_hours') is distinct from 'number' then
    raise exception 'invalid_attendance_settings' using hint = 'max_open_hours';
  end if;
  v_open := (p->>'max_open_hours')::numeric;
  if v_open % 1 <> 0 or v_open < 4 or v_open > 24 then
    raise exception 'invalid_attendance_settings' using hint = 'max_open_hours: 4–24 hours';
  end if;

  return jsonb_build_object('geofence', coalesce(v_fence, 'null'::jsonb), 'outside_rule', v_outside,
    'min_accuracy_m', v_acc::int, 'mock_rule', v_mock, 'max_open_hours', v_open::int);
end;
$function$;

comment on function public._attendance_settings(jsonb) is
  'Validates and normalises the attendance setting (geofence, outside / mock rules, minimum GPS accuracy, auto-close hours); raises invalid_attendance_settings.';

grant execute on function "public"."_attendance_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_attendance_settings"(jsonb) from public;

revoke all on function "public"._attendance_settings(p jsonb) from anon;

revoke all on function "public"._attendance_settings(p jsonb) from authenticated;
