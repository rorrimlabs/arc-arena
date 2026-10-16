-- Ops that had no test of their own: booking.update (stale, conflict, closed) and
-- booking.set_status (cancel, no-show — the floor app's "Mark no-show"), controller.set_status,
-- resource.set_mode, holiday.upsert / holiday.delete; and the station rules both apps apply,
-- now on the server too: a station with a live session is never taken out of service or removed
-- (resource.set_status or resource.upsert), and an edit without a status keeps it. Each checks its
-- permission and stays in the caller's arena.
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000200'::uuid, 'pgtap 20'),
  ('e0000000-0000-4000-8000-000000000201'::uuid, 'pgtap 20 neighbour');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('20000000-0000-0000-0000-000000000001', 'owner20@test.local'),
      ('20000000-0000-0000-0000-000000000002', 'staff20@test.local'),
      ('20000000-0000-0000-0000-000000000003', 'till20@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000200','20000000-0000-0000-0000-000000000001','Owner','owner',
    _known_perms(), true),
  ('e0000000-0000-4000-8000-000000000200','20000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill','members'], true),
  ('e0000000-0000-4000-8000-000000000200','20000000-0000-0000-0000-000000000003','Till','staff',
    array['bill'], true);
-- A booking in the neighbour arena, to prove ids never cross arenas.
insert into activities(id, arena_id, code, name)
  values ('a2000000-0000-0000-0000-0000000000ff', 'e0000000-0000-4000-8000-000000000201', 'PS5', 'PS5');
insert into bookings(id, arena_id, activity_id, scheduled_start, scheduled_end, status)
  values ('b2000000-0000-0000-0000-0000000000ff', 'e0000000-0000-4000-8000-000000000201',
    'a2000000-0000-0000-0000-0000000000ff', '2026-11-01T08:00:00Z', '2026-11-01T09:00:00Z', 'booked');

create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000200'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
create function pg_temp.booking(p_id text, p_start text, p_end text, p_extra jsonb default '{}')
  returns jsonb as $$
  select jsonb_build_object('id', p_id, 'activity_code', 'PS5',
    'resource_id', 'b2000000-0000-0000-0000-0000000000a1',
    'scheduled_start', p_start, 'scheduled_end', p_end, 'party_name', 'Asha',
    'phone', '9800002020', 'notes', 'birthday') || p_extra $$ language sql;

-- ------------------------------------------------ catalog
select pg_temp.as_user('20000000-0000-0000-0000-000000000001');
select is(pg_temp.push('activity.upsert', jsonb_build_object('id', 'a2000000-0000-0000-0000-000000000001',
    'code', 'PS5', 'name', 'PS5', 'uses_controllers', true, 'uses_games', true,
    'duration_model', 'hourly'))->>'status', 'applied', 'a PS5 station type');
select is(pg_temp.push('activity.upsert', jsonb_build_object('id', 'a2000000-0000-0000-0000-000000000002',
    'code', 'VR', 'name', 'VR', 'uses_controllers', false, 'uses_games', true,
    'duration_model', 'unit'))->>'status', 'applied', 'a VR station type');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b2000000-0000-0000-0000-0000000000a1',
    'name', 'RIFT', 'kind', 'station', 'activity_codes', jsonb_build_array('PS5', 'VR')))->>'status',
  'applied', 'station RIFT offers both');
select is(pg_temp.push('controller.upsert', jsonb_build_object('id', 'c2000000-0000-0000-0000-000000000001',
    'label', 'RIFT-1', 'home_resource_id', 'b2000000-0000-0000-0000-0000000000a1',
    'current_resource_id', 'b2000000-0000-0000-0000-0000000000a1'))->>'status', 'applied', 'pad RIFT-1');

-- ------------------------------------------------ 1. booking.update
select pg_temp.as_user('20000000-0000-0000-0000-000000000002');
select is(pg_temp.push('booking.create', pg_temp.booking('b2000000-0000-0000-0000-000000000001',
    '2026-11-01T08:00:00Z', '2026-11-01T09:00:00Z'))->>'status', 'applied', 'staff book RIFT');
