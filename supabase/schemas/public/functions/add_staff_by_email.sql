-- add_staff_by_email(arena, email, name, perms) — link an existing login to an arena as staff
--
-- Finds the auth.users row by email (trimmed, case-insensitive) and upserts a
-- role='staff' staff_profiles row for it: name defaults to 'Staff', perms are
-- replaced (not merged) and the profile is (re)activated. It never creates a
-- login; the owner adds the account in Authentication -> Users first.
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
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_user uuid;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
  end if;
  perform _assert_known_perms(p_perms);
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create their login first: Authentication → Users → Add user';
  end if;
  -- Nobody changes their own access (same rule as op_staff_update): re-adding
  -- yourself would rewrite your own perms.
  if v_user = auth.uid() then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'you cannot change your own permissions';
  end if;
  if exists (select 1 from staff_profiles
              where arena_id = p_arena and user_id = v_user and role = 'owner') then
    raise exception 'owner_profile'
      using hint = 'that login is an owner of this arena; edit it in Settings → Staff';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user, coalesce(nullif(btrim(p_name), ''), 'Staff'), 'staff',
      coalesce(p_perms, '{}'), true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  -- Re-adding someone with fewer permissions must not strand Settings.
  perform _assert_settings_holder(p_arena);
  return v_user;
end;
$function$;

comment on function public.add_staff_by_email(uuid, text, text, text[]) is 'Client API (owner level): link an existing login to the arena as a staff profile with the given permissions, reactivating and overwriting an existing staff profile. Refuses owners'' profiles, unknown permissions, and leaving nobody with Settings.';

grant execute
  on function "public"."add_staff_by_email"(uuid, text, text, text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."add_staff_by_email"(uuid, text, text, text[]) from public;

revoke all on function "public".add_staff_by_email(p_arena uuid, p_email text, p_name text, p_perms text[]) from anon;
