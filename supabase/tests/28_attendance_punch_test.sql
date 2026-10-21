-- attendance.punch (op_attendance_punch) and the 'attendance' setting: clock in / out at
-- server time with a GPS fix; the geofence verdict (inside / outside / unknown) and the
-- outside rule (block / flag / allow), the mock rule, low accuracy and no fix; one open
-- entry per person; the automatic close of a clock-in left open past max_open_hours; replay
-- and duplicate ids; and who reads what (own rows, attendance_review, other arenas, anon).
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000280'::uuid, 'pgtap 28'),
  ('e0000000-0000-4000-8000-000000000281'::uuid, 'pgtap 28 neighbour');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('28000000-0000-4000-8000-000000000001', 'owner28@test.local'),
      ('28000000-0000-4000-8000-000000000002', 'staff28@test.local'),
      ('28000000-0000-4000-8000-000000000003', 'review28@test.local'),
      ('28000000-0000-4000-8000-000000000004', 'late28@test.local'),
      ('28000000-0000-4000-8000-000000000005', 'gone28@test.local'),
      ('28000000-0000-4000-8000-000000000006', 'nextdoor28@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(id, arena_id, user_id, name, role, perms, active) values
  ('5f000000-0000-4000-8000-000000000281', 'e0000000-0000-4000-8000-000000000280',
    '28000000-0000-4000-8000-000000000001', 'Owner', 'owner', _known_perms(), true),
  ('5f000000-0000-4000-8000-000000000282', 'e0000000-0000-4000-8000-000000000280',
    '28000000-0000-4000-8000-000000000002', 'Ravi', 'staff', array['start','bill'], true),
  ('5f000000-0000-4000-8000-000000000283', 'e0000000-0000-4000-8000-000000000280',
    '28000000-0000-4000-8000-000000000003', 'Meera', 'staff', array['start','attendance_review'], true),
  ('5f000000-0000-4000-8000-000000000284', 'e0000000-0000-4000-8000-000000000280',
    '28000000-0000-4000-8000-000000000004', 'Arjun', 'staff', array['start'], true),
  ('5f000000-0000-4000-8000-000000000285', 'e0000000-0000-4000-8000-000000000280',
    '28000000-0000-4000-8000-000000000005', 'Gone', 'staff', array['start','attendance_review'], false),
  ('5f000000-0000-4000-8000-000000000286', 'e0000000-0000-4000-8000-000000000281',
    '28000000-0000-4000-8000-000000000006', 'Owner B', 'owner', _known_perms(), true);

create function pg_temp.as_user(p_n int) returns void as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub',
    '28000000-0000-4000-8000-00000000000' || p_n, 'role', 'authenticated')::text, true) $$
  language sql;
create function pg_temp.push(p_kind text, p jsonb, p_op uuid default gen_random_uuid())
  returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000280'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', p_op, 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
-- A fix: status ok with a position and accuracy.
create function pg_temp.fix(p_lat float8, p_lng float8, p_acc numeric default 8,
    p_mock boolean default false) returns jsonb as $$
  select jsonb_build_object('status', 'ok', 'lat', p_lat, 'lng', p_lng, 'accuracy_m', p_acc,
    'is_mocked', p_mock) $$ language sql;
create function pg_temp.punch(p_kind text, p_loc jsonb,
    p_id uuid default gen_random_uuid(), p_op uuid default gen_random_uuid()) returns jsonb as $$
  select pg_temp.push('attendance.punch', jsonb_build_object('punch_id', p_id, 'kind', p_kind,
    'device_id', 'pgtap-phone', 'device_at', '2000-01-01T00:00:00Z', 'location', p_loc), p_op) $$
  language sql;
create function pg_temp.settings(p_rule text, p_mock text default 'block', p_fence boolean default true)
  returns jsonb as $$
  select pg_temp.push('settings.save', jsonb_build_object('key', 'attendance', 'json',
    jsonb_build_object('geofence', case when p_fence
        then jsonb_build_object('lat', 12.9716, 'lng', 77.5946, 'radius_m', 100) else 'null'::jsonb end,
      'outside_rule', p_rule, 'min_accuracy_m', 50, 'mock_rule', p_mock, 'max_open_hours', 14))) $$
  language sql;
create function pg_temp.open_entry(p_staff text) returns attendance_entries as $$
  select * from attendance_entries where staff_id = p_staff::uuid and out_at is null and status = 'active' $$
  language sql;

-- Arena centre 12.9716, 77.5946 (radius 100 m). 12.9717 is ~11 m away; 12.9760 is ~489 m.
select ok(_geo_distance_m(12.9716, 77.5946, 12.9726, 77.5946) between 110 and 112,
  'distance: 0.001 degree of latitude is ~111 m');
