-- Shifts, staff holidays and working hours; the attendance day (_att_day: status, break,
-- rounding, late / early, extra hours, split and midnight shifts); attendance corrections
-- (edit / void / add with history, own-record rule, review); forgotten clock-outs at the shift
-- end; attendance_days and who may read it; the new permissions and who may grant them.
-- Days are in January 2026 (in the past, whatever today is).
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000290'::uuid, 'pgtap 29');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('29000000-0000-4000-8000-000000000001', 'owner29@test.local'),
      ('29000000-0000-4000-8000-000000000002', 'ravi29@test.local'),
      ('29000000-0000-4000-8000-000000000003', 'meera29@test.local'),
      ('29000000-0000-4000-8000-000000000004', 'manager29@test.local'),
      ('29000000-0000-4000-8000-000000000005', 'priya29@test.local'),
      ('29000000-0000-4000-8000-000000000006', 'sam29@test.local'),
      ('29000000-0000-4000-8000-000000000007', 'tom29@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(id, arena_id, user_id, name, role, perms, active, created_at) values
  ('5f000000-0000-4000-8000-000000000291', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000001', 'Owner', 'owner', _known_perms(), true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000292', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000002', 'Ravi', 'staff', array['start'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000293', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000003', 'Meera', 'staff', array['start','attendance_review'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000294', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000004', 'Manager', 'staff', array['start','settings'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000295', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000005', 'Priya', 'staff', array['start'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000296', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000006', 'Sam', 'staff', array['start'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000297', 'e0000000-0000-4000-8000-000000000290',
    '29000000-0000-4000-8000-000000000007', 'Tom', 'staff', array['start'], true, '2025-01-01');

create function pg_temp.as_user(p_n int) returns void as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub',
    '29000000-0000-4000-8000-00000000000' || p_n, 'role', 'authenticated')::text, true) $$
  language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000290'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
-- An IST wall time as an instant.
create function pg_temp.ist(p text) returns timestamptz as $$
  select (p::timestamp) at time zone 'Asia/Kolkata' $$ language sql;
-- A stretch of work, written straight into the table (as a punch would have).
create function pg_temp.work(p_staff text, p_in text, p_out text, p_id uuid default gen_random_uuid())
  returns uuid as $$
  insert into attendance_entries(id, arena_id, staff_id, work_date, in_at, out_at, out_source, created_by)
    values (p_id, 'e0000000-0000-4000-8000-000000000290', p_staff::uuid,
      _pr_ist_date(pg_temp.ist(p_in)), pg_temp.ist(p_in), pg_temp.ist(p_out),
      case when p_out is null then null else 'punch' end, '29000000-0000-4000-8000-000000000002')
  returning id $$ language sql;
create function pg_temp.day(p_staff text, p_day text) returns jsonb as $$
  select _att_day(p_staff::uuid, p_day::date, now()) $$ language sql;

-- ------------------------------------------------ 1. permissions
select ok(_known_perms() @> array['attendance_review','leave_approve','payroll','payroll_finalise'],
  'the staff-module permissions are known');
select pg_temp.as_user(4);
select is((pg_temp.push('staff.update', jsonb_build_object('user_id', '29000000-0000-4000-8000-000000000003',
    'perms', jsonb_build_array('start','attendance_review','leave_approve'))))->>'status', 'applied',
  'a settings holder grants leave_approve');
select is((pg_temp.push('staff.update', jsonb_build_object('user_id', '29000000-0000-4000-8000-000000000003',
    'perms', jsonb_build_array('start','attendance_review','payroll'))))->>'error', 'forbidden',
  'but not payroll (owner level only)');
select pg_temp.as_user(1);
select is((pg_temp.push('staff.update', jsonb_build_object('user_id', '29000000-0000-4000-8000-000000000003',
    'perms', jsonb_build_array('start','attendance_review'))))->>'status', 'applied', 'the owner sets perms back');

