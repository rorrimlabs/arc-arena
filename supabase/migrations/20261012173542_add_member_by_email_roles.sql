set local check_function_bodies = off;

drop function "public"."add_staff_by_email"(uuid, text, text, text[]);

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

comment on function "public"."add_member_by_email"(uuid, text, text, text, text[]) is
  'Client API: link an existing login to the arena as staff (owner level caller; perms as given) or as a co-owner (owner caller; every permission; promotes an existing staff profile). Refuses existing owners, the caller themselves, unknown permissions and leaving nobody with Settings.';

comment on function "public"."add_staff_by_email"(uuid, text, text, text[]) is
  'Client API (owner level): link an existing login to the arena as a staff profile with the given permissions, reactivating and overwriting an existing staff profile. Refuses owners'' profiles, unknown permissions, and leaving nobody with Settings.';

revoke all on function "public"."add_member_by_email"(uuid, text, text, text, text[]) from public;

grant execute
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."add_staff_by_email"(uuid, text, text, text[]) from public;

grant execute
  on function "public"."add_staff_by_email"(uuid, text, text, text[])
  to "authenticated", "postgres", "service_role";