select is(_geo_distance_m(12.9716, 77.5946, 12.9716, 77.5946), 0, 'distance: same point is 0 m');
select ok('attendance_review' = any(_known_perms()), 'attendance_review is a known permission');

-- ------------------------------------------------ 1. no setting yet: position unknown, flagged
select pg_temp.as_user(2);
create temp table r1 as select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)) as r;
select is((select r->>'status' from r1), 'applied', 'no setting: a clock-in is accepted');
select is((select r->'result'->>'geofence' from r1), 'unknown', 'no geofence set: the position is unknown');
select is((select r->'result'->'flags' from r1), '["no_geofence", "unknown"]'::jsonb,
  'and flagged no_geofence + unknown');
select is((select r->'result'->>'review' from r1), 'pending', 'default rule flag: up for review');
select ok((select (r->'result'->>'server_at')::timestamptz > '2020-01-01' from r1),
  'the punch time is the server''s, not the phone''s (device_at says 2000)');
select is((select device_at from attendance_punches where id = (select (r->'result'->>'punch_id')::uuid from r1)),
  '2000-01-01T00:00:00Z'::timestamptz, 'device_at is kept as evidence');
select is((select work_date from attendance_entries where id = (select (r->'result'->>'entry_id')::uuid from r1)),
  _pr_ist_date(statement_timestamp()), 'work_date is the IST date of the clock-in');
select is((pg_temp.punch('out', '{"status":"denied"}'))->>'status', 'applied',
  'clock-out with location denied: accepted under flag');
select is((select out_source from attendance_entries
            where id = (select (r->'result'->>'entry_id')::uuid from r1)), 'punch', 'the entry is closed by the punch');
select is((select flags from attendance_entries where id = (select (r->'result'->>'entry_id')::uuid from r1)),
  array['no_geofence_in','unknown_in','unknown_out'], 'entry flags say which punch was off');

-- ------------------------------------------------ 2. the setting
select is(pg_temp.settings('flag')->>'error', 'forbidden', 'staff without settings cannot change attendance rules');
select pg_temp.as_user(1);
select is(pg_temp.settings('block', 'block', false)->>'error', 'invalid_attendance_settings',
  'block without a geofence is refused');
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'attendance', 'json',
    jsonb_build_object('geofence', null, 'outside_rule', 'flag', 'min_accuracy_m', 2,
      'mock_rule', 'block', 'max_open_hours', 14))))->>'error', 'invalid_attendance_settings',
  'min_accuracy_m below 5 is refused');
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'attendance', 'json',
    jsonb_build_object('outside_rule', 'flag'))))->>'error', 'invalid_attendance_settings',
  'a partial object is refused');
select is(pg_temp.settings('flag')->>'status', 'applied', 'owner sets geofence, flag, 50 m, block mock');
select is((select json from settings where arena_id = 'e0000000-0000-4000-8000-000000000280' and key = 'attendance'),
  '{"geofence": {"lat": 12.971600, "lng": 77.594600, "radius_m": 100}, "outside_rule": "flag", "min_accuracy_m": 50, "mock_rule": "block", "max_open_hours": 14}'::jsonb,
  'stored normalised');

-- ------------------------------------------------ 3. flag rule
select pg_temp.as_user(2);
create temp table r3 as select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)) as r;
select is((select r->'result'->>'geofence' from r3), 'inside', 'a fix 11 m away is inside');
select is((select (r->'result'->>'distance_m')::int from r3), 11, 'distance is recorded');
select is((select r->'result'->'flags' from r3), '[]'::jsonb, 'nothing to flag');
select is((select r->'result'->>'review' from r3), 'none', 'not up for review');
select is((pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)))->>'error', 'already_clocked_in',
  'a second clock-in is refused while one is open');
create temp table r3o as select pg_temp.punch('out', pg_temp.fix(12.9760, 77.5946)) as r;
select is((select r->'result'->>'geofence' from r3o), 'outside', 'a fix ~489 m away is outside');
select is((select review from attendance_entries where id = (select (r->'result'->>'entry_id')::uuid from r3)),
  'pending', 'flag rule: an outside clock-out puts the entry up for review');
select is((select flags from attendance_entries where id = (select (r->'result'->>'entry_id')::uuid from r3)),
  array['outside_out'], 'flagged outside_out');
select is((pg_temp.punch('out', pg_temp.fix(12.9717, 77.5946)))->>'error', 'not_clocked_in',
  'a clock-out with nothing open is refused');

