-- Account provisioning. Two routes to ownership: bootstrap_owner (operator, SQL
-- editor, database access only) and create_my_arena (app sign-up: a confirmed
-- login creates one arena). Everyone else joins by accepting an invitation
-- (17_staff_invites_test.sql): no function links an existing login silently.
begin;
create extension if not exists pgtap;
select * from no_plan();

-- Isolated fixture: this file's own arena, rolled back with the transaction.
insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000009'::uuid, 'pgtap 09');
select _seed_arena_catalog('e0000000-0000-4000-8000-000000000009'::uuid);

-- Logins as the dashboard creates them ("Add user", auto-confirmed), plus one
-- that was never confirmed.
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values
  ('00000000-0000-0000-0000-000000000000','91000000-0000-4000-8000-000000000001','authenticated',
   'authenticated','owner09@shop.invalid','',now(),now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','91000000-0000-4000-8000-000000000002','authenticated',
   'authenticated','staff09@shop.invalid','',now(),now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','91000000-0000-4000-8000-000000000003','authenticated',
   'authenticated','pending09@shop.invalid','',null,now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','91000000-0000-4000-8000-000000000004','authenticated',
   'authenticated','signup09@shop.invalid','',now(),now(),now(),'{}','{}',false,false);

-- Every catalog row an arena can hold; a new arena must have none (no seed).
create function pg_temp.catalog_rows(p_arena uuid) returns int as $$
  select ((select count(*) from activities where arena_id = p_arena)
        + (select count(*) from resources where arena_id = p_arena)
        + (select count(*) from rates where arena_id = p_arena)
        + (select count(*) from rate_cards where arena_id = p_arena)
        + (select count(*) from billing_policies where arena_id = p_arena)
        + (select count(*) from game_categories where arena_id = p_arena)
        + (select count(*) from games where arena_id = p_arena)
        + (select count(*) from controllers where arena_id = p_arena))::int $$ language sql;

-- ------------------------------------------------ the app cannot reach these
-- The legacy create_arena / claim_arena (no confirmation, no limit) stay dropped.
select hasnt_function('public', f, f || ' does not exist (replaced by create_my_arena)')
from unnest(array['create_arena', 'claim_arena']) f;
select ok(not has_function_privilege('authenticated', 'bootstrap_owner(text,text,text)', 'EXECUTE'),
  'bootstrap_owner is not callable by a signed-in login');
select ok(not has_function_privilege('anon', 'bootstrap_owner(text,text,text)', 'EXECUTE'),
  'bootstrap_owner is not callable by anon');
select hasnt_function('public', f, f || ' is gone: an existing login is never linked without consent')
from unnest(array['add_staff_by_email', 'add_member_by_email']) f;
select hasnt_function('private', f, f || ' is gone from private too')
from unnest(array['add_staff_by_email', 'add_member_by_email']) f;

-- ------------------------------------------ initial owner (database access)
select throws_ok($$ select bootstrap_owner('nobody09@shop.invalid', 'X') $$,
  'no_account', 'bootstrap_owner needs an existing login');
select throws_ok($$ select bootstrap_owner('pending09@shop.invalid', 'X') $$,
  'account_not_confirmed', 'bootstrap_owner refuses an unconfirmed login');
select lives_ok($$ select bootstrap_owner('OWNER09@shop.invalid', 'Shop 09', 'Prashanth') $$,
  'bootstrap_owner attaches a confirmed login (e-mail match is case-insensitive)');
select is((select role || '/' || array_length(perms, 1) from staff_profiles sp join arenas a on a.id = sp.arena_id
            where a.name = 'Shop 09' and sp.user_id = '91000000-0000-4000-8000-000000000001'),
  'owner/8', 'the bootstrapped login is the arena''s owner with every permission');
select is(pg_temp.catalog_rows((select id from arenas where name = 'Shop 09')), 0,
  'the new arena starts empty: no types, prices, stations, games or controllers');