select is(pg_temp.push('booking.create', pg_temp.booking('b2000000-0000-0000-0000-000000000002',
    '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z'))->>'status', 'applied', 'and a later slot');

create temp table v1 as select sync_xid::text as v from bookings
  where id = 'b2000000-0000-0000-0000-000000000001';
select is(pg_temp.push('booking.update', pg_temp.booking('b2000000-0000-0000-0000-000000000001',
    '2026-11-01T08:30:00Z', '2026-11-01T09:30:00Z',
    jsonb_build_object('base_version', (select v from v1))))->>'status', 'applied',
  'an edit made on the current version moves it');
select results_eq(
  $$ select scheduled_start, party_name, phone from bookings
      where id = 'b2000000-0000-0000-0000-000000000001' $$,
  $$ values ('2026-11-01T08:30:00Z'::timestamptz, 'Asha', '9800002020') $$,
  'the new time is stored and the party details the edit carried are kept');
-- The whole test is one transaction, so every write here carries the same sync_xid: a version
-- from before another device's edit is stood in for by an older transaction id.
select is(pg_temp.push('booking.update', pg_temp.booking('b2000000-0000-0000-0000-000000000001',
    '2026-11-01T07:00:00Z', '2026-11-01T08:00:00Z',
    jsonb_build_object('base_version', '1')))->>'error', 'stale',
  'an edit over a version another device changed since is refused');
select is(pg_temp.push('booking.update', pg_temp.booking('b2000000-0000-0000-0000-000000000001',
    '2026-11-01T09:45:00Z', '2026-11-01T10:30:00Z'))->>'error', 'booking_conflict',
  'moving onto another booking on the same station is refused');
select is((select scheduled_start from bookings where id = 'b2000000-0000-0000-0000-000000000001'),
  '2026-11-01T08:30:00Z'::timestamptz, 'and the refused edits wrote nothing');
select is(pg_temp.push('booking.update', pg_temp.booking('b2000000-0000-0000-0000-0000000000ff',
    '2026-11-01T08:00:00Z', '2026-11-01T09:00:00Z'))->>'error', 'not_found',
  'another arena''s booking cannot be edited');

select pg_temp.as_user('20000000-0000-0000-0000-000000000003');
select is(pg_temp.push('booking.update', pg_temp.booking('b2000000-0000-0000-0000-000000000001',
    '2026-11-01T08:30:00Z', '2026-11-01T09:30:00Z'))->>'error', 'forbidden',
  'someone without start cannot edit a booking');

-- ------------------------------------------------ 2. booking.set_status
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-000000000002","status":"no_show"}')
    ->>'error', 'forbidden', 'someone without start cannot mark a no-show');
select pg_temp.as_user('20000000-0000-0000-0000-000000000002');
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-000000000002","status":"checked_in"}')
    ->>'error', 'invalid_status', 'check-in is never a status change on its own (it is a session start)');
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-000000000002","status":"no_show"}')
    ->>'status', 'applied', 'staff mark a booking no-show');
select is((select status from bookings where id = 'b2000000-0000-0000-0000-000000000002'), 'no_show',
  'it is stored');
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-000000000002","status":"no_show"}')
    ->>'status', 'applied', 'marking it again is a no-op');
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-000000000002","status":"cancelled"}')
    ->>'error', 'booking_not_open', 'a no-show cannot be turned into a cancel');
select is(pg_temp.push('booking.update', pg_temp.booking('b2000000-0000-0000-0000-000000000002',
    '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z'))->>'error', 'booking_not_open',
  'nor edited');
select is(pg_temp.push('booking.create', pg_temp.booking('b2000000-0000-0000-0000-000000000003',
    '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z'))->>'status', 'applied',
  'its slot is free again for a new booking');
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-000000000001","status":"cancelled"}')
    ->>'status', 'applied', 'staff cancel a booking');
select is(pg_temp.push('booking.set_status', '{"id":"b2000000-0000-0000-0000-0000000000ff","status":"cancelled"}')
    ->>'error', 'not_found', 'another arena''s booking cannot be cancelled');
