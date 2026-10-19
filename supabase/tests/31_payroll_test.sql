-- Salary runs: the three worked examples of docs/STAFF.md §4.3 to the paisa, the owner's keep /
-- waive decisions, adjustments and reversals, finalise (and its locks), discard, overlaps,
-- net_negative, the payroll / payroll_finalise permissions and that staff can read no pay.
-- The examples' October 2026 calendar is replayed in January 2026 (same weekdays: the 1st a
-- Thursday, the 2nd a Friday, Sundays 4/11/18/25) so the days are always in the past.
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000310'::uuid, 'pgtap 31 monthly'),
  ('e0000000-0000-4000-8000-000000000311'::uuid, 'pgtap 31 weekly');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', ('31000000-0000-4000-8000-00000000000' || n)::uuid,
         'authenticated', 'authenticated', 'u' || n || '@pgtap31.local', '', now(), now(), now(),
         '{}', '{}', false, false
    from generate_series(1, 7) n
  on conflict (id) do nothing;
insert into staff_profiles(id, arena_id, user_id, name, role, perms, active, created_at) values
  ('5f000000-0000-4000-8000-000000000311', 'e0000000-0000-4000-8000-000000000310',
    '31000000-0000-4000-8000-000000000001', 'Owner', 'owner', _known_perms(), true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000312', 'e0000000-0000-4000-8000-000000000310',
    '31000000-0000-4000-8000-000000000002', 'Ravi', 'staff', array['start'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000313', 'e0000000-0000-4000-8000-000000000310',
    '31000000-0000-4000-8000-000000000003', 'Arjun', 'staff', array['start'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000314', 'e0000000-0000-4000-8000-000000000310',
    '31000000-0000-4000-8000-000000000004', 'Bob', 'staff', array['start'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000315', 'e0000000-0000-4000-8000-000000000310',
    '31000000-0000-4000-8000-000000000005', 'Kim', 'staff', array['start','money','payroll','attendance_review'], true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000316', 'e0000000-0000-4000-8000-000000000311',
    '31000000-0000-4000-8000-000000000006', 'Owner W', 'owner', _known_perms(), true, '2025-01-01'),
  ('5f000000-0000-4000-8000-000000000317', 'e0000000-0000-4000-8000-000000000311',
    '31000000-0000-4000-8000-000000000007', 'Priya', 'staff', array['start'], true, '2025-01-01');

create function pg_temp.as_user(p_n int) returns void as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub',
    '31000000-0000-4000-8000-00000000000' || p_n, 'role', 'authenticated')::text, true) $$
  language sql;
create function pg_temp.push(p_arena text, p_kind text, p jsonb) returns jsonb as $$
  select sync_push(p_arena::uuid,
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
create function pg_temp.m(p_kind text, p jsonb) returns jsonb as $$
  select pg_temp.push('e0000000-0000-4000-8000-000000000310', p_kind, p) $$ language sql;
create function pg_temp.w(p_kind text, p jsonb) returns jsonb as $$
  select pg_temp.push('e0000000-0000-4000-8000-000000000311', p_kind, p) $$ language sql;
create function pg_temp.ist(p text) returns timestamptz as $$
  select (p::timestamp) at time zone 'Asia/Kolkata' $$ language sql;
create function pg_temp.work(p_arena text, p_staff text, p_in text, p_out text,
    p_out_source text default 'punch') returns void as $$
  insert into attendance_entries(arena_id, staff_id, work_date, in_at, out_at, out_source, created_by)
    values (p_arena::uuid, p_staff::uuid, _pr_ist_date(pg_temp.ist(p_in)), pg_temp.ist(p_in),
      pg_temp.ist(p_out), p_out_source, '31000000-0000-4000-8000-000000000001') $$ language sql;
-- Approved leave with its paid / LOP split, as op_leave_decide pins it.
create function pg_temp.leave(p_arena text, p_staff text, p_day text, p_paid numeric) returns void as $$
  insert into leave_requests(id, arena_id, staff_id, kind, from_date, to_date, days, paid_days,
      lop_days, day_split, reason, status, decided_at, created_by)
    values (gen_random_uuid(), p_arena::uuid, p_staff::uuid, 'planned', p_day::date, p_day::date, 1,
      p_paid, 1 - p_paid, jsonb_build_array(jsonb_build_object('day', p_day, 'units', 1, 'paid_units', p_paid)),
      'test', 'approved', now(), '31000000-0000-4000-8000-000000000001') $$ language sql;
create function pg_temp.line(p_run text, p_staff text) returns salary_run_lines as $$
  select * from salary_run_lines where run_id = p_run::uuid and staff_id = p_staff::uuid $$ language sql;
create function pg_temp.ded(p_run text, p_staff text, p_code text) returns jsonb as $$
  select x from salary_run_lines l, jsonb_array_elements(l.deductions) x
   where l.run_id = p_run::uuid and l.staff_id = p_staff::uuid and x->>'code' = p_code $$ language sql;

-- ------------------------------------------------ arena M (monthly): rules, shifts, rates
select pg_temp.as_user(1);
select pg_temp.m('pay_policy.add', jsonb_build_object('id', gen_random_uuid(), 'effective_from', '2025-12-01',
  'policy', _pay_policy('e0000000-0000-4000-8000-000000000310', '2025-12-01') || '{"extra_multiplier": 1.5}'));
select pg_temp.m('staff_holiday.upsert', jsonb_build_object('day', '2026-01-02', 'name', 'Holiday'));
select pg_temp.m('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000311', 'name', 'Day',
  'start_min', 660, 'end_min', 1200, 'days', '[1,2,3,4,5,6]'::jsonb, 'break_min', 60));
select pg_temp.m('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000312', 'name', 'Weekday',
  'start_min', 840, 'end_min', 1380, 'days', '[2,3,4,5,6]'::jsonb, 'break_min', 60));
