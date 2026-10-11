-- arena_ops — owner/staff authorization, enforced on the backend.
--
-- 0002 drove every policy off app_arena_ids() (membership only), so owner and
-- staff were indistinguishable server-side: any member could rewrite pricing,
-- the catalog and audit rows, write sessions/payments directly (bypassing the
-- RPC guarantees), and even set their own staff_profiles.role='owner'. This
-- migration closes that: role-aware helpers, an owner/staff/RPC-only policy
-- split, and the first-owner bootstrap. It mirrors the client model exactly —
-- app_user.isOwner = holds money OR reports; staff default perms are
-- {start,bill,discount,members} (seed_data.dart).

-- Role-aware helpers -----------------------------------------------------------
-- A user is an owner of an arena iff role='owner' OR their perms overlap
-- {money, reports} (the exact app_user.isOwner rule).
create or replace function app_owner_arena_ids() returns setof uuid as $$
  select arena_id from staff_profiles
   where user_id = auth.uid()
     and active
     and (role = 'owner' or perms && array['money','reports']);
$$ language sql stable security definer set search_path = public;

create or replace function app_is_owner(p_arena uuid) returns boolean as $$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or perms && array['money','reports'])
  );
$$ language sql stable security definer set search_path = public;

-- Fine-grained capability check. An owner implicitly holds every perm.
create or replace function app_has_perm(p_arena uuid, p_perm text) returns boolean as $$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or p_perm = any(perms))
  );
$$ language sql stable security definer set search_path = public;

-- First-owner bootstrap --------------------------------------------------------
-- staff_profiles is owner-write only (below), so a brand-new arena with no owner
-- could never get one. This promotes the first authenticated caller of an
-- owner-less arena to owner, and refuses once an owner exists.
create or replace function claim_arena(
  p_arena uuid,
  p_name  text default null
) returns uuid as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  perform 1 from arenas where id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'arena'; end if;
  -- "Owner" per the system definition (role OR money/reports perms), so an
  -- arena owned only via perms cannot be re-claimed or seized.
  if exists (select 1 from staff_profiles
               where arena_id = p_arena
                 and (role = 'owner' or perms && array['money','reports'])) then
    raise exception 'arena_already_claimed' using errcode = '42501';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_uid, coalesce(p_name, 'Owner'), 'owner',
      array['start','bill','discount','members','stations','money','reports','settings'], true)
  on conflict (user_id, arena_id) do update
    set role = 'owner',
        perms = array['start','bill','discount','members','stations','money','reports','settings'],
        active = true
  returning id into v_id;
  return v_id;
end;
$$ language plpgsql security definer set search_path = public;

-- Config / catalog / pricing: OWNER-WRITE (supersede 0002's member writes) -----
do $$
declare
  t text;
  owner_write text[] := array[
    'activities','resources','resource_activities','rate_cards','rate_bands',
    'rates','billing_policies','holidays','game_categories','games','game_controls'
  ];
begin
  foreach t in array owner_write loop
    execute format('drop policy if exists %I on %I', 'p_ins_' || t, t);
    execute format('drop policy if exists %I on %I', 'p_upd_' || t, t);
    execute format(
      'create policy %I on %I for insert with check (arena_id in (select app_owner_arena_ids()))',
      'p_ins_' || t, t);
    execute format(
      'create policy %I on %I for update using (arena_id in (select app_owner_arena_ids())) with check (arena_id in (select app_owner_arena_ids()))',
      'p_upd_' || t, t);
  end loop;
end $$;

-- RPC-only transactional tables (0002-covered set): drop member writes, keep
-- member SELECT, and REVOKE direct DML so only the SECURITY DEFINER RPCs write.
do $$
declare
  t text;
  rpc_only text[] := array[
    'sessions','session_extensions','session_charges','payments','audit_log'
  ];
begin
  foreach t in array rpc_only loop
    execute format('drop policy if exists %I on %I', 'p_ins_' || t, t);
    execute format('drop policy if exists %I on %I', 'p_upd_' || t, t);
    execute format('revoke insert, update, delete on %I from authenticated, anon', t);
  end loop;
end $$;

-- 0004 tables 0002 never covered + session_segments: enable RLS, member SELECT,
-- RPC-only writes (no write policy; REVOKE direct DML).
do $$
declare
  t text;
  new_rpc text[] := array[
    'session_segments','group_sessions','group_assignments','group_extensions',
    'group_charges','group_payments'
  ];
begin
  foreach t in array new_rpc loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for select using (arena_id in (select app_arena_ids()))',
      'p_sel_' || t, t);
    execute format('revoke insert, update, delete on %I from authenticated, anon', t);
  end loop;
