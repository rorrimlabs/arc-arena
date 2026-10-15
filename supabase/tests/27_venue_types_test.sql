-- Venue types: the global station type catalog, the venue_profile setting, and a mixed venue
-- (pool hall + turf, built from the catalog through sync_push alone) running a pool session and
-- a turf booking to payment with no game and no controllers.
--
-- Thu 2026-10-01; 09:00Z = 14:30 IST (inside the default opening hours).
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000270'::uuid, 'pgtap 27');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('27000000-0000-0000-0000-000000000001', 'owner27@test.local'),
      ('27000000-0000-0000-0000-000000000002', 'staff27@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000270','27000000-0000-0000-0000-000000000001','Owner','owner',
    _known_perms(), true),
  ('e0000000-0000-4000-8000-000000000270','27000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill'], true);

create function pg_temp.arena() returns uuid as $$
  select 'e0000000-0000-4000-8000-000000000270'::uuid $$ language sql;
create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push(pg_temp.arena(),
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
create function pg_temp.r(n text) returns uuid as $$
  select id from resources where name = n and arena_id = pg_temp.arena() $$ language sql;
create function pg_temp.start(p_id text, p_seg text, p_res text, p_act text, p_at text, p_end text,
    p_booking uuid default null) returns jsonb as $$
  select jsonb_build_object('id', p_id::uuid, 'segment_id', p_seg::uuid,
    'customer_id', 'cccccccc-0000-0000-0000-000000000027', 'booking_id', p_booking,
    'started_at', p_at, 'scheduled_end_at', p_end,
    'pricing_snapshot', _pricing_snapshot(pg_temp.arena()),
    'resource_id', pg_temp.r(p_res), 'activity_code', p_act,
    'allocations', '[]'::jsonb, 'moves', '[]'::jsonb) $$ language sql;
create function pg_temp.end_op(p_id text, p_seg text, p_res text, p_act text, p_s text, p_sched text,
    p_e text, p_played int, p_billed int, p_price int, p_amount int) returns jsonb as $$
  select jsonb_build_object('session_id', p_id::uuid, 'ended_at', p_e,
    'billed_amount_paise', p_amount, 'expected_segment_ids', jsonb_build_array(p_seg),
    'expected_scheduled_end_at', p_sched,
    'charges', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'segment_id', p_seg::uuid,
      'segment_index', 0, 'band_code', 'standard', 'activity_code', p_act,
      'resource_id', pg_temp.r(p_res), 'controller_count', null, 'segment_start', p_s,
      'segment_end', p_e, 'played_minutes', p_played, 'billed_minutes', p_billed,
      'unit_minutes', 60, 'unit_price_paise', p_price, 'amount_paise', p_amount))) $$ language sql;

-- ------------------------------------------------ 1. the catalog
select ok(jsonb_array_length(station_type_catalog()) > 0, 'the catalog lists station types');
select is((select count(*)::int from jsonb_array_elements(station_type_catalog()) e
            where e->>'code' !~ '^[A-Z0-9_]{1,12}$'
               or char_length(e->>'name') not between 1 and 40
               or e->>'group' not in ('gaming', 'cue', 'sports', 'arcade', 'other')
               or e->>'duration_model' not in ('hourly', 'unit', 'flat_hourly')
               or (e->>'unit_minutes')::int <= 0
               or e->>'noun' not in ('station', 'table', 'ground', 'court', 'machine', 'room')
               or jsonb_typeof(e->'uses_controllers') <> 'boolean'
               or jsonb_typeof(e->'uses_games') <> 'boolean'), 0,
  'every entry is a valid station type (code, name, group, model, unit, noun, flags)');
select is((select count(distinct e->>'code')::int from jsonb_array_elements(station_type_catalog()) e),
  jsonb_array_length(station_type_catalog()), 'codes are unique');
select ok(has_function_privilege('authenticated', 'public.station_type_catalog()', 'execute')
          and not has_function_privilege('anon', 'public.station_type_catalog()', 'execute'),
  'signed-in users may read the catalog, anon may not');