select pg_temp.m('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000313', 'name', 'Sunday',
  'start_min', 660, 'end_min', 0, 'days', '[7]'::jsonb, 'break_min', 60));
select pg_temp.m('shift.assign', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000312',
  'shift_id', 'a5000000-0000-4000-8000-000000000311', 'effective_from', '2025-12-01'));
select pg_temp.m('shift.assign', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000313',
  'shift_id', s, 'effective_from', '2025-12-01'))
  from unnest(array['a5000000-0000-4000-8000-000000000312', 'a5000000-0000-4000-8000-000000000313']) s;
select is((pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000312',
    'effective_from', '2025-12-01', 'pay_type', 'monthly', 'base_paise', 1800000, 'extra_hours_paid', false)))->>'status',
  'applied', 'Ravi: ₹18,000 / month');
select pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000313',
  'effective_from', '2025-12-01', 'pay_type', 'monthly', 'base_paise', 2000000, 'extra_hours_paid', true));
select is((pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000313',
    'effective_from', '2026-01-16', 'pay_type', 'monthly', 'base_paise', 2200000, 'extra_hours_paid', true)))->>'status',
  'applied', 'Arjun: ₹20,000, raised to ₹22,000 from 16 Jan, extra hours paid');
select is((pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000313',
    'effective_from', '2026-01-16', 'pay_type', 'monthly', 'base_paise', 1, 'extra_hours_paid', true)))->>'error',
  'duplicate', 'one rate per date');
select is((pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000312',
    'effective_from', '2026-03-01', 'pay_type', 'weekly', 'base_paise', 1)))->>'error', 'invalid_rate', 'a known pay type');
select is((pg_temp.m('pay_policy.add', jsonb_build_object('id', gen_random_uuid(), 'effective_from', '2026-03-01',
    'policy', '{"extra_multiplier": 9}'::jsonb)))->>'error', 'invalid_pay_policy', 'pay rules are validated');

-- Example 1 — Ravi, January: 22 present (4 late), 1 half day, 1 absent, 1 paid + 1 LOP leave day.
select pg_temp.work('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312',
         d::date || case when extract(day from d) in (5, 6, 9, 10) then ' 11:20' else ' 11:00' end,
         d::date || case when extract(day from d) = 7 then ' 15:00' else ' 20:00' end)
  from generate_series('2026-01-01'::date, '2026-01-31', interval '1 day') d
 where extract(isodow from d) <> 7 and extract(day from d) not in (2, 8, 12, 13);
select pg_temp.leave('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', '2026-01-12', 1);
select pg_temp.leave('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', '2026-01-13', 0);

-- Example 3 — Arjun, January: 8 h Tue–Sat, 12 h Sundays, worked the 2nd (holiday), paid leave
-- the 8th, LOP the 22nd, Mondays off.
select pg_temp.work('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313',
         d::date || case when extract(isodow from d) = 7 then ' 11:00' else ' 14:00' end,
         case when extract(isodow from d) = 7 then (d::date + 1) || ' 00:00' else d::date || ' 23:00' end)
  from generate_series('2026-01-01'::date, '2026-01-31', interval '1 day') d
 where extract(isodow from d) <> 1 and extract(day from d) not in (8, 22);
