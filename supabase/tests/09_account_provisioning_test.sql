-- Account provisioning. Two routes to ownership: bootstrap_owner (operator, SQL
-- editor, database access only) and create_my_arena (app sign-up: a confirmed
-- login creates one arena). Staff logins are never created by the database:
-- add_staff_by_email only links an existing login.
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

-- ------------------------------------------------ the app cannot reach these
-- The legacy create_arena / claim_arena (no confirmation, no limit) stay dropped.
select hasnt_function('public', f, f || ' does not exist (replaced by create_my_arena)')
from unnest(array['create_arena', 'claim_arena']) f;
select ok(not has_function_privilege('authenticated', 'bootstrap_owner(text,text,text)', 'EXECUTE'),
  'bootstrap_owner is not callable by a signed-in login');
select ok(not has_function_privilege('anon', 'bootstrap_owner(text,text,text)', 'EXECUTE'),
  'bootstrap_owner is not callable by anon');
select ok(has_function_privilege('authenticated', 'add_staff_by_email(uuid,text,text,text[])', 'EXECUTE'),
  'add_staff_by_email stays the client API (it checks owner itself)');

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
select is((select count(*)::int from resources r join arenas a on a.id = r.arena_id where a.name = 'Shop 09'),
  6, 'the new arena has the starter catalog');

-- ---------------------------------------------- staff: link, never create
-- The fixture arena's owner is the dashboard login 01.
insert into staff_profiles(arena_id, user_id, name, role, perms)
  values ('e0000000-0000-4000-8000-000000000009'::uuid, '91000000-0000-4000-8000-000000000001',
    'Owner', 'owner', array['start','bill','discount','members','stations','money','reports','settings']);
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

create temp table n_users as select count(*) as n from auth.users;
select throws_ok($$ select add_staff_by_email('e0000000-0000-4000-8000-000000000009'::uuid,
    'never-made09@shop.invalid', 'Ghost', array['start']) $$,
  'no_account', 'an unknown e-mail is refused');
select is((select count(*) from auth.users), (select n from n_users),
  'add_staff_by_email never creates a login');
select is(add_staff_by_email('e0000000-0000-4000-8000-000000000009'::uuid,
    ' Staff09@Shop.Invalid ', 'Alan', array['start','bill','discount','members']),
  '91000000-0000-4000-8000-000000000002'::uuid, 'an owner links an existing login (trimmed, any case)');
select is((select role || ':' || array_to_string(perms, ',') from staff_profiles
            where arena_id = 'e0000000-0000-4000-8000-000000000009'::uuid
              and user_id = '91000000-0000-4000-8000-000000000002'),
  'staff:start,bill,discount,members', 'with exactly the permissions the owner chose');
select is((select count(*) from auth.users), (select n from n_users),
  'still no login created');

-- A staff login cannot add people, even to its own arena.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select throws_ok($$ select add_staff_by_email('e0000000-0000-4000-8000-000000000009'::uuid,
    'pending09@shop.invalid', 'X', array['money']) $$,
  '42501', null, 'staff cannot add (or promote) anyone');
-- And a login with no membership at all sees and changes nothing.
select set_config('request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is(my_arenas(), '[]'::jsonb, 'a login with no membership belongs to no arena');
select throws_ok($$ select add_staff_by_email('e0000000-0000-4000-8000-000000000009'::uuid,
    'pending09@shop.invalid', 'X', array['money']) $$,
  '42501', null, 'a non-member cannot add anyone');
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
select is((select count(*)::int from resources where arena_id = (select arena from signup09)),
  6, 'the new arena has the starter catalog');
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

select * from finish();
rollback;
