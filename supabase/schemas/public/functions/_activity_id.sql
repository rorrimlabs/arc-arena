-- _activity_id(p_arena, p_code) — resolve an activity code to its id.
--
-- Raises 'activity_missing' (hint: the code, or 'null') when the arena has no such activity.
-- Used by op_rate_upsert, op_resource_upsert, op_booking_create and op_booking_update.
-- Server-only: not executable by anon/authenticated.
create or replace function public._activity_id (
  p_arena uuid,
  p_code  text
)
  returns uuid
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v uuid;
begin
  select id into v from activities where arena_id = p_arena and code = p_code;
  if not found then raise exception 'activity_missing' using hint = coalesce(p_code, 'null'); end if;
  return v;
end;
$function$;

comment on function public._activity_id(uuid, text) is 'Resolves an activity code to its id within an arena, raising activity_missing when absent.';

grant execute on function "public"."_activity_id"(uuid, text) to "postgres", "service_role";

revoke all on function "public"."_activity_id"(uuid, text) from public;

revoke all on function "public"._activity_id(p_arena uuid, p_code text) from anon;

revoke all on function "public"._activity_id(p_arena uuid, p_code text) from authenticated;
