-- Joining an arena by invitation (invite_member → e-mailed link → accept_invite).
-- Nobody is attached to an arena without accepting; the invite works once, only
-- for the confirmed login whose e-mail it was sent to, only for its own arena,
-- and only while whoever invited still holds the authority it needs.
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000170', 'pgtap 17 A'),
  ('e0000000-0000-4000-8000-000000000171', 'pgtap 17 B');

insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, '',
       case when u.confirmed then now() end, now(), now(), '{}', '{}', false, false
  from (values
    ('17000000-0000-4000-8000-000000000001', 'owner17@test.local',    true),
    ('17000000-0000-4000-8000-000000000002', 'settings17@test.local', true),
    ('17000000-0000-4000-8000-000000000003', 'cashier17@test.local',  true),
    ('17000000-0000-4000-8000-000000000004', 'floor17@test.local',    true),
    ('17000000-0000-4000-8000-000000000005', 'new17@test.local',      true),
    ('17000000-0000-4000-8000-000000000006', 'other17@test.local',    true),
    ('17000000-0000-4000-8000-000000000007', 'pending17@test.local',  false),
    ('17000000-0000-4000-8000-000000000008', 'ownerb17@test.local',   true),
    ('17000000-0000-4000-8000-000000000009', 'gone17@test.local',     true),
    ('17000000-0000-4000-8000-000000000010', 'coowner17@test.local',  true)) u(id, email, confirmed);

insert into staff_profiles(arena_id, user_id, name, role, perms, active) values
  ('e0000000-0000-4000-8000-000000000170', '17000000-0000-4000-8000-000000000001', 'Owner A', 'owner', _known_perms(), true),
  ('e0000000-0000-4000-8000-000000000170', '17000000-0000-4000-8000-000000000002', 'Setter', 'staff', array['start','settings'], true),
  ('e0000000-0000-4000-8000-000000000170', '17000000-0000-4000-8000-000000000003', 'Cashier', 'staff', array['start','bill','money'], true),
  ('e0000000-0000-4000-8000-000000000170', '17000000-0000-4000-8000-000000000004', 'Floor', 'staff', array['start','bill','discount','members'], true),
  ('e0000000-0000-4000-8000-000000000170', '17000000-0000-4000-8000-000000000009', 'Gone', 'staff', array['start','settings'], false),
  ('e0000000-0000-4000-8000-000000000171', '17000000-0000-4000-8000-000000000008', 'Owner B', 'owner', _known_perms(), true);

create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.invite(p_email text, p_role text, p_perms text[],
    p_arena uuid default 'e0000000-0000-4000-8000-000000000170') returns jsonb as $$
  select invite_member(p_arena, p_email, 'Invitee', p_role, p_perms) $$ language sql;
create function pg_temp.profile(p_uid text, p_arena uuid default 'e0000000-0000-4000-8000-000000000170')
  returns text as $$
  select role || ':' || array_to_string(perms, ',') || ':' || active from staff_profiles
   where arena_id = p_arena and user_id = p_uid::uuid $$ language sql;
create temp table inv(label text primary key, j jsonb);
-- Lets the throws_ok strings below refer to a saved invite.
create function pg_temp.id(p text) returns uuid as $$
  select (j ->> 'invite_id')::uuid from inv where label = p $$ language sql;
create function pg_temp.tok(p text) returns text as $$
  select j ->> 'token' from inv where label = p $$ language sql;

-- ------------------------------------------- 1. surface
select ok(not has_function_privilege('anon', f, 'EXECUTE'), 'anon cannot call ' || f)
from unnest(array['invite_member(uuid,text,text,text,text[])', 'accept_invite(uuid,text)',
  'revoke_invite(uuid,uuid)', 'arena_invites(uuid)']) f;
select ok(has_function_privilege('authenticated', f, 'EXECUTE'), 'client API: ' || f)
from unnest(array['invite_member(uuid,text,text,text,text[])', 'accept_invite(uuid,text)',
  'revoke_invite(uuid,uuid)', 'arena_invites(uuid)']) f;
select ok((select relrowsecurity from pg_class where oid = 'public.staff_invites'::regclass),
  'staff_invites has RLS on');
select ok(not has_table_privilege(r, 'public.staff_invites', 'select,insert,update,delete'),
  r || ' has no privilege on staff_invites')