select ok(not (select prosecdef from pg_proc where oid = 'public.station_type_catalog()'::regprocedure),
  'and it runs with the caller''s privileges');

-- ------------------------------------------------ 2. venue_profile
select pg_temp.as_user('27000000-0000-0000-0000-000000000002');
select is(pg_temp.push('settings.save', '{"key":"venue_profile","json":{"resource_noun":"table"}}')
    ->>'error', 'forbidden', 'staff without settings cannot change the venue profile');
select pg_temp.as_user('27000000-0000-0000-0000-000000000001');
select is(pg_temp.push('settings.save', '{"key":"venue_profile","json":{"resource_noun":"console"}}')
    ->>'error', 'invalid_venue_profile', 'an unknown noun is refused');
select is(pg_temp.push('settings.save',
    '{"key":"venue_profile","json":{"resource_noun":"table","category":"pool"}}')->>'error',
  'invalid_venue_profile', 'unknown fields are refused');
select is(pg_temp.push('settings.save', '{"key":"venue_profile","json":{"resource_noun":"table"}}')
    ->>'status', 'applied', 'the owner names the venue''s resources tables');
select is((select json from settings where arena_id = pg_temp.arena() and key = 'venue_profile'),
  '{"resource_noun":"table"}'::jsonb, 'and it is stored for every device to read');

-- ------------------------------------------------ 3. a mixed venue adopts every catalog type
select is((select count(*)::int from jsonb_array_elements(station_type_catalog()) e
            where pg_temp.push('activity.upsert', jsonb_build_object('id', gen_random_uuid(),
                    'code', e->>'code', 'name', e->>'name',
                    'uses_controllers', e->'uses_controllers', 'uses_games', e->'uses_games',
                    'duration_model', e->>'duration_model'))->>'status' = 'applied'),
  jsonb_array_length(station_type_catalog()), 'every catalog type is accepted by activity.upsert');
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'POOL', 'band', 'standard',
    'unit_minutes', 60, 'price_paise', 20000))->>'status', 'applied', 'pool: ₹200 an hour');
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'TURF', 'band', 'standard',
    'unit_minutes', 60, 'price_paise', 120000))->>'status', 'applied', 'turf: ₹1200 per started hour');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b2700000-0000-0000-0000-000000000001',
    'name', 'Table 1', 'kind', 'table', 'activity_codes', jsonb_build_array('POOL')))->>'status', 'applied',
  'adds Table 1');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b2700000-0000-0000-0000-000000000002',
    'name', 'Ground A', 'kind', 'station', 'activity_codes', jsonb_build_array('TURF', 'CRICKET')))
    ->>'status', 'applied', 'adds Ground A offering football and cricket');

-- ------------------------------------------------ 4. pool: start, end, pay (no game, no pads)
select pg_temp.as_user('27000000-0000-0000-0000-000000000002');
select is(pg_temp.push('customer.create', jsonb_build_object('id', 'cccccccc-0000-0000-0000-000000000027',
    'name', 'Meera', 'phone', '9800002727', 'is_guest', false))->>'status', 'applied', 'staff adds a customer');
select is(pg_temp.push('session.start', pg_temp.start('f2700000-0000-0000-0000-000000000001',
    'f2700000-0000-0000-0000-000000000002', 'Table 1', 'POOL',
    '2026-10-01T09:00:00Z', '2026-10-01T10:00:00Z'))->>'status', 'applied',
  'a pool session starts with no game and no controllers');
select is((select game_id::text || '/' || controller_count::text from session_segments
            where id = 'f2700000-0000-0000-0000-000000000002'), null, 'its segment has neither');
select is(pg_temp.push('session.end', pg_temp.end_op('f2700000-0000-0000-0000-000000000001',
    'f2700000-0000-0000-0000-000000000002', 'Table 1', 'POOL', '2026-10-01T09:00:00Z',
    '2026-10-01T10:00:00Z', '2026-10-01T10:00:00Z', 60, 60, 20000, 20000))->>'status', 'applied',
  'an hour of pool ends at ₹200, matching the server''s price');
