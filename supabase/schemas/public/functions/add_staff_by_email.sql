-- add_staff_by_email(arena, email, name, perms) — link an existing login to an arena as staff
--
-- The floor app's original staff call, kept for it: add_member_by_email with
-- role 'staff' (same checks, errors and result). Upserts a role='staff'
-- staff_profiles row: name defaults to 'Staff', perms are replaced (not
-- merged) and the profile is (re)activated. It never creates a login.
-- SECURITY DEFINER. Caller must be owner level in p_arena (app_is_owner).
-- Raises 'forbidden' (42501), 'invalid_permission', 'no_account', 'owner_profile'
-- (the login is an owner here) and 'last_settings_holder'. Returns the user id.
-- Client API: callable by signed-in users (authenticated).
create or replace function public.add_staff_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_perms text[]
)
  returns uuid
  language sql
  security definer
  set search_path to 'public'
  AS $function$
  select add_member_by_email(p_arena, p_email, p_name, 'staff', p_perms);
$function$;

comment on function public.add_staff_by_email(uuid, text, text, text[]) is 'Client API (owner level): link an existing login to the arena as a staff profile with the given permissions, reactivating and overwriting an existing staff profile. Refuses owners'' profiles, unknown permissions, and leaving nobody with Settings.';

grant execute
  on function "public"."add_staff_by_email"(uuid, text, text, text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."add_staff_by_email"(uuid, text, text, text[]) from public;

revoke all on function "public".add_staff_by_email(p_arena uuid, p_email text, p_name text, p_perms text[]) from anon;