select pg_temp.leave('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313', '2026-01-08', 1);
select pg_temp.leave('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313', '2026-01-22', 0);

-- ------------------------------------------------ the January run
select pg_temp.as_user(2);
select is((pg_temp.m('salary_run.create', jsonb_build_object('id', gen_random_uuid(),
    'period_start', '2026-01-01', 'period_end', '2026-01-31')))->>'error', 'forbidden', 'staff cannot run salary');
select pg_temp.as_user(5);
select is((pg_temp.m('salary_run.create', jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000311',
    'period_start', '2026-01-01', 'period_end', '2026-03-31')))->>'error', 'invalid_period', 'at most 62 days');
create temp table run1 as select pg_temp.m('salary_run.create', jsonb_build_object(
  'id', 'b1000000-0000-4000-8000-000000000310', 'period_start', '2026-01-01', 'period_end', '2026-01-31')) as r;
select is((select r->'result'->>'staff_count' from run1), '2', 'payroll creates the run: Ravi and Arjun (Bob has no rate)');

-- Example 1, to the paisa.
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312')).day_counts
            - 'early' - 'week_off',
  '{"scheduled": 26, "present": 22.5, "late": 4, "half_day": 1, "absent": 1, "paid_leave": 1, "lop_leave": 1, "holiday": 1}'::jsonb,
  'Ravi: 26 scheduled, 22 present + half a day, 1 absent, 1 paid + 1 LOP, the holiday');
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312')).base_paise,
  1800000::bigint, 'base ₹18,000.00');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', 'absent')->>'amount_paise')::bigint,
  58065::bigint, 'absent: 1 × 1,800,000 / 31 = 58,064.52 → 58,065');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', 'lop_leave')->>'amount_paise')::bigint,
  58065::bigint, 'LOP: 58,065');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', 'half_day')->>'amount_paise')::bigint,
  29032::bigint, 'half day: 0.5 × 58,064.52 → 29,032');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', 'late')->>'amount_paise')::bigint,
  29032::bigint, 'late marks (4 late + 1 early leave = 5 → one half day): 29,032');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', 'late')->>'applied')::boolean,
  true, 'every suggestion starts kept');
select pg_temp.m('salary_adjustment.add', jsonb_build_object('id', gen_random_uuid(), 'run_id', 'b1000000-0000-4000-8000-000000000310',
  'staff_id', '5f000000-0000-4000-8000-000000000312', 'kind', 'advance', 'amount_paise', 200000, 'note', 'Advance on 10 Jan'));
select pg_temp.m('salary_adjustment.add', jsonb_build_object('id', gen_random_uuid(), 'run_id', 'b1000000-0000-4000-8000-000000000310',
  'staff_id', '5f000000-0000-4000-8000-000000000312', 'kind', 'bonus', 'amount_paise', 50000, 'note', 'Festival bonus'));
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312')).net_paise,
  1475806::bigint, 'Example 1 net: ₹14,758.06');
select is((pg_temp.m('salary_adjustment.add', jsonb_build_object('id', gen_random_uuid(), 'run_id', 'b1000000-0000-4000-8000-000000000310',
    'staff_id', '5f000000-0000-4000-8000-000000000312', 'kind', 'bonus', 'amount_paise', 100, 'note', ' ')))->>'error',
  'note_required', 'an adjustment needs a note');

-- The owner waives the late deduction: kept through a recalculation.
select is((pg_temp.m('salary_run.set_deduction', jsonb_build_object('run_id', 'b1000000-0000-4000-8000-000000000310',
    'staff_id', '5f000000-0000-4000-8000-000000000312', 'code', 'late', 'applied', false,
    'note', 'Bus strike that week')))->'result'->>'net_paise', '1504838', 'waiving the late deduction: ₹15,048.38');
select is((pg_temp.m('salary_run.recalculate', jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000310')))->>'status',
  'applied', 'recalculate');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312', 'late')
            - 'label' - 'rate_paise' - 'units'),
  '{"code": "late", "amount_paise": 29032, "applied": false, "note": "Bus strike that week"}'::jsonb,
  'the waiver and its note survive the rebuild');
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312')).net_paise,
  1504838::bigint, 'so does the net');

