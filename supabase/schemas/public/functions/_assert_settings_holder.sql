-- _assert_settings_holder(arena) — refuse leaving an arena with nobody able to open Settings
--
-- Raises 'last_settings_holder' unless some active staff profile in p_arena
-- has role 'owner' or holds 'settings'. Called after the staff write in
-- add_staff_by_email and op_staff_update, so the raise rolls that write back.
-- SECURITY DEFINER (reads every profile of the arena).
-- Server-only: not executable by anon/authenticated.
create or replace function public._assert_settings_holder (
  p_arena uuid
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not exists (select 1 from staff_profiles where arena_id = p_arena and active
                   and (role = 'owner' or 'settings' = any(perms))) then
    raise exception 'last_settings_holder'
      using hint = 'someone must keep access to Settings';
  end if;
end;
$function$;

comment on function public._assert_settings_holder(uuid) is 'Internal: raise last_settings_holder unless at least one active profile in the arena is an owner or holds the settings permission.';

grant execute on function "public"."_assert_settings_holder"(uuid) to "postgres", "service_role";

revoke all on function "public"."_assert_settings_holder"(uuid) from public;

revoke all on function "public"._assert_settings_holder(p_arena uuid) from anon;

revoke all on function "public"._assert_settings_holder(p_arena uuid) from authenticated;