end $$;

-- 0004 config tables 0002 never covered: enable RLS, member SELECT, OWNER-WRITE.
do $$
declare
  t text;
  new_owner text[] := array['controllers','game_resources','settings'];
begin
  foreach t in array new_owner loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for select using (arena_id in (select app_arena_ids()))',
      'p_sel_' || t, t);
    execute format(
      'create policy %I on %I for insert with check (arena_id in (select app_owner_arena_ids()))',
      'p_ins_' || t, t);
    execute format(
      'create policy %I on %I for update using (arena_id in (select app_owner_arena_ids())) with check (arena_id in (select app_owner_arena_ids()))',
      'p_upd_' || t, t);
  end loop;
end $$;

-- staff_profiles: owner-write only (closes the role='owner' self-escalation). --
drop policy if exists p_ins_staff on staff_profiles;
drop policy if exists p_upd_staff on staff_profiles;
create policy p_ins_staff on staff_profiles for insert
  with check (arena_id in (select app_owner_arena_ids()));
create policy p_upd_staff on staff_profiles for update
  using (arena_id in (select app_owner_arena_ids()))
  with check (arena_id in (select app_owner_arena_ids()));

-- arenas: owner-only UPDATE.
drop policy if exists p_upd_arenas on arenas;
create policy p_upd_arenas on arenas for update
  using (id in (select app_owner_arena_ids()))
  with check (id in (select app_owner_arena_ids()));

-- Execute surface: RPCs are SECURITY DEFINER and gate themselves on membership /
-- role, so expose them to signed-in users only (defense-in-depth).
revoke execute on function
  start_session(uuid, jsonb, text),
  reconfigure_session(uuid, timestamptz, uuid, text, uuid, int, uuid, text),
  extend_session(uuid, int, timestamptz, bigint, text, uuid, text),
  end_session(uuid, timestamptz, jsonb, bigint, boolean),
  record_payment(uuid, bigint, text, text, text, text, text, uuid),
  void_session(uuid, text),
  claim_arena(uuid, text)
  from anon, public;
grant execute on function
  start_session(uuid, jsonb, text),
  reconfigure_session(uuid, timestamptz, uuid, text, uuid, int, uuid, text),
  extend_session(uuid, int, timestamptz, bigint, text, uuid, text),
  end_session(uuid, timestamptz, jsonb, bigint, boolean),
  record_payment(uuid, bigint, text, text, text, text, text, uuid),
  void_session(uuid, text),
  claim_arena(uuid, text)
  to authenticated;

-- Helper functions: signed-in users only. app_arena_ids()/app_owner_arena_ids()
-- are evaluated inside RLS policies as the querying role, so authenticated must
-- keep EXECUTE; app_is_owner/app_has_perm run only inside SECURITY DEFINER
-- bodies but keeping them granted to authenticated is harmless.
revoke execute on function
  app_arena_ids(), app_owner_arena_ids(), app_is_owner(uuid), app_has_perm(uuid, text)
  from anon, public;
grant execute on function
  app_arena_ids(), app_owner_arena_ids(), app_is_owner(uuid), app_has_perm(uuid, text)
  to authenticated;

-- RLS does not cover TRUNCATE; strip it from clients so the append-only /
-- no-hard-delete guarantee cannot be bypassed on any table.
revoke truncate on all tables in schema public from anon, authenticated;
