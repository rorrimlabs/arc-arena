-- app_is_owner(arena) — is the caller "owner level" in the arena?
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Clients reach it only through the
-- SECURITY INVOKER wrapper public.app_is_owner.
--
-- True when auth.uid() has an active staff profile in p_arena with role 'owner'
-- or holding money or reports (holding either makes a member owner level, the
-- same rule as the app's AppUser.isOwner). Gates add_staff_by_email and the
-- owner-only branches of op_staff_update. SECURITY DEFINER (reads staff_profiles).
-- Executable by authenticated so the public wrapper (called by the staff-admin
-- Edge Function) can reach it; not exposed over the Data API itself.
create or replace function private.app_is_owner (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or perms && array['money','reports'])
  );
$function$;

comment on function private.app_is_owner(uuid) is 'True when the signed-in user is owner level in the arena: an active profile with role owner, or holding the money or reports permission.';

grant execute
  on function "private"."app_is_owner"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."app_is_owner"(uuid) from public;

revoke all on function "private".app_is_owner(p_arena uuid) from anon;
