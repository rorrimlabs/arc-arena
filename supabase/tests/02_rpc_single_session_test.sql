-- Single-session RPCs: behaviour, idempotency, locking, money, void.
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,
    email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
      'authenticated','authenticated','owner@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select (select id from arenas limit 1),'11111111-1111-1111-1111-111111111111','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true;
insert into customers(id,arena_id,name) values
  ('cccccccc-0000-0000-0000-000000000001',(select id from arenas limit 1),'Test Walk-in');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- start_session uses the client-supplied id and opens segment 0.
select is(
  start_session((select id from arenas limit 1), jsonb_build_object(
    'id','aaaaaaaa-0000-0000-0000-000000000001',
    'segment_id','bbbbbbbb-0000-0000-0000-000000000001',
    'customer_id','cccccccc-0000-0000-0000-000000000001',
    'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot', jsonb_build_object('policy', jsonb_build_object('name','Default')),
    'resource_id',(select id from resources where name='HEX'),'activity_code','PS5','controller_count',2),
    'req-start-1')::text,
  'aaaaaaaa-0000-0000-0000-000000000001', 'start_session returns the client id');
select is((select count(*)::int from session_segments
  where session_id='aaaaaaaa-0000-0000-0000-000000000001' and ended_at is null), 1,
  'exactly one open segment after start');
select is((select policy_snapshot->>'name' from sessions where id='aaaaaaaa-0000-0000-0000-000000000001'),
  'Default', 'policy_snapshot materialised from pricing_snapshot->policy');

-- Idempotent: same request_id returns the first session, no second row.
select is(
  start_session((select id from arenas limit 1), jsonb_build_object(
    'id','aaaaaaaa-0000-0000-0000-000000000099','customer_id','cccccccc-0000-0000-0000-000000000001',
    'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,'resource_id',(select id from resources where name='HEX'),'activity_code','PS5'),
    'req-start-1')::text,
  'aaaaaaaa-0000-0000-0000-000000000001', 'duplicate request_id returns the same session');
select is((select count(*)::int from sessions where arena_id=(select id from arenas limit 1)), 1,
  'no duplicate session row was created');

-- One open segment per resource: a second start on HEX fails.
select throws_ok($$
  select start_session((select id from arenas limit 1), jsonb_build_object(
    'id','aaaaaaaa-0000-0000-0000-000000000002','customer_id','cccccccc-0000-0000-0000-000000000001',
    'started_at','2026-10-01T09:05:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,'resource_id',(select id from resources where name='HEX'),'activity_code','PS5'),
    'req-start-2') $$,
  'resource_busy', 'a second start on a busy resource raises resource_busy');

-- not_playable: Tekken 8 is explicitly not_playable on RIFT (seed override).
select throws_ok($$
  select start_session((select id from arenas limit 1), jsonb_build_object(
    'id','aaaaaaaa-0000-0000-0000-000000000003','customer_id','cccccccc-0000-0000-0000-000000000001',
    'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,'resource_id',(select id from resources where name='RIFT'),
    'activity_code','PS5','game_id',(select id from games where name='Tekken 8')), 'req-np') $$,
  'not_playable', 'starting a game marked not_playable on that station raises not_playable');

-- Payment status transitions: partial -> paid, and idempotent payment.
select isnt(record_payment('aaaaaaaa-0000-0000-0000-000000000001', 10000, 'cash',
  'payment', null, null, 'req-pay-1')::text, null, 'record_payment returns an id');
select is(record_payment('aaaaaaaa-0000-0000-0000-000000000001', 10000, 'cash',
  'payment', null, null, 'req-pay-1')::text,
  (select id::text from payments where request_id='req-pay-1'),
  'duplicate payment request_id returns the same payment');
select is((select count(*)::int from payments where session_id='aaaaaaaa-0000-0000-0000-000000000001'), 1,
  'duplicate payment wrote only one row');

-- end_session writes charges once and derives payment_status from paid vs billed.
select is((end_session('aaaaaaaa-0000-0000-0000-000000000001','2026-10-01T10:00:00Z',
  jsonb_build_array(jsonb_build_object('segment_index',0,'band_code','standard','activity_code','PS5',
    'controller_count',2,'segment_start','2026-10-01T09:00:00Z','segment_end','2026-10-01T10:00:00Z',
    'played_minutes',60,'billed_minutes',60,'unit_minutes',60,'unit_price_paise',28000,'amount_paise',28000)),
  28000, false))->>'payment_status', 'partial', 'end with 10000 paid of 28000 -> partial');
select is((select count(*)::int from session_charges where session_id='aaaaaaaa-0000-0000-0000-000000000001'), 1,
  'one charge row written at end');
-- Ending again is a no-op that writes nothing more.
select is((end_session('aaaaaaaa-0000-0000-0000-000000000001','2026-10-01T10:00:00Z','[]'::jsonb,28000,false))->>'applied',
  'false', 'ending a completed session is idempotent (applied=false)');
select is((select count(*)::int from session_charges where session_id='aaaaaaaa-0000-0000-0000-000000000001'), 1,
  'ending twice still leaves exactly one charge row');

-- Paying the balance flips partial -> paid.
select isnt(record_payment('aaaaaaaa-0000-0000-0000-000000000001', 18000, 'upi',
  'payment', null, null, 'req-pay-2')::text, null, 'second payment recorded');
select is((select payment_status from sessions where id='aaaaaaaa-0000-0000-0000-000000000001'),
  'paid', 'paying the balance -> paid');

-- Refund rules: reason required; stored negative.
select throws_ok($$ select record_payment('aaaaaaaa-0000-0000-0000-000000000001', 5000, 'cash','refund',null,null,'req-ref-noreason') $$,
  'refund_reason_required', 'refund without a reason is rejected');
select isnt(record_payment('aaaaaaaa-0000-0000-0000-000000000001', 5000, 'cash','refund',null,'overcharge','req-ref-1')::text,
  null, 'refund with a reason is accepted');
select ok((select amount_paise from payments where request_id='req-ref-1') < 0,
  'refund is stored as a negative amount');
select throws_ok($$ select record_payment('aaaaaaaa-0000-0000-0000-000000000001', 0, 'cash','payment',null,null,'req-zero') $$,
  'amount_zero', 'a zero payment is rejected');

-- The resource is free again after end: a new session can start on HEX.
select isnt(start_session((select id from arenas limit 1), jsonb_build_object(
    'id','aaaaaaaa-0000-0000-0000-000000000004','customer_id','cccccccc-0000-0000-0000-000000000001',
    'started_at','2026-10-01T11:00:00Z','scheduled_end_at','2026-10-01T12:00:00Z',
    'pricing_snapshot','{}'::jsonb,'resource_id',(select id from resources where name='HEX'),'activity_code','PS5'),
    'req-start-4')::text, null, 'resource is free after end; a new session starts');

-- void_session (owner) flips status and is idempotent.
select void_session('aaaaaaaa-0000-0000-0000-000000000004','test correction');
select is((select status from sessions where id='aaaaaaaa-0000-0000-0000-000000000004'),
  'voided', 'void_session sets status voided');
select lives_ok($$ select void_session('aaaaaaaa-0000-0000-0000-000000000004','again') $$,
  'void is idempotent (voiding a voided session is a no-op)');
select is((select count(*)::int from audit_log where entity_id='aaaaaaaa-0000-0000-0000-000000000004'), 1,
  'void wrote exactly one audit row');

reset role;
select set_config('request.jwt.claims','', true);
select * from finish();
rollback;