create temp table r3a as select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946, 200)) as r;
select is((select r->'result'->>'geofence' from r3a), 'unknown', 'a fix worse than 50 m is unknown');
select is((select r->'result'->'flags' from r3a), '["low_accuracy", "unknown"]'::jsonb, 'flagged low_accuracy');
select is((pg_temp.punch('out', '{"status":"gps_off"}'))->>'status', 'applied', 'clock out with GPS off (flag)');

select is((pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946, 8, true)))->>'error', 'mock_location',
  'mock_rule block: a mock location is refused');
select is((select count(*)::int from attendance_punches where staff_id = '5f000000-0000-4000-8000-000000000282'
            and is_mocked), 0, 'and leaves no punch behind');

-- ------------------------------------------------ 4. payload checks
select is((pg_temp.push('attendance.punch', jsonb_build_object('kind', 'in', 'device_id', 'x',
    'location', '{"status":"denied"}'::jsonb)))->>'error', 'invalid_payload', 'punch_id is required');
select is((pg_temp.push('attendance.punch', jsonb_build_object('punch_id', gen_random_uuid(), 'kind', 'break',
    'device_id', 'x', 'location', '{"status":"denied"}'::jsonb)))->>'error', 'invalid_payload', 'kind is in or out');
select is((pg_temp.push('attendance.punch', jsonb_build_object('punch_id', gen_random_uuid(), 'kind', 'in',
    'device_id', 'x', 'location', '{"status":"ok"}'::jsonb)))->>'error', 'invalid_payload',
  'status ok needs a position');
select is((pg_temp.push('attendance.punch', jsonb_build_object('punch_id', gen_random_uuid(), 'kind', 'in',
    'device_id', 'x', 'location', '{"status":"denied","lat":1,"lng":1,"accuracy_m":5}'::jsonb)))->>'error',
  'invalid_payload', 'a position needs status ok');
select is((pg_temp.push('attendance.punch', jsonb_build_object('punch_id', gen_random_uuid(), 'kind', 'in',
    'device_id', ' ', 'location', '{"status":"denied"}'::jsonb)))->>'error', 'invalid_payload', 'device_id is required');

-- ------------------------------------------------ 5. replay and duplicate ids
create temp table ids as select gen_random_uuid() as punch, gen_random_uuid() as op;
select is((pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946), (select punch from ids), (select op from ids)))->>'status',
  'applied', 'clock in');
create temp table r5 as select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946), (select punch from ids), (select op from ids)) as r;
select is((select r->>'replayed' from r5), 'true', 'the same op sent again replays its first answer');
select is((select count(*)::int from attendance_punches where id = (select punch from ids)), 1,
  'and records one punch');
select is((pg_temp.punch('out', pg_temp.fix(12.9717, 77.5946), (select punch from ids)))->>'error', 'duplicate',
  'a new op reusing a punch_id is refused');
select is((pg_temp.punch('out', pg_temp.fix(12.9717, 77.5946)))->>'status', 'applied', 'clock out');

-- ------------------------------------------------ 6. block and allow
select pg_temp.as_user(1);
select is(pg_temp.settings('block')->>'status', 'applied', 'owner switches to block');
select pg_temp.as_user(2);
create temp table r6 as select pg_temp.punch('in', pg_temp.fix(12.9760, 77.5946)) as r;
select is((select r->>'error' from r6), 'outside_geofence', 'block: outside is refused');
select is((select r->>'detail' from r6), '489 m from the arena; the limit is 100 m', 'the hint says how far');
select is((pg_temp.punch('in', '{"status":"denied"}'))->>'error', 'location_required', 'block: no location is refused');
select is((pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946, 200)))->>'error', 'location_required',
  'block: a poor fix is refused');
select is((pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)))->>'status', 'applied', 'block: inside is accepted');
select is((pg_temp.punch('out', pg_temp.fix(12.9717, 77.5946)))->>'status', 'applied', 'and out');

select pg_temp.as_user(1);
select is(pg_temp.settings('allow', 'flag')->>'status', 'applied', 'owner switches to allow, mock flag');
select pg_temp.as_user(2);
create temp table r6a as select pg_temp.punch('in', pg_temp.fix(12.9760, 77.5946)) as r;
select is((select r->'result'->>'geofence' from r6a), 'outside', 'allow: outside is recorded');
select is((select r->'result'->>'review' from r6a), 'none', 'allow: but not put up for review');
select is((pg_temp.punch('out', pg_temp.fix(12.9717, 77.5946, 8, true)))->'result'->>'review', 'pending',
  'mock_rule flag: a mock location is accepted and put up for review');
select is((select is_mocked from attendance_punches where staff_id = '5f000000-0000-4000-8000-000000000282'
            and kind = 'out' order by server_at desc limit 1), true, 'and the punch says so');