from unnest(array['anon', 'authenticated']) r;
select is((select count(*)::int from pg_policies where tablename = 'staff_invites'), 0,
  'and no policies: invites are read only through arena_invites()');

-- ------------------------------------------- 2. who may invite
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
insert into inv values ('new', pg_temp.invite(' New17@Test.Local ', 'staff', array['start','bill']));
select ok((select j ->> 'token' ~ '^[0-9a-f]{64}$' from inv where label = 'new'),
  'the owner gets a one-time token (32 random bytes, hex)');
select is((select email || '/' || role || '/' || array_to_string(perms, ',') from staff_invites
            where id = pg_temp.id('new')),
  'new17@test.local/staff/start,bill', 'the address is stored trimmed and lower case, with role and perms');
select ok((select token_hash = extensions.digest(pg_temp.tok('new'), 'sha256')
                  and position(pg_temp.tok('new')::bytea in token_hash) = 0
             from staff_invites where id = pg_temp.id('new')),
  'only the token''s SHA-256 is stored');
select ok((select expires_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
             from staff_invites where id = pg_temp.id('new')), 'it expires in 7 days');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000005'), null,
  'nobody joins the arena by being invited');

select throws_ok($$ select pg_temp.invite('x17@test.local', 'admin', array['start']) $$,
  'invalid_role', 'role must be staff or owner');
select throws_ok($$ select pg_temp.invite('not-an-email', 'staff', array['start']) $$,
  'invalid_email', 'the address must look like one');
select throws_ok($$ select invite_member('e0000000-0000-4000-8000-000000000170',
    'x17@test.local', '   ', 'staff', array['start']) $$, 'invalid_name', 'a blank name is refused');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start','root']) $$,
  'invalid_permission', 'unknown permission codes are refused');
select throws_ok($$ select pg_temp.invite('OWNER17@test.local', 'staff', array['start']) $$,
  '42501', null, 'nobody invites themselves (no route to their own perms)');

select pg_temp.as_user('17000000-0000-4000-8000-000000000002');
select lives_ok($$ select pg_temp.invite('setter-pick17@test.local', 'staff', array['start']) $$,
  'a Settings holder may invite staff');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start','money']) $$,
  '42501', null, 'but not grant money (owner level only)');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'owner', null) $$,
  '42501', null, 'and not invite an owner');

select pg_temp.as_user('17000000-0000-4000-8000-000000000003');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start']) $$,
  '42501', null, 'owner level without Settings cannot invite (same rule as staff.update)');
select pg_temp.as_user('17000000-0000-4000-8000-000000000004');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start']) $$,
  '42501', null, 'floor staff cannot invite');
select pg_temp.as_user('17000000-0000-4000-8000-000000000009');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start']) $$,
  '42501', null, 'a deactivated member cannot invite, whatever their old perms');
select pg_temp.as_user('17000000-0000-4000-8000-000000000008');
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start']) $$,
  '42501', null, 'another arena''s owner cannot invite into this arena');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok($$ select pg_temp.invite('x17@test.local', 'staff', array['start']) $$,
  '42501', null, 'no session, no invite');

-- ------------------------------------------- 3. accepting
select pg_temp.as_user('17000000-0000-4000-8000-000000000006');
select throws_ok($$ select accept_invite(pg_temp.id('new'), pg_temp.tok('new')) $$,
  '42501', null, 'another login cannot accept, even with the right token');
select pg_temp.as_user('17000000-0000-4000-8000-000000000005');
select throws_ok($$ select accept_invite(pg_temp.id('new'), repeat('0', 64)) $$,
  'invite_invalid', 'a wrong token is refused');
select throws_ok($$ select accept_invite(gen_random_uuid(), pg_temp.tok('new')) $$,
  'invite_invalid', 'an unknown invite is refused the same way (nothing to probe)');
select throws_ok($$ select accept_invite(pg_temp.id('new'), null) $$,
  'invite_invalid', 'no token, no entry');
select is((select accept_invite(pg_temp.id('new'), pg_temp.tok('new')) ->> 'arena_name'),
  'pgtap 17 A', 'the invited, confirmed login accepts with its token');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000005'), 'staff:start,bill:true',
  'and is now an active member with exactly the invited permissions');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000005', 'e0000000-0000-4000-8000-000000000171'),
  null, 'of that arena only');
