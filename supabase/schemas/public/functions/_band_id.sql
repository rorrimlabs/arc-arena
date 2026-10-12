-- _band_id(p_arena, p_code) — resolve a rate band code to its id, creating it if missing.
--
-- Inserts rate_bands(code, name = initcap(code)) when the arena has no band with that code.
-- Used by op_rate_upsert.
-- Server-only: not executable by anon/authenticated.
create or replace function public._band_id (
  p_arena uuid,
  p_code  text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v uuid;
begin
  select id into v from rate_bands where arena_id = p_arena and code = p_code;
  if not found then
    insert into rate_bands(arena_id, code, name) values (p_arena, p_code, initcap(p_code))
      returning id into v;
  end if;
  return v;
end;
$function$;

comment on function public._band_id(uuid, text) is 'Resolves a rate band code to its id within an arena, creating the band when absent.';

grant execute on function "public"."_band_id"(uuid, text) to "postgres", "service_role";

revoke all on function "public"."_band_id"(uuid, text) from public;

revoke all on function "public"._band_id(p_arena uuid, p_code text) from anon;

revoke all on function "public"._band_id(p_arena uuid, p_code text) from authenticated;