-- ------------------------------------------------ 2. settings: work_hours, leave_rules
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'work_hours', 'json',
    jsonb_build_object('late_grace_min', 10))))->>'error', 'invalid_work_hours', 'work_hours needs every field');
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'work_hours', 'json',
    _work_hours('e0000000-0000-4000-8000-000000000290') || '{"half_day_pct": 80}')))->>'error',
  'invalid_work_hours', 'half day must be below full day');
select is(_work_hours('e0000000-0000-4000-8000-000000000290')->>'standard_day_min', '480', 'default standard day 8 h');
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'leave_rules', 'json',
    jsonb_build_object('paid_leave_days', 12.3, 'half_day_allowed', true, 'unplanned_backdate_days', 7))))->>'error',
  'invalid_leave_rules', 'paid leave days in halves only');
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'leave_rules', 'json',
    jsonb_build_object('paid_leave_days', 12.5, 'half_day_allowed', true, 'unplanned_backdate_days', 7))))->>'status',
  'applied', 'leave rules saved');

-- ------------------------------------------------ 3. shifts, assignments, holidays
select pg_temp.as_user(2);
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000291',
    'name', 'Day', 'start_min', 660, 'end_min', 1200, 'days', '[1,2,3,4,5,6]'::jsonb, 'break_min', 60))
  )->>'error', 'forbidden', 'staff cannot edit shifts');
select pg_temp.as_user(4);
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000291',
    'name', 'Day', 'start_min', 660, 'end_min', 1200, 'days', '[1,2,3,4,5,6]'::jsonb, 'break_min', 60))
  )->>'status', 'applied', 'Day shift Mon–Sat 11:00–20:00, 60 min break');
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000292',
    'name', 'Eve', 'start_min', 960, 'end_min', 1320, 'days', '[1,2,4,5,6,7]'::jsonb, 'break_min', 30))
  )->>'status', 'applied', 'Eve shift 16:00–22:00 (no Wednesday), 30 min break');
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', gen_random_uuid(),
    'name', 'day', 'start_min', 600, 'end_min', 900, 'days', '[1]'::jsonb, 'break_min', 0)))->>'error',
  'duplicate', 'shift names are unique (any case)');
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', gen_random_uuid(),
    'name', 'Bad', 'start_min', 600, 'end_min', 600, 'days', '[1]'::jsonb)))->>'error',
  'invalid_shift', 'start and end must differ');
select is((pg_temp.push('shift.assign', jsonb_build_object('id', 'a6000000-0000-4000-8000-000000000291',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'shift_id', 'a5000000-0000-4000-8000-000000000291',
    'effective_from', '2025-12-01')))->>'status', 'applied', 'Ravi on Day from 1 Dec');
select is((pg_temp.push('shift.assign', jsonb_build_object('id', gen_random_uuid(),
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'shift_id', 'a5000000-0000-4000-8000-000000000291',
    'effective_from', '2026-01-10', 'effective_to', '2026-01-20')))->>'error', 'assignment_overlap',
  'the same shift twice over the same days is refused');
select is((pg_temp.push('shift.assign', jsonb_build_object('id', 'a6000000-0000-4000-8000-000000000292',
    'staff_id', '5f000000-0000-4000-8000-000000000295', 'shift_id', 'a5000000-0000-4000-8000-000000000292',
    'effective_from', '2025-12-01')))->>'status', 'applied', 'Priya on Eve');
select is((pg_temp.push('staff_holiday.upsert', jsonb_build_object('day', '2026-01-02', 'name', 'Founders day')))->>'status',
  'applied', 'a staff holiday on Fri 2 Jan (paid by default)');
select is((select paid from staff_holidays where arena_id = 'e0000000-0000-4000-8000-000000000290' and day = '2026-01-02'),
  true, 'paid');

-- ------------------------------------------------ 4. the attendance day
select pg_temp.work('5f000000-0000-4000-8000-000000000292', '2026-01-05 11:02', '2026-01-05 20:00');
select pg_temp.work('5f000000-0000-4000-8000-000000000292', '2026-01-06 11:20', '2026-01-06 20:00');
create temp table half_entry as
  select pg_temp.work('5f000000-0000-4000-8000-000000000292', '2026-01-07 11:00', '2026-01-07 15:00') as id;
