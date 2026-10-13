-- create_my_arena(arena_name, owner_name) — self-serve sign-up: the caller creates an arena and owns it
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Clients reach it only through the
-- SECURITY INVOKER wrapper public.create_my_arena.
--
-- The app's route to ownership: a person signs up (e-mail + password), confirms
-- the e-mail with the 6-digit code, then calls this. Creates the arena with the
-- default catalog and makes auth.uid() its owner (_create_arena_with_owner).
-- One arena per login: refuses with 'arena_limit' once the caller owns any
-- arena (active or not); an operator can still add more with bootstrap_owner.
-- Calls from one login are serialised (advisory lock) so two devices racing
-- cannot both pass the check. Raises 'forbidden' (42501, no session),
-- 'no_account', 'account_not_confirmed', 'invalid_name' and 'arena_limit'.
-- Returns the new arena id. SECURITY DEFINER.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.create_my_arena (
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

comment on function private.create_my_arena(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

grant execute on function "private"."create_my_arena"(text, text) to "authenticated", "postgres", "service_role";

revoke all on function "private"."create_my_arena"(text, text) from public;

revoke all on function "private".create_my_arena(p_arena_name text, p_owner_name text) from anon;
