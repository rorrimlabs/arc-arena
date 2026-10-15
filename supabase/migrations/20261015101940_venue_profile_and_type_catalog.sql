set local check_function_bodies = off;

create or replace function public._venue_profile (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k where k <> 'resource_noun') then
    raise exception 'invalid_venue_profile' using hint = 'an object of resource_noun';
  end if;
  if jsonb_typeof(p->'resource_noun') is distinct from 'string'
     or p->>'resource_noun' not in ('station', 'table', 'ground', 'court', 'machine', 'room') then
    raise exception 'invalid_venue_profile'
      using hint = 'resource_noun: station, table, ground, court, machine or room';
  end if;
  return jsonb_build_object('resource_noun', p->>'resource_noun');
end;
$function$;

create or replace function public.op_settings_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_json jsonb := p->'json';
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours', 'floor_options', 'discount_options', 'venue_profile') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  elsif p->>'key' = 'discount_options' then
    v_json := _discount_options(p->'json');
  elsif p->>'key' = 'venue_profile' then
    v_json := _venue_profile(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

create or replace function public.station_type_catalog()
  returns jsonb
  language sql
  immutable
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

comment on function "public"."_venue_profile"(jsonb) is 'Validates the venue_profile setting (resource_noun: what the venue calls its stations, tables, grounds…); raises invalid_venue_profile.';

comment on function "public"."station_type_catalog"() is 'Client API: the global catalog of ready-made station types (code, name, group, flags, duration model, rate unit, resource noun) an owner picks from; reads no table and carries no prices.';

revoke all on function "public"."_venue_profile"(jsonb) from public;

grant execute on function "public"."_venue_profile"(jsonb) to "postgres", "service_role";

revoke all on function "public"."station_type_catalog"() from public;

grant execute
  on function "public"."station_type_catalog"()
  to "authenticated", "postgres", "service_role";
