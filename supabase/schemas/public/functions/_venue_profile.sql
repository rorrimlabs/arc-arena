-- _venue_profile(p) — validate the arena's venue profile (settings key 'venue_profile').
--
-- Shape: {resource_noun: station | table | ground | court | machine | room}, nothing else.
-- resource_noun is what the venue calls the things it rents out ("Add your first table");
-- labels only, never pricing or availability. Returns the object as stored. Raises
-- invalid_venue_profile (hint names the bad field) otherwise.
-- Server-only: used by op_settings_save; not executable by anon/authenticated.
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

comment on function public._venue_profile(jsonb) is
  'Validates the venue_profile setting (resource_noun: what the venue calls its stations, tables, grounds…); raises invalid_venue_profile.';

grant execute on function "public"."_venue_profile"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_venue_profile"(jsonb) from public;

revoke all on function "public"._venue_profile(p jsonb) from anon;

revoke all on function "public"._venue_profile(p jsonb) from authenticated;