select is((select status from bookings where id = 'b2000000-0000-0000-0000-0000000000ff'), 'booked',
  'and stays booked');

-- ------------------------------------------------ 3. controller.set_status
select is(pg_temp.push('controller.set_status', '{"id":"c2000000-0000-0000-0000-000000000001","status":"faulty","notes":"stick drift"}')
    ->>'error', 'forbidden', 'staff without settings cannot mark a pad faulty');
select pg_temp.as_user('20000000-0000-0000-0000-000000000001');
select is(pg_temp.push('controller.set_status', '{"id":"c2000000-0000-0000-0000-000000000001","status":"faulty","notes":"stick drift"}')
    ->>'status', 'applied', 'the owner marks it faulty with a note');
select results_eq(
  $$ select status, notes from controllers where id = 'c2000000-0000-0000-0000-000000000001' $$,
  $$ values ('faulty', 'stick drift') $$, 'status and note are stored');
select is(pg_temp.push('controller.set_status', '{"id":"c2000000-0000-0000-0000-000000000001","status":"exploded"}')
    ->>'error', 'invalid', 'an unknown status is refused');
select is(pg_temp.push('controller.set_status', '{"id":"c2000000-0000-0000-0000-0000000000ff","status":"usable"}')
    ->>'error', 'not_found', 'an unknown pad is not found');

-- ------------------------------------------------ 4. resource.set_mode
select is(pg_temp.push('resource.set_mode', '{"id":"b2000000-0000-0000-0000-0000000000a1","mode":"VR"}')
    ->>'status', 'applied', 'the owner locks RIFT to VR');
select is((select current_mode from resources where id = 'b2000000-0000-0000-0000-0000000000a1'), 'VR',
  'the lock is stored');
select is(pg_temp.push('resource.set_mode', '{"id":"b2000000-0000-0000-0000-0000000000a1","mode":null}')
    ->>'status', 'applied', 'and clears it');
select is((select current_mode from resources where id = 'b2000000-0000-0000-0000-0000000000a1'), null,
  'the lock is gone');
select pg_temp.as_user('20000000-0000-0000-0000-000000000002');
select is(pg_temp.push('resource.set_mode', '{"id":"b2000000-0000-0000-0000-0000000000a1","mode":"VR"}')
    ->>'error', 'forbidden', 'staff without settings cannot lock a station');

-- ------------------------------------------------ 5. holidays
select is(pg_temp.push('holiday.upsert', '{"day":"2026-11-08","name":"Diwali","closed":true}')->>'error',
  'forbidden', 'staff without settings cannot add a holiday');
select pg_temp.as_user('20000000-0000-0000-0000-000000000001');
select is(pg_temp.push('holiday.upsert', '{"day":"2026-11-08","name":"Diwali","closed":true}')->>'status',
  'applied', 'the owner adds a closed holiday');
select results_eq(
  $$ select name, closed from holidays where arena_id = 'e0000000-0000-4000-8000-000000000200'
      and day = '2026-11-08' $$,
  $$ values ('Diwali', true) $$, 'it is stored');
select is((select count(*)::int from pricing_catalog_history
    where arena_id = 'e0000000-0000-4000-8000-000000000200') > 0, true,
  'a holiday changes the price list, so the previous one is retired');
select is(pg_temp.push('holiday.upsert', '{"day":"not a day","name":"x"}')->>'error', 'invalid_payload',
  'a bad day is refused');
select is(pg_temp.push('holiday.delete', '{"day":"2026-11-08"}')->>'status', 'applied',
  'the owner removes it');
select is((select count(*)::int from holidays where arena_id = 'e0000000-0000-4000-8000-000000000200'), 0,
  'it is gone');
select ok(exists(select 1 from sync_tombstones where arena_id = 'e0000000-0000-4000-8000-000000000200'
    and table_name = 'holidays' and row_key->>'day' = '2026-11-08'), 'and devices are told');
select is(pg_temp.push('holiday.delete', '{"day":"2026-11-08"}')->>'status', 'applied',
  'removing a day that is not a holiday is a no-op');