-- ------------------------------------------------ 7. a clock-in left open too long
-- Arjun clocked in 20 h ago and never out (max_open_hours = 14).
insert into attendance_entries(id, arena_id, staff_id, work_date, in_at, created_by) values
  ('ae000000-0000-4000-8000-000000000281', 'e0000000-0000-4000-8000-000000000280',
   '5f000000-0000-4000-8000-000000000284', _pr_ist_date(now() - interval '20 hours'),
   now() - interval '20 hours', '28000000-0000-4000-8000-000000000004');
select pg_temp.as_user(4);
create temp table r7 as select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)) as r;
select is((select r->>'status' from r7), 'applied', 'a new clock-in is accepted');
select is((select r->'result'->>'auto_closed_entry_id' from r7), 'ae000000-0000-4000-8000-000000000281',
  'after closing the stale one');
-- No shift: a forgotten clock-in counts a standard day (8 h), never more than max_open_hours.
select is((select (out_at - in_at) from attendance_entries where id = 'ae000000-0000-4000-8000-000000000281'),
  interval '8 hours', 'closed at clock-in + the standard day (no shift)');
select is((select array[out_source, review] || flags from attendance_entries
            where id = 'ae000000-0000-4000-8000-000000000281'),
  array['auto','pending','auto_out'], 'marked auto, flagged auto_out, up for review');
select is((pg_temp.open_entry('5f000000-0000-4000-8000-000000000284')).id::text,
  (select r->'result'->>'entry_id' from r7), 'the new clock-in is the open entry');
-- Meera clocked in 20 h ago and only now clocks out (past max_open_hours): the stretch is cut
-- to a standard day and keeps the tap as evidence.
insert into attendance_entries(id, arena_id, staff_id, work_date, in_at, created_by) values
  ('ae000000-0000-4000-8000-000000000283', 'e0000000-0000-4000-8000-000000000280',
   '5f000000-0000-4000-8000-000000000283', _pr_ist_date(now() - interval '20 hours'),
   now() - interval '20 hours', '28000000-0000-4000-8000-000000000003');
select pg_temp.as_user(3);
create temp table r7o as select pg_temp.punch('out', pg_temp.fix(12.9717, 77.5946)) as r;
select is((select r->'result'->>'auto_closed_entry_id' from r7o), 'ae000000-0000-4000-8000-000000000283',
  'a late clock-out closes the stale entry automatically');
select is((select out_at - in_at from attendance_entries where id = 'ae000000-0000-4000-8000-000000000283'),
  interval '8 hours', 'at clock-in + the standard day');
select is((select out_source from attendance_entries where id = 'ae000000-0000-4000-8000-000000000283'),
  'auto', 'marked auto');
select is((select out_punch_id::text from attendance_entries where id = 'ae000000-0000-4000-8000-000000000283'),
  (select r->'result'->>'punch_id' from r7o), 'with the clock-out punch kept as evidence');

-- ------------------------------------------------ 8. who reads what
select pg_temp.as_user(3);
select is((pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)))->>'status', 'applied', 'the reviewer clocks in too');
select pg_temp.as_user(5);
select throws_ok($$ select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)) $$, '42501', 'forbidden',
  'a deactivated member cannot punch (sync_push refuses the whole batch)');
select pg_temp.as_user(6);
select throws_ok($$ select pg_temp.punch('in', pg_temp.fix(12.9717, 77.5946)) $$, '42501', 'forbidden',
  'a member of another arena cannot punch here');

create function pg_temp.seen() returns text as $$
  select (select count(distinct staff_id) from attendance_punches
           where arena_id = 'e0000000-0000-4000-8000-000000000280')
    || '/' || (select count(distinct staff_id) from attendance_entries
           where arena_id = 'e0000000-0000-4000-8000-000000000280') $$ language sql;
set local role authenticated;
select pg_temp.as_user(2);
select is(pg_temp.seen(), '1/1', 'staff see only their own punches and entries');
select pg_temp.as_user(3);
select is(pg_temp.seen(), '3/3', 'attendance_review sees everyone''s');
select pg_temp.as_user(1);
select is(pg_temp.seen(), '3/3', 'the owner sees everyone''s');
select pg_temp.as_user(5);
select is(pg_temp.seen(), '0/0', 'a deactivated member sees nothing');
select pg_temp.as_user(6);
select is(pg_temp.seen(), '0/0', 'another arena''s owner sees nothing');
reset role;
select ok(not has_table_privilege('anon', 'public.attendance_punches', 'select')
          and not has_table_privilege('anon', 'public.attendance_entries', 'select'),
  'anon reads neither table');
select ok(not has_function_privilege('authenticated', 'public.op_attendance_punch(uuid,jsonb)', 'execute'),
  'the op is reached only through sync_push');

select * from finish();
rollback;
