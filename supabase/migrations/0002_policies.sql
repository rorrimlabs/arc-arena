-- Row Level Security (spec §29, §32).
--
-- Every row belongs to an arena. A signed-in staff member may read and write
-- rows for arenas they are a member of (via staff_profiles). No DELETE policy
-- is defined anywhere, so RLS denies all deletes: historical data cannot be
-- destroyed by the app. Configuration changes happen through UPDATE
-- (e.g. disabling a game sets active=false).

-- Arenas a given auth user belongs to.
create or replace function app_arena_ids() returns setof uuid as $$
  -- `and active` matches the client's PermissionGuard active gate and the
  -- role-aware helpers: a deactivated staff member loses all access server-side.
  select arena_id from staff_profiles where user_id = auth.uid() and active;
$$ language sql stable security definer set search_path = public;

-- Uniform arena-scoped policies for every table that has an arena_id column.
do $$
declare
  t text;
  tables text[] := array[
    'activities','resources','resource_activities','customers',
    'rate_cards','rate_bands','rates','billing_policies','holidays',
    'game_categories','games','game_controls','bookings',
    'sessions','session_extensions','session_charges','payments','audit_log'
  ];
begin
  foreach t in array tables loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for select using (arena_id in (select app_arena_ids()))',
      'p_sel_' || t, t);
    execute format(
      'create policy %I on %I for insert with check (arena_id in (select app_arena_ids()))',
      'p_ins_' || t, t);
    execute format(
      'create policy %I on %I for update using (arena_id in (select app_arena_ids())) with check (arena_id in (select app_arena_ids()))',
      'p_upd_' || t, t);
  end loop;
end $$;

-- arenas: keyed by id rather than arena_id.
alter table arenas enable row level security;
create policy p_sel_arenas on arenas for select
  using (id in (select app_arena_ids()));
create policy p_upd_arenas on arenas for update
  using (id in (select app_arena_ids()))
  with check (id in (select app_arena_ids()));

-- staff_profiles: a member can see the roster of their own arena(s).
alter table staff_profiles enable row level security;
create policy p_sel_staff on staff_profiles for select
  using (arena_id in (select app_arena_ids()));
create policy p_ins_staff on staff_profiles for insert
  with check (arena_id in (select app_arena_ids()));
create policy p_upd_staff on staff_profiles for update
  using (arena_id in (select app_arena_ids()))
  with check (arena_id in (select app_arena_ids()));