select is((select jsonb_agg(e ->> 'arena_name') from jsonb_array_elements(my_arenas()) e),
  '["pgtap 17 A"]'::jsonb, 'my_arenas lists it, so the apps can open it');
select ok((select accepted_by = '17000000-0000-4000-8000-000000000005' and accepted_at is not null
             from staff_invites where id = pg_temp.id('new')), 'the invite records who accepted');
select throws_ok($$ select accept_invite(pg_temp.id('new'), pg_temp.tok('new')) $$,
  'invite_used', 'and works once');
-- What the dashboard routes on after the invitee accepts (2026-10-14 auth fix): exactly one
-- membership, floor staff (not owner level), and no arena of their own.
select is((select count(*)::int from staff_profiles
            where user_id = '17000000-0000-4000-8000-000000000005'), 1,
  'a repeated accept leaves exactly one membership');
select is((select count(*)::int from staff_profiles
            where user_id = '17000000-0000-4000-8000-000000000005' and role = 'owner'), 0,
  'accepting a staff invitation creates no arena and no ownership');
select is((select jsonb_agg((e ->> 'role') || ':' || (e ->> 'active'))
             from jsonb_array_elements(my_arenas()) e),
  '["staff:true"]'::jsonb, 'my_arenas shows the invitee as active staff only (the staff app, not Create Arena)');

-- Unconfirmed login: the address is not proven yet.
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
insert into inv values ('pending', pg_temp.invite('pending17@test.local', 'staff', array['start']));
select pg_temp.as_user('17000000-0000-4000-8000-000000000007');
select throws_ok($$ select accept_invite(pg_temp.id('pending'), pg_temp.tok('pending')) $$,
  'email_not_confirmed', 'an unconfirmed login cannot accept');

-- Expired.
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
insert into inv values ('late', pg_temp.invite('other17@test.local', 'staff', array['start']));
update staff_invites set expires_at = now() - interval '1 minute' where id = pg_temp.id('late');
select pg_temp.as_user('17000000-0000-4000-8000-000000000006');
select throws_ok($$ select accept_invite(pg_temp.id('late'), pg_temp.tok('late')) $$,
  'invite_expired', 'an expired invite is refused');

-- A newer invite replaces the open one; withdrawing stops a link.
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
insert into inv values ('first', pg_temp.invite('again17@test.local', 'staff', array['start']));
insert into inv values ('second', pg_temp.invite('again17@test.local', 'staff', array['start','bill']));
select ok((select revoked_at is not null from staff_invites where id = pg_temp.id('first')),
  'inviting the same address again withdraws the first link');
select is((select count(*)::int from staff_invites where arena_id = 'e0000000-0000-4000-8000-000000000170'
            and email = 'again17@test.local' and accepted_at is null and revoked_at is null),
  1, 'one open invite per address');
insert into inv values ('withdrawn', pg_temp.invite('gone17@test.local', 'staff', array['start']));
select pg_temp.as_user('17000000-0000-4000-8000-000000000004');
select throws_ok($$ select revoke_invite('e0000000-0000-4000-8000-000000000170', pg_temp.id('withdrawn')) $$,
  '42501', null, 'floor staff cannot withdraw invites');
select pg_temp.as_user('17000000-0000-4000-8000-000000000008');
select throws_ok($$ select revoke_invite('e0000000-0000-4000-8000-000000000171', pg_temp.id('withdrawn')) $$,
  'not_found', 'another arena cannot reach it');
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
select lives_ok($$ select revoke_invite('e0000000-0000-4000-8000-000000000170', pg_temp.id('withdrawn')) $$,
  'the owner withdraws it');
select pg_temp.as_user('17000000-0000-4000-8000-000000000009');
select throws_ok($$ select accept_invite(pg_temp.id('withdrawn'), pg_temp.tok('withdrawn')) $$,
  'invite_revoked', 'a withdrawn invite is refused');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000009'), 'staff:start,settings:false',
  'and the deactivated member stays deactivated');
select throws_ok($$ select accept_invite(pg_temp.id('first'), pg_temp.tok('first')) $$,
  'invite_revoked', 'a replaced link is refused too');

-- Reactivation needs the person's consent: accepting a fresh invite.
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
insert into inv values ('back', pg_temp.invite('gone17@test.local', 'staff', array['start']));
select is(pg_temp.profile('17000000-0000-4000-8000-000000000009'), 'staff:start,settings:false',
  'inviting a former member does not reactivate them');