select pg_temp.work('5f000000-0000-4000-8000-000000000292', '2026-01-04 12:00', '2026-01-04 14:00');
select pg_temp.work('5f000000-0000-4000-8000-000000000292', '2026-01-02 11:00', '2026-01-02 19:00');
create temp table long_entry as
  select pg_temp.work('5f000000-0000-4000-8000-000000000292', '2026-01-09 11:00', '2026-01-09 23:00') as id;

select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-05') - array['day','flags','holiday','holiday_paid'],
  '{"status":"present","sched_min":480,"worked_min":478,"regular_min":478,"extra_min":0,"late":false,"early":false,
    "present_units":1,"absent_units":0,"half_day":false,"leave_units":0,"leave_paid":0,"leave_lop":0,"open":false,"entries":1}'::jsonb,
  'Mon 11:02–20:00: present, 538 clocked − 60 break = 478, within the grace');
select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-06')->>'status', 'late', 'Tue 11:20: late');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-07') ->> 'status'), 'half_day',
  'Wed 11:00–15:00 (240 min, no break under 300): half day (>= 40 %, < 75 %)');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-07') ->> 'early')::boolean, true,
  'and left early');
select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-08')->>'status', 'absent', 'Thu: no clock-in = absent');
select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-04') ->> 'status', 'week_off', 'Sun: week off');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-04') ->> 'extra_min')::int, 120,
  'work on a week off is all extra');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-02')->>'status'), 'holiday', 'Fri 2 Jan: holiday');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-02')->>'extra_min')::int, 420,
  'work on a holiday is all extra (480 − 60 break)');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-09')->>'extra_min')::int, 180,
  'a 12 h day (660 after the break) has 180 min beyond the 8 h standard day');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000292', '2024-06-01')->>'status'), 'not_employed',
  'before joining: not employed');

-- Priya: a split shift (the gap covers the break) and a shift past midnight.
select pg_temp.work('5f000000-0000-4000-8000-000000000295', '2026-01-08 12:00', '2026-01-08 14:00');
select pg_temp.work('5f000000-0000-4000-8000-000000000295', '2026-01-08 17:00', '2026-01-08 22:20');
select pg_temp.work('5f000000-0000-4000-8000-000000000295', '2026-01-09 16:00', '2026-01-10 02:10');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000295', '2026-01-08')->>'worked_min')::int, 440,
  'split shift 2 h + 5 h 20: 440, no break (the 180 min gap covers it)');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000295', '2026-01-09')->>'worked_min')::int, 580,
  'Fri 16:00 → Sat 02:10 counts on Friday: 610 − 30');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000295', '2026-01-10')->>'entries')::int, 0,
  'and nothing on Saturday');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000295', '2026-01-07')->>'status'), 'week_off',
  'Eve does not run on Wednesday');

select pg_temp.as_user(4);
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'work_hours', 'json',
    _work_hours('e0000000-0000-4000-8000-000000000290') || '{"rounding": "nearest_15"}')))->>'status',
  'applied', 'round to the nearest 15 minutes');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000295', '2026-01-08')->>'worked_min')::int, 435,
  '440 → 435');
select is((pg_temp.day('5f000000-0000-4000-8000-000000000295', '2026-01-09')->>'worked_min')::int, 585,
  '580 → 585 (7.5 rounds up)');
select is((pg_temp.push('settings.save', jsonb_build_object('key', 'work_hours', 'json',
    _work_hours('e0000000-0000-4000-8000-000000000290') || '{"rounding": "exact"}')))->>'status', 'applied', 'back to exact');

-- ------------------------------------------------ 5. corrections
select pg_temp.as_user(2);
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'in_at', pg_temp.ist('2026-01-08 11:00'),
    'out_at', pg_temp.ist('2026-01-08 20:00'), 'reason', 'forgot')))->>'error', 'forbidden',
  'staff cannot correct attendance');
