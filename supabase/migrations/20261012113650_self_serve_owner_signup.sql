set local check_function_bodies = off;

create or replace function public._create_arena_with_owner (
  p_user       uuid,
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_arena uuid;
begin
  insert into arenas(name) values (coalesce(nullif(btrim(p_arena_name), ''), 'Arena'))
    returning id into v_arena;
  perform _seed_arena_catalog(v_arena);
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, p_user, coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      array['start','bill','discount','members','stations','money','reports','settings'], true);
  return v_arena;
end;
$function$;

create or replace function public.bootstrap_owner (
  p_email      text,
  p_arena_name text,
  p_owner_name text default null::text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_user uuid; v_confirmed timestamptz;
begin
  select id, email_confirmed_at into v_user, v_confirmed
    from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create the login first: Authentication → Users → Add user';
  end if;
  if v_confirmed is null then
    raise exception 'account_not_confirmed'
      using hint = 'tick "Auto Confirm User" when adding the user, or confirm it';
  end if;
  return _create_arena_with_owner(v_user, p_arena_name, p_owner_name);
end;
$function$;

create or replace function public.create_my_arena (
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_user      uuid := auth.uid();
  v_confirmed timestamptz;
  v_arena     text := btrim(coalesce(p_arena_name, ''));
  v_owner     text := btrim(coalesce(p_owner_name, ''));
begin
  if v_user is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  select email_confirmed_at into v_confirmed from auth.users where id = v_user;
  if not found then
    raise exception 'no_account' using hint = 'sign up again';
  end if;
  if v_confirmed is null then
    raise exception 'account_not_confirmed'
      using hint = 'enter the code we e-mailed you to confirm the address';
  end if;
  if v_arena = '' or length(v_arena) > 80 then
    raise exception 'invalid_name' using hint = 'the arena name must be 1 to 80 characters';
  end if;
  if v_owner = '' or length(v_owner) > 80 then
    raise exception 'invalid_name' using hint = 'your name must be 1 to 80 characters';
  end if;
  -- Serialise this login's calls until commit, then check what it already owns.
  perform pg_advisory_xact_lock(hashtextextended('create_my_arena:' || v_user::text, 0));
  if exists (select 1 from staff_profiles where user_id = v_user and role = 'owner') then
    raise exception 'arena_limit' using hint = 'this login already owns an arena';
  end if;
  return _create_arena_with_owner(v_user, v_arena, v_owner);
end;
$function$;

comment on function "public"."_create_arena_with_owner"(uuid, text, text) is
  'Internal: create an arena with the default catalog and make the given login its owner with every permission. Shared by bootstrap_owner and create_my_arena; callers validate the login first.';

comment on function "public"."create_my_arena"(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

comment on table "public"."arenas" is 'One gaming centre (tenant). Every arena-scoped row references it via arena_id; created by bootstrap_owner() or create_my_arena().';

revoke all on function "public"."_create_arena_with_owner"(uuid, text, text) from public;

grant execute
  on function "public"."_create_arena_with_owner"(uuid, text, text)
  to "postgres", "service_role";

revoke all on function "public"."create_my_arena"(text, text) from public;

grant execute
  on function "public"."create_my_arena"(text, text)
  to "authenticated", "postgres", "service_role";