-- Example 3, to the paisa.
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313')).base_paise,
  2103226::bigint, 'Arjun base: (2,000,000 × 15 + 2,200,000 × 16) / 31 → 2,103,226');
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313')).extra_min,
  1440, '24 h extra: 8 h on the holiday + 4 × 4 h on 12 h Sundays');
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313')).extra_paise,
  300000::bigint, 'extra hours at the derived rate × 1.5: ₹3,000.00');
select is((pg_temp.ded('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313', 'lop_leave')->>'amount_paise')::bigint,
  70968::bigint, 'LOP on the 22nd at the raised rate: 70,968');
select is((select jsonb_array_length(rates) from salary_run_lines where run_id = 'b1000000-0000-4000-8000-000000000310'
            and staff_id = '5f000000-0000-4000-8000-000000000313'), 2, 'both rates are shown');
select pg_temp.m('salary_adjustment.add', jsonb_build_object('id', gen_random_uuid(), 'run_id', 'b1000000-0000-4000-8000-000000000310',
  'staff_id', '5f000000-0000-4000-8000-000000000313', 'kind', 'deduction', 'amount_paise', 30000, 'note', 'Cracked controller, 20 Jan'));
select is((pg_temp.line('b1000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000313')).net_paise,
  2302258::bigint, 'Example 3 net: ₹23,022.58');

-- A mistaken bonus, reversed (append-only).
create temp table oops as select gen_random_uuid() as id;
select pg_temp.m('salary_adjustment.add', jsonb_build_object('id', (select id from oops), 'run_id', 'b1000000-0000-4000-8000-000000000310',
  'staff_id', '5f000000-0000-4000-8000-000000000313', 'kind', 'bonus', 'amount_paise', 99900, 'note', 'typo'));
select is((pg_temp.m('salary_adjustment.reverse', jsonb_build_object('id', gen_random_uuid(),
    'reverses_id', (select id from oops), 'note', 'Entered by mistake')))->'result'->>'net_paise', '2302258',
  'reversing it restores the net');
select is((pg_temp.m('salary_adjustment.reverse', jsonb_build_object('id', gen_random_uuid(),
    'reverses_id', (select id from oops), 'note', 'again')))->>'error', 'already_reversed', 'only once');
select is((select count(*)::int from salary_adjustments where run_id = 'b1000000-0000-4000-8000-000000000310'
            and staff_id = '5f000000-0000-4000-8000-000000000313'), 3, 'nothing is deleted');

-- ------------------------------------------------ finalise and its locks
select is((pg_temp.m('salary_run.finalise', jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000310')))->>'error',
  'forbidden', 'payroll alone cannot finalise');
select pg_temp.as_user(1);
select is((pg_temp.m('salary_run.finalise', jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000310')))->'result'->>'net_paise',
  (1504838 + 2302258)::text, 'the owner finalises: total net');
select is((select status from salary_runs where id = 'b1000000-0000-4000-8000-000000000310'), 'finalised', 'locked');
select is((pg_temp.m('salary_run.set_deduction', jsonb_build_object('run_id', 'b1000000-0000-4000-8000-000000000310',
    'staff_id', '5f000000-0000-4000-8000-000000000312', 'code', 'late', 'applied', true)))->>'error', 'run_not_draft',
  'a finalised run does not change');
select is((pg_temp.m('attendance.correct', jsonb_build_object('action', 'add', 'staff_id', '5f000000-0000-4000-8000-000000000312',
    'in_at', pg_temp.ist('2026-01-08 11:00'), 'out_at', pg_temp.ist('2026-01-08 20:00'), 'reason', 'late fix')))->>'error',
  'period_finalised', 'attendance in a finalised period cannot be corrected');
select is((pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000312',
    'effective_from', '2026-01-20', 'pay_type', 'monthly', 'base_paise', 1900000)))->>'error', 'rate_in_finalised_period',
  'no pay change inside a finalised period');
select is((pg_temp.m('salary_run.create', jsonb_build_object('id', gen_random_uuid(), 'period_start', '2026-01-25',
    'period_end', '2026-02-24')))->>'error', 'run_overlap', 'runs do not overlap');
create temp table run2 as select gen_random_uuid() as id;
select pg_temp.m('salary_run.create', jsonb_build_object('id', (select id from run2), 'period_start', '2026-02-01',
  'period_end', '2026-02-28'));
select is((pg_temp.m('salary_run.discard', jsonb_build_object('id', (select id from run2))))->>'status', 'applied',
  'a draft is discarded');
select is((pg_temp.m('salary_run.create', jsonb_build_object('id', gen_random_uuid(), 'period_start', '2026-02-01',
    'period_end', '2026-02-28')))->>'status', 'applied', 'and its period is free again');

-- ------------------------------------------------ nobody changes their own pay (S7), owners may
select pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000315',
  'effective_from', '2026-03-01', 'pay_type', 'monthly', 'base_paise', 2000000, 'extra_hours_paid', false));
