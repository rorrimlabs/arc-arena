-- station_type_catalog() — client API: the global list of ready-made station types
--
-- What an owner picks from when setting up a venue (dashboard onboarding and
-- Settings → Station types → Add from catalog). Picking one sends the ordinary
-- activity.upsert with these values, and the owner's copy is then theirs to edit:
-- nothing here is checked by any op, and it carries no prices (owners enter them).
-- Each entry: code (an activities code), name, group (gaming | cue | sports | arcade | other:
-- how onboarding groups and pre-ticks them), uses_controllers, uses_games, duration_model
-- (as activities), unit_minutes (the rate's unit when pricing it) and noun (what one of
-- its resources is called: station | table | ground | court | machine | room).
-- Data lives in the function body so it ships with the schema to every environment.
-- Reads no table; runs as the caller.
create or replace function public.station_type_catalog ()
  returns jsonb
  language sql
  immutable
  security invoker
  set search_path to ''
  AS $function$
  select '[
    {"code": "PS5", "name": "PlayStation 5", "group": "gaming", "uses_controllers": true,
     "uses_games": true, "duration_model": "hourly", "unit_minutes": 60, "noun": "station"},
    {"code": "XBOX", "name": "Xbox", "group": "gaming", "uses_controllers": true,
     "uses_games": true, "duration_model": "hourly", "unit_minutes": 60, "noun": "station"},
    {"code": "PC", "name": "Gaming PC", "group": "gaming", "uses_controllers": false,
     "uses_games": true, "duration_model": "hourly", "unit_minutes": 60, "noun": "station"},
    {"code": "VR", "name": "VR", "group": "gaming", "uses_controllers": false,
     "uses_games": true, "duration_model": "unit", "unit_minutes": 30, "noun": "station"},
    {"code": "SIM", "name": "Racing simulator", "group": "gaming", "uses_controllers": false,
     "uses_games": true, "duration_model": "hourly", "unit_minutes": 60, "noun": "station"},
    {"code": "POOL", "name": "Pool table", "group": "cue", "uses_controllers": false,
     "uses_games": false, "duration_model": "hourly", "unit_minutes": 60, "noun": "table"},
    {"code": "SNOOKER", "name": "Snooker table", "group": "cue", "uses_controllers": false,
     "uses_games": false, "duration_model": "hourly", "unit_minutes": 60, "noun": "table"},
    {"code": "TURF", "name": "Football turf", "group": "sports", "uses_controllers": false,
     "uses_games": false, "duration_model": "unit", "unit_minutes": 60, "noun": "ground"},
    {"code": "CRICKET", "name": "Cricket net", "group": "sports", "uses_controllers": false,
     "uses_games": false, "duration_model": "unit", "unit_minutes": 60, "noun": "ground"},
    {"code": "BADMINTON", "name": "Badminton court", "group": "sports", "uses_controllers": false,
     "uses_games": false, "duration_model": "unit", "unit_minutes": 60, "noun": "court"},
    {"code": "ARCADE", "name": "Arcade machine", "group": "arcade", "uses_controllers": false,
     "uses_games": false, "duration_model": "hourly", "unit_minutes": 60, "noun": "machine"},
    {"code": "LOUNGE", "name": "Lounge", "group": "other", "uses_controllers": false,
     "uses_games": false, "duration_model": "flat_hourly", "unit_minutes": 60, "noun": "room"}
  ]'::jsonb;
$function$;

comment on function public.station_type_catalog() is 'Client API: the global catalog of ready-made station types (code, name, group, flags, duration model, rate unit, resource noun) an owner picks from; reads no table and carries no prices.';

revoke all on function "public"."station_type_catalog"() from public;

revoke all on function "public".station_type_catalog() from anon;

revoke all on function "public".station_type_catalog() from authenticated;

grant execute on function "public"."station_type_catalog"() to "authenticated", "postgres", "service_role";