select is(pg_temp.push('payment.record', jsonb_build_object('scope', 'single',
    'parent_id', 'f2700000-0000-0000-0000-000000000001', 'payment_id', gen_random_uuid(),
    'amount_paise', 20000, 'method', 'upi'))->'result'->>'payment_status', 'paid', 'and is paid');

-- ------------------------------------------------ 5. turf: book, refuse overlap, play, pay
select is(pg_temp.push('booking.create', jsonb_build_object('id', 'b2700000-0000-0000-0000-0000000000b1',
    'customer_id', 'cccccccc-0000-0000-0000-000000000027', 'activity_code', 'TURF',
    'resource_id', pg_temp.r('Ground A'), 'scheduled_start', '2026-10-01T10:00:00Z',
    'scheduled_end', '2026-10-01T11:00:00Z'))->>'status', 'applied', 'Ground A is booked 15:30–16:30');
select is(pg_temp.push('booking.create', jsonb_build_object('id', 'b2700000-0000-0000-0000-0000000000b2',
    'activity_code', 'CRICKET', 'resource_id', pg_temp.r('Ground A'),
    'scheduled_start', '2026-10-01T10:30:00Z', 'scheduled_end', '2026-10-01T11:30:00Z'))->>'error',
  'booking_conflict', 'an overlapping booking on the same ground is refused, whatever the sport');
select is(pg_temp.push('booking.create', jsonb_build_object('id', 'b2700000-0000-0000-0000-0000000000b3',
    'activity_code', 'CRICKET', 'resource_id', pg_temp.r('Ground A'),
    'scheduled_start', '2026-10-01T11:00:00Z', 'scheduled_end', '2026-10-01T12:00:00Z'))->>'status',
  'applied', 'the next hour (touching ends) can be booked');
select is(pg_temp.push('session.start', pg_temp.start('f2700000-0000-0000-0000-000000000011',
    'f2700000-0000-0000-0000-000000000012', 'Ground A', 'TURF',
    '2026-10-01T10:00:00Z', '2026-10-01T11:00:00Z', 'b2700000-0000-0000-0000-0000000000b1'))->>'status',
  'applied', 'the booking is checked in as a session');
select is((select status from bookings where id = 'b2700000-0000-0000-0000-0000000000b1'), 'checked_in',
  'and the booking is marked checked in');
select is(pg_temp.push('session.end', pg_temp.end_op('f2700000-0000-0000-0000-000000000011',
    'f2700000-0000-0000-0000-000000000012', 'Ground A', 'TURF', '2026-10-01T10:00:00Z',
    '2026-10-01T11:00:00Z', '2026-10-01T11:00:00Z', 60, 60, 120000, 99999))->>'error', 'price_mismatch',
  'a wrong turf bill is refused');
select is(pg_temp.push('session.end', pg_temp.end_op('f2700000-0000-0000-0000-000000000011',
    'f2700000-0000-0000-0000-000000000012', 'Ground A', 'TURF', '2026-10-01T10:00:00Z',
    '2026-10-01T11:00:00Z', '2026-10-01T11:00:00Z', 60, 60, 120000, 120000))->>'status', 'applied',
  'the booked hour ends at ₹1200');
select is(pg_temp.push('payment.record', jsonb_build_object('scope', 'single',
    'parent_id', 'f2700000-0000-0000-0000-000000000011', 'payment_id', gen_random_uuid(),
    'amount_paise', 120000, 'method', 'cash'))->'result'->>'payment_status', 'paid', 'and is paid');

-- ------------------------------------------------ 6. started hours on the fixed-block model
select is((_pr_quote(_pricing_snapshot(pg_temp.arena()), 'TURF', null,
    '2026-10-01T12:00:00Z', '2026-10-01T13:10:00Z', '2026-10-01T12:00:00Z')->>'amount')::int, 240000,
  '70 minutes of turf bills two started hours');

select * from finish();
rollback;