create temp table run4 as select gen_random_uuid() as id;
select pg_temp.m('salary_run.create', jsonb_build_object('id', (select id from run4), 'period_start', '2026-03-01',
  'period_end', '2026-03-31'));
create temp table adj4 as select gen_random_uuid() as id;
select pg_temp.m('salary_adjustment.add', jsonb_build_object('id', (select id from adj4), 'run_id', (select id from run4),
  'staff_id', '5f000000-0000-4000-8000-000000000315', 'kind', 'deduction', 'amount_paise', 50000, 'note', 'Breakage'));
select is((pg_temp.m('hr_profile.save', jsonb_build_object('staff_id', '5f000000-0000-4000-8000-000000000311',
    'employee_code', 'OWN-1')))->>'status', 'applied', 'role owner may edit their own HR profile');
select pg_temp.as_user(5);
select is((pg_temp.m('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000315',
    'effective_from', '2026-03-15', 'pay_type', 'monthly', 'base_paise', 9000000, 'extra_hours_paid', false)))->>'error',
  'own_record', 'a payroll holder cannot set their own pay rate');
select is((pg_temp.m('hr_profile.save', jsonb_build_object('staff_id', '5f000000-0000-4000-8000-000000000315',
    'paid_leave_days', 60)))->>'error', 'own_record', 'nor their own HR profile');
select is((pg_temp.m('salary_run.set_deduction', jsonb_build_object('run_id', (select id from run4),
    'staff_id', '5f000000-0000-4000-8000-000000000315', 'code', 'absent', 'applied', false)))->>'error', 'own_record',
  'nor waive their own deductions');
select is((pg_temp.m('salary_adjustment.add', jsonb_build_object('id', gen_random_uuid(), 'run_id', (select id from run4),
    'staff_id', '5f000000-0000-4000-8000-000000000315', 'kind', 'bonus', 'amount_paise', 100000, 'note', 'Me')))->>'error',
  'own_record', 'nor give themselves a bonus');
select is((pg_temp.m('salary_adjustment.reverse', jsonb_build_object('id', gen_random_uuid(), 'reverses_id', (select id from adj4),
    'note', 'Undo')))->>'error', 'own_record', 'nor reverse a deduction on their own line');
select is((select count(*)::int from salary_adjustments where run_id = (select id from run4)), 1, 'nothing was written');
select pg_temp.as_user(1);

-- ------------------------------------------------ finalise only a period that is over and reviewed
create temp table run5 as select gen_random_uuid() as id;
select pg_temp.m('salary_run.create', jsonb_build_object('id', (select id from run5),
  'period_start', (_pr_ist_date(now()) - 5)::text, 'period_end', (_pr_ist_date(now()) + 3)::text));
select is((pg_temp.m('salary_run.finalise', jsonb_build_object('id', (select id from run5))))->>'error',
  'period_not_over', 'a period that ends after today cannot be finalised');
select is((select status from salary_runs where id = (select id from run5)), 'draft', 'it stays a draft');
select pg_temp.m('salary_run.discard', jsonb_build_object('id', (select id from run5)));
create temp table run6 as select gen_random_uuid() as id;
select pg_temp.m('salary_run.create', jsonb_build_object('id', (select id from run6),
  'period_start', (_pr_ist_date(now()) - 10)::text, 'period_end', (_pr_ist_date(now()) - 1)::text));
select pg_temp.work('e0000000-0000-4000-8000-000000000310', '5f000000-0000-4000-8000-000000000312',
  (_pr_ist_date(now()) - 3)::text || ' 10:00', (_pr_ist_date(now()) - 3)::text || ' 19:00');
update attendance_entries set review = 'pending'
 where staff_id = '5f000000-0000-4000-8000-000000000312' and work_date = _pr_ist_date(now()) - 3;
select is((pg_temp.m('salary_run.finalise', jsonb_build_object('id', (select id from run6))))->>'detail',
  'Ravi', 'an entry still flagged for review blocks finalise, naming the person');
update attendance_entries set review = 'accepted'
 where staff_id = '5f000000-0000-4000-8000-000000000312' and work_date = _pr_ist_date(now()) - 3;
