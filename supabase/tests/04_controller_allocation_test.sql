-- Controller allocation: schema mirror + the allocate/release RPCs and the
-- one-open-per-controller guarantee (brief §3, §4, §9).
begin;
create extension if not exists pgtap;
select * from no_plan();

-- Isolated fixture: this file works in its OWN arena (the same starter catalog
-- seed.sql uses), so whatever else is in the database — the dev seed, arenas
-- left by the two-device suite, a half-finished run — cannot change what it
-- sees. Created inside this transaction and rolled back with it.
insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000004'::uuid, 'pgtap 04');
select _seed_arena_catalog('e0000000-0000-4000-8000-000000000004'::uuid);

-- Schema parity (no auth needed).
select has_table('public', 'controller_allocations', 'controller_allocations exists');
select has_index('public', 'controller_allocations',
  'ux_one_open_allocation_per_controller', 'one-open-per-controller unique index');
select has_column('public', 'resources', 'current_mode', 'resources.current_mode (RIFT lock)');
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'controllers_status_check')
    like '%unavailable%',
  'controllers.status allows unavailable');
select is(
  (select relrowsecurity from pg_class where oid = 'public.controller_allocations'::regclass),
  true, 'RLS is enabled on controller_allocations');
select index_is_unique('public', 'controller_allocations',
  'ux_one_open_allocation_per_controller');

-- The race backstop (brief §9): even a DIRECT insert (bypassing the RPC, as the
-- table owner) cannot open a second allocation for a pad that already has one —
-- the trigger rejects it. Uses GHOST-1, which the RPC tests below never touch.
select lives_ok($$
  insert into controller_allocations(id, arena_id, controller_id, scope, resource_id, activity_code, started_at)
  select gen_random_uuid(), 'e0000000-0000-4000-8000-000000000004'::uuid, c.id, 'single', c.current_resource_id, 'PS5', now()
  from controllers c where c.label = 'GHOST-1' and c.arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid $$,
  'a first open allocation inserts');
select throws_ok($$
  insert into controller_allocations(id, arena_id, controller_id, scope, resource_id, activity_code, started_at)
  select gen_random_uuid(), 'e0000000-0000-4000-8000-000000000004'::uuid, c.id, 'single', c.current_resource_id, 'PS5', now()
  from controllers c where c.label = 'GHOST-1' and c.arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid $$,
  'controller_taken', 'a second OPEN allocation for the same pad is rejected');

-- Fixture: one owner.
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
    'authenticated','authenticated','owner@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select 'e0000000-0000-4000-8000-000000000004'::uuid,'11111111-1111-1111-1111-111111111111','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true;

-- The legacy RPCs are no longer a client surface (0012 revoked EXECUTE from
-- authenticated; clients go through sync_push). They are exercised here as the
-- internal building blocks they now are: as the function owner, with the
-- caller's JWT claims, so auth.uid() and every membership/role check still run.
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- Allocate a specific pad physically at HEX.
select is(jsonb_array_length(
    allocate_controllers('e0000000-0000-4000-8000-000000000004'::uuid, 'single',
      array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)],
      (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid), 'PS5', now())),
  1, 'allocate_controllers reserves one pad');

-- The same pad cannot be allocated again (one open allocation per controller).
select throws_ok($$
  select allocate_controllers('e0000000-0000-4000-8000-000000000004'::uuid, 'single',
    array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid), 'PS5', now()) $$,
  'controller_taken', 'a pad already in use is rejected');

-- A pad not physically at the target station is rejected (borrow it first).
select throws_ok($$
  select allocate_controllers('e0000000-0000-4000-8000-000000000004'::uuid, 'single',
    array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)],
    (select id from resources where name='VOID' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid), 'PS5', now()) $$,
  'controller_elsewhere', 'a pad at another station is rejected');

-- Idempotency: a repeated request_id returns the same allocation, no new row.
select is(
  allocate_controllers('e0000000-0000-4000-8000-000000000004'::uuid, 'single',
    array[(select id from controllers where label='HEX-2' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid), 'PS5', now(), p_request_id => 'req-1'),
  allocate_controllers('e0000000-0000-4000-8000-000000000004'::uuid, 'single',
    array[(select id from controllers where label='HEX-2' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid), 'PS5', now(), p_request_id => 'req-1'),
  'a repeated request_id returns the same allocation');
select is((select count(*)::int from controller_allocations where request_id='req-1'),
  1, 'the idempotent retry wrote only one row');

-- Releasing frees the pad; it can then be allocated again.
select is(
  release_controllers('e0000000-0000-4000-8000-000000000004'::uuid,
    array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)], now()),
  1, 'release_controllers ends one open allocation');
select is(jsonb_array_length(
    allocate_controllers('e0000000-0000-4000-8000-000000000004'::uuid, 'single',
      array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid)],
      (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000004'::uuid), 'PS5', now())),
  1, 'a released pad can be allocated again');

select set_config('request.jwt.claims','', true);
select * from finish();
rollback;
