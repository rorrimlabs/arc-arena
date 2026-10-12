-- bootstrap_owner(email, arena_name, owner_name) — create a new arena with its first owner
--
-- Operator tool, run from the SQL editor: the login must already exist and be
-- confirmed in auth.users. Creates the arena through _create_arena_with_owner
-- (name defaults to 'Arena', starter catalog, role='owner' profile with all
-- eight permissions, name defaults to 'Owner'). Unlike the app's
-- create_my_arena it has no one-arena limit: every call creates another arena.
-- Raises 'no_account' or 'account_not_confirmed'. Returns the new arena id.
-- SECURITY DEFINER. Server-only: not executable by anon/authenticated.
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

comment on function public.bootstrap_owner(text, text, text) is 'Operator-only (SQL editor): create a new arena with the default catalog and make an existing, confirmed login its owner. Returns the arena id; each call creates a new arena.';

grant execute on function "public"."bootstrap_owner"(text, text, text) to "postgres", "service_role";

revoke all on function "public"."bootstrap_owner"(text, text, text) from public;

revoke all on function "public".bootstrap_owner(p_email text, p_arena_name text, p_owner_name text) from anon;

revoke all on function "public".bootstrap_owner(p_email text, p_arena_name text, p_owner_name text) from authenticated;