select pg_temp.as_user(3);
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'in_at', pg_temp.ist('2026-01-08 11:00'),
    'out_at', pg_temp.ist('2026-01-08 20:00'))))->>'error', 'reason_required', 'a correction needs a reason');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'in_at', pg_temp.ist('2026-01-08 11:00'),
    'out_at', pg_temp.ist('2026-01-08 10:00'), 'reason', 'x')))->>'error', 'invalid_times', 'out before in');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'in_at', now() + interval '1 hour',
    'out_at', now() + interval '2 hours', 'reason', 'x')))->>'error', 'invalid_times', 'not in the future');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'in_at', pg_temp.ist('2026-01-05 19:00'),
    'out_at', pg_temp.ist('2026-01-05 21:00'), 'reason', 'x')))->>'error', 'overlap',
  'not over another active stretch');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000293', 'in_at', pg_temp.ist('2026-01-08 11:00'),
    'out_at', pg_temp.ist('2026-01-08 20:00'), 'reason', 'me')))->>'error', 'own_record',
  'a reviewer cannot correct their own attendance');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'add',
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'in_at', pg_temp.ist('2026-01-08 11:00'),
    'out_at', pg_temp.ist('2026-01-08 20:00'), 'reason', 'Forgot to clock in; seen on CCTV')))->>'status',
  'applied', 'a missing day is added');
select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-08')->>'status', 'present', 'Thu is now present');

create temp table edit1 as select pg_temp.push('attendance.correct', jsonb_build_object('action', 'edit',
    'entry_id', (select id from half_entry), 'in_at', pg_temp.ist('2026-01-07 11:00'),
    'out_at', pg_temp.ist('2026-01-07 20:00'), 'reason', 'Stayed till close')) as r;
select is((select r->>'status' from edit1), 'applied', 'an entry is corrected');
select is((select status from attendance_entries where id = (select id from half_entry)), 'superseded',
  'the original is kept, superseded');
select is((select replaces_id from attendance_entries where id = (select (r->'result'->>'entry_id')::uuid from edit1)),
  (select id from half_entry), 'the new row points at it');
select is((select array[source, review, reason] from attendance_entries
            where id = (select (r->'result'->>'entry_id')::uuid from edit1)),
  array['manual', 'corrected', 'Stayed till close'], 'marked manual, corrected, with the reason');
select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-07')->>'status', 'present', 'Wed is now present');
select is((select count(*)::int from audit_log where entity_id = (select (r->'result'->>'entry_id')::uuid from edit1)
            and action = 'correct' and before->>'out_at' is not null), 1, 'and audited with before / after');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'edit',
    'entry_id', (select id from half_entry), 'in_at', pg_temp.ist('2026-01-07 11:00'),
    'out_at', pg_temp.ist('2026-01-07 19:00'), 'reason', 'again')))->>'error', 'not_active',
  'a superseded row cannot be corrected again');
select is((pg_temp.push('attendance.correct', jsonb_build_object('action', 'void',
    'entry_id', (select id from long_entry), 'reason', 'Was off sick, logged by mistake')))->>'status',
  'applied', 'an entry is voided');
select is(pg_temp.day('5f000000-0000-4000-8000-000000000292', '2026-01-09')->>'status', 'absent',
  'Fri no longer counts');

-- Review: accept a flagged entry once.
update attendance_entries set review = 'pending', flags = '{outside_out}'
 where staff_id = '5f000000-0000-4000-8000-000000000292' and work_date = '2026-01-06';
select is((pg_temp.push('attendance.review', jsonb_build_object('entry_id',
    (select id from attendance_entries where staff_id = '5f000000-0000-4000-8000-000000000292'
      and work_date = '2026-01-06'), 'note', 'Was getting change')))->>'status', 'applied', 'a flag is accepted');
select is((pg_temp.push('attendance.review', jsonb_build_object('entry_id',
    (select id from attendance_entries where staff_id = '5f000000-0000-4000-8000-000000000292'
      and work_date = '2026-01-06'))))->>'error', 'not_pending', 'only once');