-- ------------------------------------------------ 6. a station someone is playing on
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'PS5', 'band', 'standard',
    'controller_count', 1, 'unit_minutes', 60, 'price_paise', 10000))->>'status', 'applied', 'a PS5 price');
select is(pg_temp.push('controller.set_status', '{"id":"c2000000-0000-0000-0000-000000000001","status":"usable","notes":null}')
    ->>'status', 'applied', 'pad RIFT-1 is mended (section 3 marked it faulty)');
select pg_temp.as_user('20000000-0000-0000-0000-000000000002');
select is(pg_temp.push('customer.create', jsonb_build_object('id', 'cccccccc-0000-0000-0000-000000000020',
    'name', 'Kiran', 'phone', '9800002021', 'is_guest', false))->>'status', 'applied', 'a customer');
select is(pg_temp.push('session.start', jsonb_build_object(
    'id', 'f2000000-0000-0000-0000-000000000001', 'segment_id', 'f2000000-0000-0000-0000-000000000002',
    'customer_id', 'cccccccc-0000-0000-0000-000000000020',
    'started_at', '2026-10-01T08:00:00Z', 'scheduled_end_at', '2026-10-01T09:00:00Z',
    'pricing_snapshot', _pricing_snapshot('e0000000-0000-4000-8000-000000000200'::uuid),
    'resource_id', 'b2000000-0000-0000-0000-0000000000a1', 'activity_code', 'PS5',
    'controller_count', 1,
    'allocations', jsonb_build_array(jsonb_build_object('controller_id', 'c2000000-0000-0000-0000-000000000001')),
    'moves', '[]'::jsonb))->>'status', 'applied', 'staff start a session on RIFT');

select pg_temp.as_user('20000000-0000-0000-0000-000000000001');
select is(pg_temp.push('resource.set_status', '{"id":"b2000000-0000-0000-0000-0000000000a1","status":"maintenance"}')
    ->>'error', 'resource_busy', 'a station with a live session cannot be taken out of service');
select is(pg_temp.push('resource.set_status', '{"id":"b2000000-0000-0000-0000-0000000000a1","status":"disabled"}')
    ->>'error', 'resource_busy', '... nor removed');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b2000000-0000-0000-0000-0000000000a1',
    'name', 'RIFT', 'kind', 'station', 'status', 'disabled',
    'activity_codes', jsonb_build_array('PS5', 'VR')))->>'error', 'resource_busy',
  '... not even through resource.upsert');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b2000000-0000-0000-0000-0000000000a1',
    'name', 'RIFT-X', 'kind', 'station', 'activity_codes', jsonb_build_array('PS5', 'VR')))->>'status',
  'applied', 'a rename without a status is fine while it is played');
select results_eq(
  $$ select name, status from resources where id = 'b2000000-0000-0000-0000-0000000000a1' $$,
  $$ values ('RIFT-X', 'available') $$, 'and keeps the status');
select is(pg_temp.push('session.void', jsonb_build_object('session_id', 'f2000000-0000-0000-0000-000000000001',
    'reason', 'test', 'at', '2026-10-01T08:30:00Z'))->>'status', 'applied', 'the session is voided');
select is(pg_temp.push('resource.set_status', '{"id":"b2000000-0000-0000-0000-0000000000a1","status":"maintenance"}')
    ->>'status', 'applied', 'now it can go out of service');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b2000000-0000-0000-0000-0000000000a1',
    'name', 'RIFT', 'kind', 'station', 'activity_codes', jsonb_build_array('PS5', 'VR')))->>'status',
  'applied', 'an edit made on an old copy (no status) ...');
select is((select status from resources where id = 'b2000000-0000-0000-0000-0000000000a1'), 'maintenance',
  '... does not put it back in service');
select is(pg_temp.push('resource.set_status', '{"id":"b2000000-0000-0000-0000-0000000000ff","status":"available"}')
    ->>'error', 'not_found', 'an unknown station is not found');

select * from finish();
rollback;