-- ------------------------------------- staff join only through invitations
-- The fixture arena's owner is the dashboard login 01; 02 joined as staff
-- (inserted directly here — the invitation flow itself is 17's subject).
insert into staff_profiles(arena_id, user_id, name, role, perms)
  values ('e0000000-0000-4000-8000-000000000009'::uuid, '91000000-0000-4000-8000-000000000001',
    'Owner', 'owner', array['start','bill','discount','members','stations','money','reports','settings']),
  ('e0000000-0000-4000-8000-000000000009'::uuid, '91000000-0000-4000-8000-000000000002',
    'Alan', 'staff', array['start','bill','discount','members']);

create temp table n_users as select count(*) as n from auth.users;
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok($$ select invite_member('e0000000-0000-4000-8000-000000000009'::uuid,
    'never-made09@shop.invalid', 'Ghost', 'staff', array['start']) $$,
  'an owner can invite an address that has no login');
select is((select count(*) from auth.users), (select n from n_users),
  'inviting never creates (or touches) a login in the database');
select is((select count(*)::int from staff_profiles
            where arena_id = 'e0000000-0000-4000-8000-000000000009'::uuid),
  2, 'and adds nobody to the arena until the invite is accepted');

-- A staff login cannot invite people, even to its own arena.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select throws_ok($$ select invite_member('e0000000-0000-4000-8000-000000000009'::uuid,
    'pending09@shop.invalid', 'X', 'staff', array['money']) $$,
  '42501', null, 'staff without Settings cannot invite (or promote) anyone');
-- And a login with no membership at all sees and changes nothing.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is(my_arenas(), '[]'::jsonb, 'a login with no membership belongs to no arena');
select throws_ok($$ select invite_member('e0000000-0000-4000-8000-000000000009'::uuid,
    'pending09@shop.invalid', 'X', 'staff', array['start']) $$,
  '42501', null, 'a non-member cannot invite anyone');
select throws_ok($$ select sync_pull('e0000000-0000-4000-8000-000000000009'::uuid) $$,
  '42501', null, 'a non-member cannot read the arena');

-- ------------------------------------------- self-serve sign-up: create_my_arena
select ok(has_function_privilege('authenticated', 'create_my_arena(text,text)', 'EXECUTE'),
  'create_my_arena is the client API for sign-up');
select ok(not has_function_privilege('anon', 'create_my_arena(text,text)', 'EXECUTE'),
  'create_my_arena is not callable signed out');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok($$ select create_my_arena('X', 'Y') $$,
  '42501', null, 'no session, no arena');

-- 03 signed up but never entered the code.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select throws_ok($$ select create_my_arena('Pending Arena', 'P') $$,
  'account_not_confirmed', 'an unconfirmed login cannot create an arena');

-- 04 is a fresh, confirmed sign-up with no membership.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select throws_ok($$ select create_my_arena('   ', 'Me') $$,
  'invalid_name', 'a blank arena name is refused');
select throws_ok($$ select create_my_arena('Arena', '') $$,
  'invalid_name', 'a blank owner name is refused');
select throws_ok($$ select create_my_arena(repeat('x', 81), 'Me') $$,
  'invalid_name', 'an arena name over 80 characters is refused');
create temp table signup09 as select create_my_arena('  Signup Arena  ', ' Sam ') as arena;
select is((select name from arenas where id = (select arena from signup09)),
  'Signup Arena', 'the arena is created with the trimmed name');
select is((select name || '/' || role || '/' || array_length(perms, 1) || '/' || active
             from staff_profiles where arena_id = (select arena from signup09)),
  'Sam/owner/8/true', 'the caller is its only member: an active owner with every permission');
select is(pg_temp.catalog_rows((select arena from signup09)), 0,
  'the signed-up arena starts empty too: the owner builds the catalog on the dashboard');
select is((select jsonb_agg(e ->> 'role') from jsonb_array_elements(my_arenas()) e),
  '["owner"]'::jsonb, 'my_arenas now lists it, so the app can open it');
select throws_ok($$ select create_my_arena('Second', 'Sam') $$,
  'arena_limit', 'one arena per login');

-- 01 already owns arenas (bootstrapped): the limit counts those too.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select throws_ok($$ select create_my_arena('Another', 'Owner') $$,
  'arena_limit', 'an owner from bootstrap_owner cannot add arenas from the app');
-- 02 is staff elsewhere, not an owner: they may start their own arena.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select lives_ok($$ select create_my_arena('Alan''s Arena', 'Alan') $$,
  'staff of another arena can still create their own');
-- bootstrap_owner itself has no limit (operator tool).
select lives_ok($$ select bootstrap_owner('signup09@shop.invalid', 'Branch 2') $$,
  'the operator can still add a second arena for an owner');

-- ----------------------------------------- arena_staff: the owner's staff list
-- 02 (staff, never signed in) recorded a payment and a refund in the fixture.
insert into customers(id, arena_id, name)
  values ('c5000000-0000-4000-8000-000000000009', 'e0000000-0000-4000-8000-000000000009', 'Walk-in 09');
insert into sessions(id, arena_id, customer_id, started_at, scheduled_end_at, pricing_snapshot, policy_snapshot)
  values ('5e000000-0000-4000-8000-000000000009', 'e0000000-0000-4000-8000-000000000009',
          'c5000000-0000-4000-8000-000000000009',
          now() - interval '2 hours', now() - interval '1 hour', '{}', '{}');
insert into payments(arena_id, session_id, amount_paise, method, kind, reason, created_by) values
  ('e0000000-0000-4000-8000-000000000009', '5e000000-0000-4000-8000-000000000009', 30000, 'upi', 'payment', null,
   '91000000-0000-4000-8000-000000000002'),
  ('e0000000-0000-4000-8000-000000000009', '5e000000-0000-4000-8000-000000000009', -5000, 'cash', 'refund', 'Wrong amount',
   '91000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
create temp table staff09 as
  select e from jsonb_array_elements(arena_staff('e0000000-0000-4000-8000-000000000009'::uuid)) e;
select is((select array_agg(e ->> 'role') from staff09), array['owner', 'staff'],
  'arena_staff lists the owner first, then staff');
select is((select e ->> 'email' from staff09 where e ->> 'role' = 'staff'), 'staff09@shop.invalid',
  'with the login e-mail');
select is((select (e ->> 'invited')::boolean from staff09 where e ->> 'role' = 'staff'), true,
  'a login that never signed in is flagged invited');
select is((select (e ->> 'bills_30d') || '/' || (e ->> 'takings_30d_paise') || '/' || (e ->> 'refunds_30d_paise')
             from staff09 where e ->> 'role' = 'staff'), '1/25000/5000',
  'and the bills, net takings and refunds they recorded in 30 days');
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select throws_ok($$ select arena_staff('e0000000-0000-4000-8000-000000000009'::uuid) $$,
  '42501', null, 'staff cannot list e-mails');
select ok(not has_function_privilege('anon', 'arena_staff(uuid)', 'EXECUTE'),
  'arena_staff is not callable signed out');

select * from finish();
rollback;