-- ------------------------------------------------ 6. forgotten clock-outs, with shifts
-- A shift that ended 3 h ago after 7 h (relative to now); Sam and Tom started it and never left.
create temp table rel as select
  (extract(hour from (now() at time zone 'Asia/Kolkata'))::int * 60
   + extract(minute from (now() at time zone 'Asia/Kolkata'))::int) as m;
select pg_temp.as_user(4);
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000293',
    'name', 'Rel', 'start_min', ((select m from rel) - 600 + 2880) % 1440,
    'end_min', ((select m from rel) - 180 + 2880) % 1440, 'days', '[1,2,3,4,5,6,7]'::jsonb, 'break_min', 0)))->>'status',
  'applied', 'a 7 h shift that ended 3 h ago');
select pg_temp.push('shift.assign', jsonb_build_object('id', gen_random_uuid(), 'staff_id', s,
    'shift_id', 'a5000000-0000-4000-8000-000000000293', 'effective_from', '2025-01-01'))
  from unnest(array['5f000000-0000-4000-8000-000000000296', '5f000000-0000-4000-8000-000000000297']) s;
insert into attendance_entries(id, arena_id, staff_id, work_date, in_at, created_by)
  select gen_random_uuid(), 'e0000000-0000-4000-8000-000000000290', s::uuid,
         _pr_ist_date(now() - interval '600 minutes'), now() - interval '600 minutes',
         '29000000-0000-4000-8000-000000000006'
    from unnest(array['5f000000-0000-4000-8000-000000000296', '5f000000-0000-4000-8000-000000000297']) s;

select pg_temp.as_user(6);
create temp table sam as select pg_temp.push('attendance.punch', jsonb_build_object('punch_id', gen_random_uuid(),
    'kind', 'in', 'device_id', 'p', 'location', '{"status":"denied"}'::jsonb)) as r;
select is((select r->>'status' from sam), 'applied', 'a clock-in after the shift end + grace is accepted');
select ok((select (out_at - (now() - interval '600 minutes')) between interval '419 minutes' and interval '420 minutes'
             and out_source = 'auto' and review = 'pending' and 'auto_out' = any(flags)
             from attendance_entries where id = (select (r->'result'->>'auto_closed_entry_id')::uuid from sam)),
  'the forgotten one closes at the shift end (7 h), flagged for review');

select pg_temp.as_user(7);
create temp table tom as select pg_temp.push('attendance.punch', jsonb_build_object('punch_id', gen_random_uuid(),
    'kind', 'out', 'device_id', 'p', 'location', '{"status":"denied"}'::jsonb)) as r;
select is((select r->'result'->>'auto_closed_entry_id' from tom), null,
  'a clock-out 3 h after the shift end (within max_open_hours) is not cut');
select ok((select out_source = 'punch' and review = 'pending' and 'past_shift_end' = any(flags)
             and out_at > now() - interval '1 minute'
             from attendance_entries where id = (select (r->'result'->>'entry_id')::uuid from tom)),
  'it keeps its real time, flagged past_shift_end for review');

-- ------------------------------------------------ 7. attendance_days: who reads what
set local role authenticated;
select pg_temp.as_user(2);
select is(jsonb_array_length(attendance_days('e0000000-0000-4000-8000-000000000290', '2026-01-01', '2026-01-10',
    '5f000000-0000-4000-8000-000000000292')), 10, 'staff read their own days');
select throws_ok($$ select attendance_days('e0000000-0000-4000-8000-000000000290', '2026-01-01', '2026-01-10',
    '5f000000-0000-4000-8000-000000000295') $$, '42501', 'forbidden', 'not someone else''s');
select throws_ok($$ select attendance_days('e0000000-0000-4000-8000-000000000290', '2026-01-01', '2026-01-10') $$,
  '42501', 'forbidden', 'nor everyone''s');
