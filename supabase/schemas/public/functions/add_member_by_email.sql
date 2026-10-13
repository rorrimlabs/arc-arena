-- add_member_by_email(arena, email, name, role, perms) — link an existing login to an arena as staff or owner
--
-- Finds the auth.users row by email (trimmed, case-insensitive) and upserts its
-- staff_profiles row in p_arena, (re)activated:
--   role 'staff': perms are replaced (not merged), name defaults to 'Staff'.
--     Caller must be owner level in p_arena (app_is_owner).
--   role 'owner': a co-owner with every known permission, name defaults to
--     'Owner'; an existing staff profile is promoted. Caller must be an active
--     role='owner' member of p_arena (owner-level staff cannot make owners).
-- It never creates a login (the staff-admin Edge Function does that first).
-- Nobody adds or changes themselves; an existing owner profile is refused.
-- SECURITY DEFINER. Raises 'forbidden' (42501), 'invalid_role',
-- 'invalid_permission', 'no_account', 'owner_profile' and 'last_settings_holder'.
-- Returns the user id. Client API: callable by signed-in users (authenticated).
create or replace function public.add_member_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_user uuid; v_perms text[];
begin
  if p_role is null or p_role not in ('staff', 'owner') then
    raise exception 'invalid_role' using hint = 'role must be staff or owner';
  end if;
  if p_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add an owner';
    end if;
    v_perms := _known_perms();
  else
    if not app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
    end if;
    perform _assert_known_perms(p_perms);
    v_perms := coalesce(p_perms, '{}');
  end if;
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create their login first (admin dashboard → Users → Add)';
  end if;
  -- Nobody changes their own access (same rule as op_staff_update).
  if v_user = auth.uid() then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'you cannot change your own permissions';
  end if;
  if exists (select 1 from staff_profiles
              where arena_id = p_arena and user_id = v_user and role = 'owner') then
    raise exception 'owner_profile'
      using hint = 'that login is already an owner of this arena';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user,
      coalesce(nullif(btrim(p_name), ''), case p_role when 'owner' then 'Owner' else 'Staff' end),
      p_role, v_perms, true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, role = excluded.role, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  -- Re-adding someone with fewer permissions must not strand Settings.
  perform _assert_settings_holder(p_arena);
  return v_user;
end;
$function$;

comment on function public.add_member_by_email(uuid, text, text, text, text[]) is 'Client API: link an existing login to the arena as staff (owner level caller; perms as given) or as a co-owner (owner caller; every permission; promotes an existing staff profile). Refuses existing owners, the caller themselves, unknown permissions and leaving nobody with Settings.';

grant execute
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."add_member_by_email"(uuid, text, text, text, text[]) from public;

revoke all on function "public".add_member_by_email(p_arena uuid, p_email text, p_name text, p_role text, p_perms text[]) from anon;
