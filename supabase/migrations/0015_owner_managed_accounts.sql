-- 0015 — Owner-managed accounts (internal shop app, no public registration).
--
-- Before: anyone could sign up, and any signed-in account could call
-- create_arena and become the owner of a new arena. Now:
--   * Sign-up is switched off at the Auth level (config.toml locally; the
--     hosted dashboard toggle "Allow new users to sign up" = OFF).
--   * Accounts (owner and staff) are created by the owner in the Supabase
--     dashboard: Authentication → Users → Add user → Create new user.
--   * The FIRST owner is attached to a new arena by bootstrap_owner(), run once
--     from the SQL editor (database access required — not callable by the app).
--   * create_arena is no longer callable by the app.
--   * add_staff_by_email (0012) is unchanged in behaviour: an owner links an
--     EXISTING account to the arena with chosen permissions. It never creates
--     an Auth user (verified: an unknown e-mail raises no_account and adds no
--     row to auth.users). Only its hint text changes, to point at the dashboard.

revoke execute on function create_arena(text, text) from public, anon, authenticated;

-- bootstrap_owner: one-time initial setup. Run as the database owner in the
-- SQL editor after creating the owner's login in the dashboard:
--   select bootstrap_owner('owner@example.com', 'My Arena', 'Owner Name');
-- Creates the arena with the starter catalog and makes that account its owner.
create or replace function bootstrap_owner(
  p_email text, p_arena_name text, p_owner_name text default null
) returns uuid as $$
declare v_user uuid; v_confirmed timestamptz; v_arena uuid;
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
  insert into arenas(name) values (coalesce(nullif(btrim(p_arena_name), ''), 'Arena'))
    returning id into v_arena;
  perform _seed_arena_catalog(v_arena);
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, v_user, coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      array['start','bill','discount','members','stations','money','reports','settings'], true);
  return v_arena;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function bootstrap_owner(text, text, text) from public, anon, authenticated;

-- Same behaviour as 0012; the hint now matches owner-managed accounts.
create or replace function add_staff_by_email(
  p_arena uuid, p_email text, p_name text, p_perms text[]
) returns uuid as $$
declare v_user uuid; v_id uuid;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
  end if;
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create their login first: Authentication → Users → Add user';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user, coalesce(nullif(btrim(p_name), ''), 'Staff'), 'staff',
      coalesce(p_perms, '{}'), true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, perms = excluded.perms, active = true,
        updated_at = statement_timestamp()
  returning id into v_id;
  return v_user;
end;
$$ language plpgsql security definer set search_path = public;
