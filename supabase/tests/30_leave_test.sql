-- Leave: requests (planned / unplanned, half days, working days only, overlaps, backdating),
-- the approver's paid / LOP split pinned to dates, cancellation (pending at once, approved by
-- approval), balance adjustments, leave years from the joining date, the own-record rule, the
-- finalised-period lock, the attendance day on leave, and who reads what. Dates are relative to
-- today (planned leave cannot start in the past).
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000300'::uuid, 'pgtap 30');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('30000000-0000-4000-8000-000000000001', 'owner30@test.local'),
      ('30000000-0000-4000-8000-000000000002', 'ravi30@test.local'),
      ('30000000-0000-4000-8000-000000000003', 'meera30@test.local'),
      ('30000000-0000-4000-8000-000000000004', 'asha30@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(id, arena_id, user_id, name, role, perms, active, created_at) values
  ('5f000000-0000-4000-8000-000000000301', 'e0000000-0000-4000-8000-000000000300',
    '30000000-0000-4000-8000-000000000001', 'Owner', 'owner', _known_perms(), true, '2024-01-01'),
  ('5f000000-0000-4000-8000-000000000302', 'e0000000-0000-4000-8000-000000000300',
    '30000000-0000-4000-8000-000000000002', 'Ravi', 'staff', array['start'], true, '2024-01-01'),
  ('5f000000-0000-4000-8000-000000000303', 'e0000000-0000-4000-8000-000000000300',
    '30000000-0000-4000-8000-000000000003', 'Meera', 'staff', array['start','leave_approve'], true, '2024-01-01'),
  ('5f000000-0000-4000-8000-000000000304', 'e0000000-0000-4000-8000-000000000300',
    '30000000-0000-4000-8000-000000000004', 'Asha', 'staff', array['start'], true, '2024-01-01');

create function pg_temp.as_user(p_n int) returns void as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub',
    '30000000-0000-4000-8000-00000000000' || p_n, 'role', 'authenticated')::text, true) $$
  language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000300'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
-- Today (IST) and the next Monday at least a week away (a whole Mon–Sat week ahead).
create temp table t as select _pr_ist_date(now()) as today,
  _pr_ist_date(now()) + (8 - extract(isodow from _pr_ist_date(now()))::int) + 7 as mon;
create function pg_temp.d(p_offset int) returns text as $$ select ((select mon from t) + p_offset)::text $$ language sql;
create function pg_temp.ask(p_id text, p_from text, p_to text, p_kind text default 'planned',
    p_half text default 'none') returns jsonb as $$
  select pg_temp.push('leave.request', jsonb_build_object('id', p_id, 'kind', p_kind,
    'from_date', p_from, 'to_date', p_to, 'half_day', p_half, 'reason', 'family function')) $$ language sql;
create function pg_temp.bal(p_staff text) returns jsonb as $$
  select _leave_balance(p_staff::uuid, (select today from t)) $$ language sql;

-- Mon–Sat 10:00–19:00; Sunday is everyone's week off.
select pg_temp.as_user(1);
select pg_temp.push('shift.upsert', jsonb_build_object('id', 'a5000000-0000-4000-8000-000000000301', 'name', 'Day',
  'start_min', 600, 'end_min', 1140, 'days', '[1,2,3,4,5,6]'::jsonb, 'break_min', 60));
select pg_temp.push('shift.assign', jsonb_build_object('id', gen_random_uuid(), 'staff_id', s,
  'shift_id', 'a5000000-0000-4000-8000-000000000301', 'effective_from', '2024-01-01'))
  from unnest(array['5f000000-0000-4000-8000-000000000302', '5f000000-0000-4000-8000-000000000303',
                    '5f000000-0000-4000-8000-000000000304']) s;
select is((pg_temp.push('hr_profile.save', jsonb_build_object('staff_id', '5f000000-0000-4000-8000-000000000302',
    'joined_on', ((select today from t) - 400)::text)))->>'status', 'applied', 'Ravi joined 400 days ago');

-- ------------------------------------------------ 1. leave years from the joining date
select is((select (bal->>'year_start')::date from (select pg_temp.bal('5f000000-0000-4000-8000-000000000302') as bal) b),
  ((select today from t) - 400 + interval '1 year')::date, 'the current leave year started on the anniversary');
select is((pg_temp.bal('5f000000-0000-4000-8000-000000000302')->>'allowance')::numeric, 12::numeric,
  'the arena''s 12 days');
select pg_temp.push('hr_profile.save', jsonb_build_object('staff_id', '5f000000-0000-4000-8000-000000000304',
  'joined_on', '2024-02-29', 'paid_leave_days', 15));