select pg_temp.as_user(3);
create temp table all_days as select attendance_days('e0000000-0000-4000-8000-000000000290', '2026-01-01', '2026-01-10') as j;
select ok((select jsonb_array_length(j) from all_days) >= 50, 'a reviewer reads every tracked person''s days');
select is((select count(*)::int from all_days, jsonb_array_elements(j) x where x->>'staff_name' = 'Owner'), 0,
  'the owner is not tracked by default');
select is((select x->>'status' from all_days, jsonb_array_elements(j) x
            where x->>'staff_name' = 'Ravi' and x->>'work_date' = '2026-01-07'), 'present',
  'with the same status as the salary run will use');
select throws_ok($$ select attendance_days('e0000000-0000-4000-8000-000000000290', '2026-01-01', '2026-03-31') $$,
  'P0001', 'invalid_period', 'at most 62 days');
-- ------------------------------------------------ roster changes never rewrite worked days
reset role;
select pg_temp.as_user(4);
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000291',
    'name', 'Day', 'start_min', 660, 'end_min', 1200, 'days', '[1,2,3,4,5,6]'::jsonb, 'break_min', 60,
    'active', false)))->>'detail', 'Ravi',
  'a shift someone is still on cannot be turned off (end their assignment first)');
select pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-0000000002f1',
  'name', 'Night', 'start_min', 1320, 'end_min', 360, 'days', '[1,2,3,4,5,6,7]'::jsonb, 'break_min', 0));
select pg_temp.push('shift.assign', jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000002f1',
  'staff_id', '5f000000-0000-4000-8000-000000000293', 'shift_id', 'a5000000-0000-4000-8000-0000000002f1',
  'effective_from', (_pr_ist_date(now()) - 30)::text));
select pg_temp.push('shift.assign', jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000002f2',
  'staff_id', '5f000000-0000-4000-8000-000000000292', 'shift_id', 'a5000000-0000-4000-8000-0000000002f1',
  'effective_from', (_pr_ist_date(now()) + 7)::text));
-- A shift counts from its start to its end on the day it starts (Night 22:00–06:00).
select is(_att_work_date('5f000000-0000-4000-8000-000000000293',
    pg_temp.ist(_pr_ist_date(now())::text || ' 02:00')), _pr_ist_date(now()) - 1,
  'a clock-in at 02:00 inside the night shift belongs to the night it started');
select is(_att_work_date('5f000000-0000-4000-8000-000000000293',
    pg_temp.ist(_pr_ist_date(now())::text || ' 21:15')), _pr_ist_date(now()),
  'a clock-in shortly before 22:00 belongs to that night');
select is(_att_work_date('5f000000-0000-4000-8000-000000000292',
    pg_temp.ist(_pr_ist_date(now())::text || ' 02:00')), _pr_ist_date(now()),
  'with no shift around it, the IST date');
select pg_temp.push('shift.unassign', jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000002f1'));
select is((select effective_to from staff_shifts where id = 'a6000000-0000-4000-8000-0000000002f1'),
  _pr_ist_date(now()) - 1, 'ending an assignment that has started keeps it, ended yesterday');
select pg_temp.push('shift.unassign', jsonb_build_object('id', 'a6000000-0000-4000-8000-0000000002f2'));
select ok(not exists (select 1 from staff_shifts where id = 'a6000000-0000-4000-8000-0000000002f2'),
  'an assignment that has not started is deleted');
select is((pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-0000000002f1',
    'name', 'Night', 'start_min', 1320, 'end_min', 360, 'days', '[1,2,3,4,5,6,7]'::jsonb, 'break_min', 0,
    'active', false)))->>'status', 'applied', 'once nobody is on it from today, the shift can be turned off');
select is((pg_temp.push('shift.assign', jsonb_build_object('id', gen_random_uuid(),
    'staff_id', '5f000000-0000-4000-8000-000000000292', 'shift_id', 'a5000000-0000-4000-8000-0000000002f1',
    'effective_from', (_pr_ist_date(now()) + 1)::text)))->>'error', 'shift_inactive',
  'nobody is put on a shift that is not in use');

reset role;

select * from finish();
rollback;