select pg_temp.as_user('17000000-0000-4000-8000-000000000009');
select lives_ok($$ select accept_invite(pg_temp.id('back'), pg_temp.tok('back')) $$,
  'they accept');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000009'), 'staff:start:true',
  'and are back with the newly invited permissions only');

-- The inviter's authority is checked again at acceptance.
select pg_temp.as_user('17000000-0000-4000-8000-000000000002');
insert into inv values ('stale', pg_temp.invite('setter-late17@test.local', 'staff', array['start']));
update staff_profiles set perms = array['start'] where user_id = '17000000-0000-4000-8000-000000000002';
insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
  values ('00000000-0000-0000-0000-000000000000', '17000000-0000-4000-8000-000000000011', 'authenticated',
    'authenticated', 'setter-late17@test.local', '', now(), now(), now(), '{}', '{}', false, false);
select pg_temp.as_user('17000000-0000-4000-8000-000000000011');
select throws_ok($$ select accept_invite(pg_temp.id('stale'), pg_temp.tok('stale')) $$,
  'invite_invalid', 'an invite from someone who has since lost Settings no longer works');
update staff_profiles set perms = array['start','settings'] where user_id = '17000000-0000-4000-8000-000000000002';

-- ------------------------------------------- 4. owners
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
insert into inv values ('co', pg_temp.invite('coowner17@test.local', 'owner', array['start']));
select is((select perms from staff_invites where id = pg_temp.id('co')), _known_perms(),
  'an owner invite carries every permission, whatever was asked');
select pg_temp.as_user('17000000-0000-4000-8000-000000000002');
select throws_ok($$ select pg_temp.invite('coowner17@test.local', 'staff', array['start']) $$,
  '42501', null, 'a Settings holder cannot replace (downgrade) an owner invite');
select throws_ok($$ select revoke_invite('e0000000-0000-4000-8000-000000000170', pg_temp.id('co')) $$,
  '42501', null, 'or withdraw it');
select pg_temp.as_user('17000000-0000-4000-8000-000000000010');
select is((select accept_invite(pg_temp.id('co'), pg_temp.tok('co')) ->> 'role'), 'owner',
  'the invited co-owner accepts');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000010'),
  'owner:' || array_to_string(_known_perms(), ',') || ':true', 'and is an owner with every permission');
-- An existing owner can never be turned into staff by an invite.
select pg_temp.as_user('17000000-0000-4000-8000-000000000002');
insert into inv values ('demote', pg_temp.invite('coowner17@test.local', 'staff', array['start']));
select pg_temp.as_user('17000000-0000-4000-8000-000000000010');
select throws_ok($$ select accept_invite(pg_temp.id('demote'), pg_temp.tok('demote')) $$,
  'owner_profile', 'an owner cannot be demoted through an invite');
select is(pg_temp.profile('17000000-0000-4000-8000-000000000010'),
  'owner:' || array_to_string(_known_perms(), ',') || ':true', 'and stays an owner');

-- ------------------------------------------- 5. listing
select pg_temp.as_user('17000000-0000-4000-8000-000000000001');
create temp table open17 as
  select e from jsonb_array_elements(arena_invites('e0000000-0000-4000-8000-000000000170')) e;
select ok((select bool_and(not (e ? 'token_hash') and not (e ? 'token')) from open17),
  'arena_invites never returns a token or its hash');
select ok((select bool_or(e ->> 'email' = 'again17@test.local') and not bool_or(e ->> 'email' = 'new17@test.local')
             from open17), 'it lists open invites only (not accepted or withdrawn ones)');
select ok((select (e ->> 'expired')::boolean from open17 where e ->> 'email' = 'other17@test.local'),
  'and flags expired ones');
select pg_temp.as_user('17000000-0000-4000-8000-000000000004');
select throws_ok($$ select arena_invites('e0000000-0000-4000-8000-000000000170') $$,
  '42501', null, 'floor staff cannot list invites (addresses)');
select pg_temp.as_user('17000000-0000-4000-8000-000000000008');
select throws_ok($$ select arena_invites('e0000000-0000-4000-8000-000000000170') $$,
  '42501', null, 'nor can another arena''s owner');

select * from finish();
rollback;