select is(_leave_year_start('5f000000-0000-4000-8000-000000000304', '2026-03-01'), '2026-02-28'::date,
  'a 29 Feb joiner''s year starts 28 Feb');
select is(_leave_year_start('5f000000-0000-4000-8000-000000000304', '2026-02-27'), '2025-02-28'::date,
  'and the day before belongs to the year before');
select is((pg_temp.bal('5f000000-0000-4000-8000-000000000304')->>'allowance')::numeric, 15::numeric,
  'a per-person allowance overrides the arena''s');

-- ------------------------------------------------ 2. requests
select pg_temp.as_user(2);
select is((pg_temp.push('leave.request', jsonb_build_object('id', gen_random_uuid(), 'kind', 'planned',
    'from_date', pg_temp.d(0), 'to_date', pg_temp.d(0), 'half_day', 'none', 'reason', ' ')))->>'error',
  'reason_required', 'a reason is required');
select is((pg_temp.ask(gen_random_uuid()::text, ((select today from t) - 1)::text, ((select today from t) - 1)::text))->>'error',
  'planned_in_past', 'planned leave cannot start in the past');
select is((pg_temp.ask(gen_random_uuid()::text, ((select today from t) - 10)::text, ((select today from t) - 10)::text,
    'unplanned'))->>'error', 'too_far_back', 'unplanned leave goes back at most 7 days');
select is((pg_temp.ask(gen_random_uuid()::text, pg_temp.d(0), pg_temp.d(1), 'planned', 'first_half'))->>'error',
  'half_day_not_allowed', 'a half day is one day only');
select is((pg_temp.ask(gen_random_uuid()::text, pg_temp.d(-1), pg_temp.d(-1)))->>'error', 'no_working_days',
  'a Sunday alone is not leave');
create temp table r1 as select pg_temp.ask('1e000000-0000-4000-8000-000000000301', pg_temp.d(-2), pg_temp.d(2)) as r;
select is((select r->'result'->>'days' from r1), '4.0', 'Sat–Wed is 4 working days (the Sunday is not leave)');
select is((pg_temp.ask(gen_random_uuid()::text, pg_temp.d(2), pg_temp.d(3)))->>'error', 'leave_overlap',
  'overlapping your own request is refused');
select is((pg_temp.bal('5f000000-0000-4000-8000-000000000302')->>'pending')::numeric, 4::numeric,
  'pending days show in the balance');

-- ------------------------------------------------ 3. decisions
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000301',
    'approve', true)))->>'error', 'forbidden', 'staff cannot approve leave');
select pg_temp.as_user(3);
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000301',
    'approve', true, 'paid_days', 1.3)))->>'error', 'invalid_paid_days', 'paid days in halves');
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000301',
    'approve', true, 'paid_days', 5)))->>'error', 'invalid_paid_days', 'not more than the request');
create temp table dec1 as select pg_temp.push('leave.decide', jsonb_build_object('id',
  '1e000000-0000-4000-8000-000000000301', 'approve', true, 'note', 'enjoy')) as r;
select is((select r->'result' from dec1), '{"status":"approved","paid_days":4.0,"lop_days":0.0}'::jsonb,
  'approved, all paid from the balance by default');
select is((select jsonb_array_length(day_split) from leave_requests where id = '1e000000-0000-4000-8000-000000000301'),
  4, 'pinned to its 4 working days');
select is((pg_temp.bal('5f000000-0000-4000-8000-000000000302')->>'balance')::numeric, 8::numeric, '12 − 4 = 8 left');
select is(_att_day('5f000000-0000-4000-8000-000000000302', pg_temp.d(0)::date, now())->>'status', 'on_leave',
  'the day reads as on leave');
select is(_att_day('5f000000-0000-4000-8000-000000000302', pg_temp.d(-1)::date, now())->>'status', 'week_off',
  'the Sunday inside it stays a week off');

-- More than the balance: the approver splits paid and LOP (the default fills the balance).
select pg_temp.as_user(3);
select is((pg_temp.push('leave.adjust', jsonb_build_object('staff_id', '5f000000-0000-4000-8000-000000000302',
    'days', -7, 'reason', 'Took 7 days before the app')))->>'status', 'applied', 'an opening balance correction');
select pg_temp.as_user(2);
select pg_temp.ask('1e000000-0000-4000-8000-000000000302', pg_temp.d(7), pg_temp.d(8));
select pg_temp.as_user(3);
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000302',
    'approve', true)))->'result', '{"status":"approved","paid_days":1.0,"lop_days":1.0}'::jsonb,
  'with 1 day left: 1 paid, 1 LOP');