select is((pg_temp.m('salary_run.finalise', jsonb_build_object('id', (select id from run6))))->>'status',
  'applied', 'once reviewed, a period that ended yesterday finalises');

-- ------------------------------------------------ a login with pay records cannot be deleted
select throws_ok($$ delete from staff_profiles where id = '5f000000-0000-4000-8000-000000000312' $$,
  '23503', null, 'deleting a profile with salary lines is refused (deactivate instead)');

-- ------------------------------------------------ Example 2: weekly, hourly, nearest 15 min
select pg_temp.as_user(6);
select pg_temp.w('settings.save', jsonb_build_object('key', 'work_hours', 'json',
  _work_hours('e0000000-0000-4000-8000-000000000311') || '{"rounding": "nearest_15"}'));
select pg_temp.w('pay_policy.add', jsonb_build_object('id', gen_random_uuid(), 'effective_from', '2025-12-01',
  'policy', _pay_policy('e0000000-0000-4000-8000-000000000311', '2025-12-01')
            || '{"period_kind": "weekly", "extra_multiplier": 1.5}'));
select pg_temp.w('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000314', 'name', 'Eve',
  'start_min', 960, 'end_min', 1320, 'days', '[1,2,4,5,6,7]'::jsonb, 'break_min', 30));
select pg_temp.w('shift.assign', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000317',
  'shift_id', 'a5000000-0000-4000-8000-000000000314', 'effective_from', '2025-12-01'));
select pg_temp.w('pay_rate.add', jsonb_build_object('id', gen_random_uuid(), 'staff_id', '5f000000-0000-4000-8000-000000000317',
  'effective_from', '2025-12-01', 'pay_type', 'hourly', 'base_paise', 12000, 'extra_hours_paid', true));
select pg_temp.work('e0000000-0000-4000-8000-000000000311', '5f000000-0000-4000-8000-000000000317', i, o, s)
  from (values ('2026-01-05 16:02', '2026-01-05 22:10', 'punch'), ('2026-01-06 15:55', '2026-01-06 21:48', 'punch'),
               ('2026-01-08 12:00', '2026-01-08 14:00', 'punch'), ('2026-01-08 17:00', '2026-01-08 22:20', 'punch'),
               ('2026-01-09 16:00', '2026-01-10 02:10', 'punch'), ('2026-01-10 16:05', '2026-01-10 22:00', 'auto'),
               ('2026-01-11 16:00', '2026-01-11 22:00', 'punch')) v(i, o, s);
create temp table run3 as select gen_random_uuid() as id;
select pg_temp.w('salary_run.create', jsonb_build_object('id', (select id from run3), 'period_start', '2026-01-05',
  'period_end', '2026-01-11'));
select is((select array[regular_min, extra_min] from salary_run_lines where run_id = (select id from run3)),
  array[2250, 105], 'Priya: 37.5 h regular, 1 h 45 extra (Friday past 8 h)');
select is((select array[base_paise, extra_paise, deductions_paise, net_paise] from salary_run_lines where run_id = (select id from run3)),
  array[450000, 31500, 0, 481500]::bigint[], 'Example 2: ₹4,500 + ₹315 (× 1.5) = ₹4,815.00; no late rule for hourly staff');
select pg_temp.w('salary_adjustment.add', jsonb_build_object('id', gen_random_uuid(), 'run_id', (select id from run3),
  'staff_id', '5f000000-0000-4000-8000-000000000317', 'kind', 'advance', 'amount_paise', 600000, 'note', 'Big advance'));
select is((pg_temp.w('salary_run.finalise', jsonb_build_object('id', (select id from run3))))->>'error', 'net_negative',
  'a negative net cannot be finalised');

-- ------------------------------------------------ who reads pay
set local role authenticated;
select pg_temp.as_user(2);
select is((select count(*)::int from staff_pay_rates) + (select count(*)::int from salary_runs)
          + (select count(*)::int from salary_run_lines) + (select count(*)::int from salary_adjustments)
          + (select count(*)::int from pay_policies), 0, 'staff read no pay at all, not even their own');
select pg_temp.as_user(5);
select is((select count(*)::int from salary_run_lines where run_id = 'b1000000-0000-4000-8000-000000000310'), 2,
  'payroll reads the lines');
select is((select count(*)::int from salary_run_lines where arena_id = 'e0000000-0000-4000-8000-000000000311'), 0,
  'of its own arena only');
reset role;

select * from finish();
rollback;
