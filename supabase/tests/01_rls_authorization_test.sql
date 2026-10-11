-- Owner vs staff authorization, enforced on the backend (RLS).
begin;
create extension if not exists pgtap;
select * from no_plan();

-- Fixture: one owner, one staff (Drift default staff perms), plus two extra
-- auth users the owner-write tests reference (FK targets).
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,
    email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data,
    is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
      'authenticated','authenticated','owner@test.local','',now(),now(),now(),'{}','{}',false,false),
    ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222',
      'authenticated','authenticated','staff@test.local','',now(),now(),now(),'{}','{}',false,false),
    ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333',
      'authenticated','authenticated','x3@test.local','',now(),now(),now(),'{}','{}',false,false),
    ('00000000-0000-0000-0000-000000000000','44444444-4444-4444-4444-444444444444',
      'authenticated','authenticated','x4@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ((select id from arenas limit 1),'11111111-1111-1111-1111-111111111111'::uuid,'Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true),
  ((select id from arenas limit 1),'22222222-2222-2222-2222-222222222222'::uuid,'Staff','staff',
    array['start','bill','discount','members'],true);

-- ===================== as STAFF =====================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*)::int from rates), 12, 'staff can READ config (rates)');
select throws_ok($$
  insert into rates(arena_id,rate_card_id,activity_id,band_id,unit_minutes,price_paise)
    select (select id from arenas limit 1), rc.id, a.id, b.id, 60, 9900
    from rate_cards rc, activities a, rate_bands b
    where a.code='PS5' and b.code='standard' limit 1 $$,
  '42501', NULL, 'staff CANNOT write config (rates insert denied by RLS)');
-- An UPDATE denied by RLS silently affects 0 rows (USING filters them out);
-- attempt a visible mutation now and assert below that nothing changed.
update games set name = name || '_HACKED' where arena_id=(select id from arenas limit 1);
select throws_ok($$
  insert into staff_profiles(arena_id,user_id,name,role)
    values ((select id from arenas limit 1),'33333333-3333-3333-3333-333333333333','X','owner') $$,
  '42501', NULL, 'staff CANNOT insert a staff_profiles row (no self-escalation)');
select throws_ok($$ insert into sessions(arena_id,customer_id,started_at,scheduled_end_at,pricing_snapshot,policy_snapshot)
    values ((select id from arenas limit 1), gen_random_uuid(), now(), now()+interval '1h','{}','{}') $$,
  '42501', NULL, 'staff CANNOT write sessions directly (RPC-only)');
select throws_ok($$ insert into audit_log(arena_id,entity_type,entity_id,action)
    values ((select id from arenas limit 1),'x',gen_random_uuid(),'x') $$,
  '42501', NULL, 'staff CANNOT write audit_log directly (RPC-only)');
select lives_ok($$ insert into customers(arena_id,name) values ((select id from arenas limit 1),'Walk-in by staff') $$,
  'staff CAN create a customer (floor op)');
-- Self-escalation via UPDATE is silently filtered by RLS USING (0 rows).
update staff_profiles set role='owner' where user_id='22222222-2222-2222-2222-222222222222';
reset role;
select set_config('request.jwt.claims','', true);
select is((select count(*)::int from games where name like '%HACKED%'),
  0, 'staff UPDATE on catalog (games) changed nothing (owner-only)');
select is((select role from staff_profiles where user_id='22222222-2222-2222-2222-222222222222'),
  'staff', 'staff self-escalation UPDATE changed nothing');

-- ===================== as OWNER =====================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select lives_ok($$ update games set name=name where arena_id=(select id from arenas limit 1) $$,
  'owner CAN update catalog (games)');
select lives_ok($$
  insert into rates(arena_id,rate_card_id,activity_id,band_id,unit_minutes,price_paise)
    select (select id from arenas limit 1), rc.id, a.id, b.id, 60, 9900
    from rate_cards rc, activities a, rate_bands b
    where a.code='LOUNGE' and b.code='happy' limit 1 $$,
  'owner CAN write config (rates insert)');
select lives_ok($$
  insert into staff_profiles(arena_id,user_id,name,role,perms)
    values ((select id from arenas limit 1),'44444444-4444-4444-4444-444444444444','New Staff','staff',array['start']) $$,
  'owner CAN add a staff profile');
-- Deletes are blocked for everyone (append-only): revoked on RPC-only tables.
select throws_ok($$ delete from sessions where arena_id=(select id from arenas limit 1) $$,
  '42501', NULL, 'even an owner CANNOT delete sessions (append-only)');
reset role;
select set_config('request.jwt.claims','', true);

-- ===================== as NON-MEMBER =====================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}', true);
select is((select count(*)::int from sessions), 0, 'non-member sees no sessions');
select is((select count(*)::int from rates), 0, 'non-member sees no config');
reset role;
select set_config('request.jwt.claims','', true);

select * from finish();
rollback;