select is((select array[(day_split->0->>'paid_units')::numeric, (day_split->1->>'paid_units')::numeric]
            from leave_requests where id = '1e000000-0000-4000-8000-000000000302'),
  array[1.0, 0]::numeric[], 'the paid day is the earliest one');
select is((select array[(x->>'leave_paid')::numeric, (x->>'leave_lop')::numeric]
            from (select _att_day('5f000000-0000-4000-8000-000000000302', pg_temp.d(8)::date, now()) as x) q),
  array[0, 1]::numeric[], 'the attendance day carries the LOP');

-- Half day; reject; own record.
select pg_temp.as_user(4);
select pg_temp.ask('1e000000-0000-4000-8000-000000000303', pg_temp.d(10), pg_temp.d(10), 'planned', 'second_half');
select is((select days from leave_requests where id = '1e000000-0000-4000-8000-000000000303'), 0.5::numeric(4,1),
  'a half day counts 0.5');
select pg_temp.as_user(3);
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000303',
    'approve', false, 'note', 'busy weekend')))->'result'->>'status', 'rejected', 'rejected');
select pg_temp.ask('1e000000-0000-4000-8000-000000000304', pg_temp.d(14), pg_temp.d(14));
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000304',
    'approve', true)))->>'error', 'own_record', 'an approver cannot approve their own leave');
select pg_temp.as_user(1);
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000304',
    'approve', true)))->'result'->>'status', 'approved', 'the owner can');

-- ------------------------------------------------ 4. cancelling
select pg_temp.as_user(2);
select pg_temp.ask('1e000000-0000-4000-8000-000000000305', pg_temp.d(21), pg_temp.d(21));
select is((pg_temp.push('leave.cancel', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000305')))->'result'->>'status',
  'cancelled', 'a pending request is cancelled at once');
select is((pg_temp.push('leave.cancel', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000301',
    'reason', 'trip off')))->'result'->>'status', 'cancel_pending', 'approved leave waits for approval to cancel');
select is((pg_temp.bal('5f000000-0000-4000-8000-000000000302')->>'used')::numeric, 5::numeric,
  'still counted while the cancellation waits');
select is((pg_temp.push('leave.cancel', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000304')))->>'error',
  'not_found', 'nobody cancels someone else''s leave');
select pg_temp.as_user(3);
select is((pg_temp.push('leave.decide', jsonb_build_object('id', '1e000000-0000-4000-8000-000000000301',
    'approve', true)))->'result'->>'status', 'cancelled', 'the cancellation is approved');
select is((pg_temp.bal('5f000000-0000-4000-8000-000000000302')->>'used')::numeric, 1::numeric,
  'and the days come back');
select is(_att_day('5f000000-0000-4000-8000-000000000302', pg_temp.d(0)::date, now())->>'status', 'upcoming',
  'the day is a normal working day again');

-- ------------------------------------------------ 5. a finalised period is locked
insert into salary_runs(id, arena_id, period_start, period_end, status, rules_snapshot, computed_at,
    created_by, finalised_by, finalised_at)
  values (gen_random_uuid(), 'e0000000-0000-4000-8000-000000000300', (select today from t) - 30,
    (select today from t) - 2, 'finalised', '{}', now(), '30000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001', now());
select pg_temp.as_user(2);
select is((pg_temp.ask(gen_random_uuid()::text, ((select today from t) - 3)::text, ((select today from t) - 3)::text,
    'unplanned'))->>'error', 'period_finalised', 'no leave inside a finalised salary period');

-- ------------------------------------------------ 6. who reads what
set local role authenticated;
select pg_temp.as_user(2);
select is((select count(distinct staff_id)::int from leave_requests where arena_id = 'e0000000-0000-4000-8000-000000000300'),
  1, 'staff see only their own requests');
select is(jsonb_array_length(leave_balances('e0000000-0000-4000-8000-000000000300',
    '5f000000-0000-4000-8000-000000000302')), 1, 'and their own balance');
select throws_ok($$ select leave_balances('e0000000-0000-4000-8000-000000000300') $$, '42501', 'forbidden',
  'not everyone''s');
select pg_temp.as_user(3);
select is((select count(distinct staff_id)::int from leave_requests where arena_id = 'e0000000-0000-4000-8000-000000000300'),
  3, 'an approver sees every request');
select is(jsonb_array_length(leave_balances('e0000000-0000-4000-8000-000000000300')), 4,
  'and every balance');
reset role;

select * from finish();
rollback;
