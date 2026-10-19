-- Day/time pricing rules (pricing_rules, _pr_rule, _pr_rule_price, rule.* ops).
--
-- Seed list: PS5 standard 1 pad ₹150/h, POOL ₹275/h,
-- per-minute billing, cash rounded to ₹1. Sat 2026-10-03 IST; 19:00 IST = 13:30Z.
-- A rule is judged at the session START and then prices the whole session;
-- the first active match by priority wins; an arena without rules prices and
-- snapshots exactly as before.
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000124'::uuid, 'pgtap 24');
-- These fixtures replay fixed past dates: widen the offline window (offline_rules, default
-- 24 h) so device-stamped times from then are accepted.
insert into settings(arena_id, key, json)
  select id, 'offline_rules', '{"max_offline_hours": 100000}' from arenas where name like 'pgtap%'
  on conflict (arena_id, key) do nothing;
select _seed_arena_catalog('e0000000-0000-4000-8000-000000000124'::uuid);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values
  ('00000000-0000-0000-0000-000000000000','24000000-0000-0000-0000-000000000001','authenticated',
   'authenticated','owner24@test.local','',now(),now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','24000000-0000-0000-0000-000000000002','authenticated',
   'authenticated','staff24@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000124'::uuid,'24000000-0000-0000-0000-000000000001','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true),
  ('e0000000-0000-4000-8000-000000000124'::uuid,'24000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill','discount','members'],true);

create function pg_temp.arena() returns uuid as $$ select 'e0000000-0000-4000-8000-000000000124'::uuid $$ language sql;
create function pg_temp.r(n text) returns uuid as $$ select id from resources where name = n and arena_id = 'e0000000-0000-4000-8000-000000000124'::uuid $$ language sql;
create function pg_temp.snap() returns jsonb as $$ select _pricing_snapshot(pg_temp.arena()) $$ language sql;
create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push(pg_temp.arena(),
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)), 'pgtap')
    -> 'results' -> 0 $$ language sql;
-- PS5 1 pad (or POOL) quoted on the current list, start and end in UTC.
create function pg_temp.q(p_s text, p_e text, p_act text default 'PS5') returns jsonb as $$
  select _pr_quote(pg_temp.snap(), p_act, case when p_act = 'PS5' then 1 end,
    p_s::timestamptz, p_e::timestamptz) $$ language sql;
create function pg_temp.rule(p_id text, p_name text, p_days int[], p_s int, p_e int, p_kind text,
    p_value int, p_extra jsonb default '{}') returns jsonb as $$
  select jsonb_build_object('id', p_id::uuid, 'name', p_name, 'days', to_jsonb(p_days),
    'start_min', p_s, 'end_min', p_e, 'adjust_kind', p_kind, 'adjust_value', p_value) || p_extra
  $$ language sql;

-- ===================== schema + grants
select has_table('public', 'pricing_rules', 'pricing_rules exists');
select ok(has_table_privilege('authenticated', 'public.pricing_rules', 'SELECT'),
  'authenticated may SELECT pricing_rules (filtered by RLS)');
select ok(not has_table_privilege(r, 'public.pricing_rules', p), r || ' has no ' || p)
from unnest(array['authenticated','anon']) as r,
     unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) as p;
select ok(exists (select 1 from _sync_sources() where name = 'pricing_rules'),
  'pricing_rules is in the change feed');

-- ===================== no rules: unchanged
select ok(not (pg_temp.snap() ? 'rules'), 'without rules the snapshot has no rules key');
select ok(not (_pricing_canon(pg_temp.snap()) ? 'rules'), '…and neither does its canon');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->>'amount')::int, 15000,
  'Sat 19:00 IST, 1 h of PS5 = ₹150 with no rule');

-- ===================== ops: permission and validation
select pg_temp.as_user('24000000-0000-0000-0000-000000000002');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000001',
    'Weekend evening', array[6,7], 1080, 1380, 'percent', 20))->>'error', 'forbidden',
  'staff without settings cannot add a rule');

select pg_temp.as_user('24000000-0000-0000-0000-000000000001');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000009',
    'Bad', array[6], 1200, 1080, 'percent', 20))->>'error', 'invalid_window', 'end before start is refused');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000009',
    'Bad', array[]::int[], 0, 60, 'percent', 20))->>'error', 'invalid_window', 'no days is refused');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000009',
    'Bad', array[6], 0, 60, 'percent', -101))->>'error', 'invalid_adjustment', 'below −100% is refused');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000009',
    'Bad', array[6], 0, 60, 'per_hour', 0))->>'error', 'invalid_adjustment', 'a zero change is refused');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000009',
    'Bad', array[6], 0, 60, 'percent', 10, '{"activity_codes":["NOPE"]}'))->>'error', 'unknown_type',
  'an unknown type code is refused');
select is((select count(*)::int from pricing_rules where arena_id = pg_temp.arena()), 0, 'nothing was saved');

-- ===================== a rule judged at the start prices the whole session
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000001',
    'Weekend evening', array[6,7], 1080, 1380, 'percent', 20))->>'status', 'applied',
  'owner adds Weekend evening +20% (Sat/Sun 18:00–23:00)');
select ok(pg_temp.snap() ? 'rules', 'the snapshot now carries the rule');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->>'amount')::int, 18000,
  'Sat 19:00, 1 h = ₹180');
select is(pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->'rule'->>'name', 'Weekend evening',
  'the quote names the rule');
select is((pg_temp.q('2026-10-03T12:00:00Z','2026-10-03T14:00:00Z')->>'amount')::int, 30000,
  'started 17:30 (before the window): the whole 2 h at ₹150, even past 18:00');
select is((pg_temp.q('2026-10-03T17:00:00Z','2026-10-03T19:00:00Z')->>'amount')::int, 36000,
  'started 22:30 (inside): the whole 2 h at ₹180, even past 23:00');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z','POOL')->>'amount')::int, 33000,
  'a rule for every type also prices POOL (₹275 → ₹330)');
select is((pg_temp.q('2026-10-02T13:30:00Z','2026-10-02T14:30:00Z')->>'amount')::int, 15000,
  'Friday 19:00 is not a rule day');

-- ===================== type scope, priority and reorder
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000002',
    'Pool Saturday', array[6], 0, 1440, 'per_hour', -5000, '{"activity_codes":["pool"]}'))->>'status',
  'applied', 'owner adds Pool Saturday −₹50/h (POOL only, goes last)');
select is((select activity_codes from pricing_rules where id = 'f2400000-0000-0000-0000-000000000002'),
  array['POOL'], 'type codes are stored upper-cased');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z','POOL')->>'amount')::int, 33000,
  'Weekend evening still wins for POOL (higher priority)');
select is(pg_temp.push('rule.reorder', jsonb_build_object('ids', jsonb_build_array(
    'f2400000-0000-0000-0000-000000000001')))->>'error', 'stale', 'a reorder missing a rule is stale');
select is(pg_temp.push('rule.reorder', jsonb_build_object('ids', jsonb_build_array(
    'f2400000-0000-0000-0000-000000000002','f2400000-0000-0000-0000-000000000001')))->>'status', 'applied',
  'Pool Saturday is moved first');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z','POOL')->>'amount')::int, 22500,
  'now POOL Sat 19:00 = ₹275 − ₹50');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->>'amount')::int, 18000,
  'PS5 is outside Pool Saturday''s scope, so Weekend evening still applies');

-- ===================== holidays and dates
select is(pg_temp.push('holiday.upsert', jsonb_build_object('day','2026-10-03','name','Festival'))->>'status',
  'applied', 'Sat 2026-10-03 becomes a holiday');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000001',
    'Weekend evening', array[6,7], 1080, 1380, 'percent', 20, '{"holiday_mode":"skip"}'))->>'status',
  'applied', 'Weekend evening is edited to skip holidays');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->>'amount')::int, 15000,
  'on the holiday Weekend evening does not apply');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000003',
    'Festival free', array[1,2,3,4,5,6,7], 0, 1440, 'percent', -100,
    '{"holiday_mode":"only","valid_from":"2026-10-01","valid_until":"2026-10-31"}'))->>'status',
  'applied', 'Festival free (−100%, holidays only, October)');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->>'amount')::int, 0,
  'a −100% rule takes the price to ₹0, never below');
select is((pg_temp.q('2026-10-04T13:30:00Z','2026-10-04T14:30:00Z')->>'amount')::int, 18000,
  'Sunday is not a holiday: Weekend evening applies again');
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000003',
    'Festival free', array[1,2,3,4,5,6,7], 0, 1440, 'percent', -100,
    '{"holiday_mode":"only","valid_from":"2026-11-01"}'))->>'status', 'applied',
  'Festival free now starts in November');
select is((pg_temp.q('2026-10-03T13:30:00Z','2026-10-03T14:30:00Z')->>'amount')::int, 15000,
  'outside its dates it does not apply');

-- ===================== disabled rules leave the snapshot
select is(pg_temp.push('rule.upsert', pg_temp.rule('f2400000-0000-0000-0000-000000000003',
    'Festival free', array[1,2,3,4,5,6,7], 0, 1440, 'percent', -100,
    '{"holiday_mode":"only","active":false}'))->>'status', 'applied', 'Festival free is disabled');
select is(jsonb_array_length(pg_temp.snap()->'rules'), 2, 'a disabled rule is not in the snapshot');
select is(pg_temp.push('holiday.delete', jsonb_build_object('day','2026-10-03'))->>'status', 'applied',
  'the holiday is removed');

-- ===================== a real session is billed with the rule, and history keeps old lists
select pg_temp.as_user('24000000-0000-0000-0000-000000000002');
select is(pg_temp.push('customer.create', jsonb_build_object(
    'id','cccccccc-0000-0000-0000-000000000024','name','Ravi','phone','9800002424',
    'is_guest', false))->>'status', 'applied', 'staff creates a customer');
select is(pg_temp.push('session.start', jsonb_build_object(
    'id','a2400000-0000-0000-0000-000000000001','segment_id','b2400000-0000-0000-0000-000000000001',
    'customer_id','cccccccc-0000-0000-0000-000000000024',
    'started_at','2026-10-03T13:30:00Z','scheduled_end_at','2026-10-03T14:30:00Z',
    'pricing_snapshot', pg_temp.snap(), 'resource_id', pg_temp.r('HEX'), 'activity_code','PS5',
    'controller_count', 1, 'allocations','[]'::jsonb, 'moves','[]'::jsonb))->>'status', 'applied',
  'HEX starts Sat 19:00 on the list with rules');
select is(pg_temp.push('session.end', jsonb_build_object(
    'session_id','a2400000-0000-0000-0000-000000000001','ended_at','2026-10-03T14:30:00Z',
    'billed_amount_paise', 15000, 'expected_segment_ids', '["b2400000-0000-0000-0000-000000000001"]'::jsonb,
    'expected_scheduled_end_at','2026-10-03T14:30:00Z',
    'charges', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(),
      'segment_id','b2400000-0000-0000-0000-000000000001','segment_index',0,'band_code','standard',
      'activity_code','PS5','resource_id',pg_temp.r('HEX'),'controller_count',1,
      'segment_start','2026-10-03T13:30:00Z','segment_end','2026-10-03T14:30:00Z',
      'played_minutes',60,'billed_minutes',60,'unit_minutes',60,'unit_price_paise',15000,
      'amount_paise',15000))))->>'error', 'price_mismatch', 'billing the base ₹150 is refused');
select is(pg_temp.push('session.end', jsonb_build_object(
    'session_id','a2400000-0000-0000-0000-000000000001','ended_at','2026-10-03T14:30:00Z',
    'billed_amount_paise', 18000, 'expected_segment_ids', '["b2400000-0000-0000-0000-000000000001"]'::jsonb,
    'expected_scheduled_end_at','2026-10-03T14:30:00Z',
    'charges', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(),
      'segment_id','b2400000-0000-0000-0000-000000000001','segment_index',0,'band_code','standard',
      'activity_code','PS5','resource_id',pg_temp.r('HEX'),'controller_count',1,
      'segment_start','2026-10-03T13:30:00Z','segment_end','2026-10-03T14:30:00Z',
      'played_minutes',60,'billed_minutes',60,'unit_minutes',60,'unit_price_paise',18000,
      'amount_paise',18000))))->>'status', 'applied', 'the rule-adjusted ₹180 bill is accepted');

select pg_temp.as_user('24000000-0000-0000-0000-000000000001');
select is(pg_temp.push('rule.delete', jsonb_build_object('id','f2400000-0000-0000-0000-000000000001'))->>'status',
  'applied', 'Weekend evening is deleted');
select ok(exists (select 1 from pricing_catalog_history where arena_id = pg_temp.arena()),
  'the replaced lists are kept so in-flight sessions still validate');
select is(pg_temp.push('rule.delete', jsonb_build_object('id','f2400000-0000-0000-0000-000000000001'))->>'status',
  'applied', 'deleting it again is a no-op');

-- ===================== per-hour rounding on a 30-minute unit (VR ₹200 / 30 min)
select is(_pr_rule_price(20000, 30, '{"adjust_kind":"per_hour","adjust_value":-3031}'::jsonb), 18485::bigint,
  '−₹30.31/h on a 30-min unit = −1515.5 → −1515 (half toward +∞)');
select is(_pr_rule_price(20000, 30, '{"adjust_kind":"per_hour","adjust_value":-3033}'::jsonb), 18484::bigint,
  '−₹30.33/h on a 30-min unit = −1516.5 → −1516');
select is(_pr_rule_price(15000, 60, '{"adjust_kind":"percent","adjust_value":-33}'::jsonb), 10050::bigint,
  '−33% of ₹150 = ₹100.50');
select is(_pr_rule_price(1000, 60, '{"adjust_kind":"per_hour","adjust_value":-5000}'::jsonb), 0::bigint,
  'a per-hour cut never goes below ₹0');

-- ===================== minute of day and tie-break order (floor app parity)
-- Thu 2026-10-01 (ISO 4), 14:00–17:00 IST = 08:30–11:30Z.
create function pg_temp.hh(p_extra jsonb default '[]') returns jsonb as $$
  select jsonb_build_object('rules', jsonb_build_array(jsonb_build_object('id',
    '24000000-0000-0000-0000-0000000000a1', 'name', 'Happy hours', 'priority', 0, 'days', '[4]'::jsonb,
    'start_min', 840, 'end_min', 1020, 'holiday_mode', 'any', 'activity_codes', '[]'::jsonb,
    'adjust_kind', 'percent', 'adjust_value', -20)) || p_extra) $$ language sql;
select ok(_pr_rule(pg_temp.hh(), 'PS5', '2026-10-01T08:29:59Z') is null,
  'a start at 13:59:59 IST is before a 14:00 rule (seconds are dropped, not rounded)');
select is(_pr_rule(pg_temp.hh(), 'PS5', '2026-10-01T08:30:00Z')->>'name', 'Happy hours',
  'a start at 14:00:00 IST is inside it');
select is(_pr_rule(pg_temp.hh(), 'PS5', '2026-10-01T11:29:59Z')->>'name', 'Happy hours',
  'a start at 16:59:59 IST is still inside a rule ending at 17:00');
select ok(_pr_rule(pg_temp.hh(), 'PS5', '2026-10-01T11:30:00Z') is null, 'a start at 17:00:00 IST is not');
select is(_pr_rule(pg_temp.hh(jsonb_build_array(jsonb_build_object('id',
    '24000000-0000-0000-0000-0000000000a2', 'name', 'Early', 'priority', 0, 'days', '[4]'::jsonb,
    'start_min', 840, 'end_min', 1020, 'holiday_mode', 'any', 'activity_codes', '[]'::jsonb,
    'adjust_kind', 'percent', 'adjust_value', -10))), 'PS5', '2026-10-01T09:00:00Z')->>'name', 'Early',
  'equal priority: names compare by code point (collate "C", like the floor app): Early before Happy');
select is(_pr_rule(pg_temp.hh(jsonb_build_array(jsonb_build_object('id',
    '24000000-0000-0000-0000-0000000000a2', 'name', 'happy hours', 'priority', 0, 'days', '[4]'::jsonb,
    'start_min', 840, 'end_min', 1020, 'holiday_mode', 'any', 'activity_codes', '[]'::jsonb,
    'adjust_kind', 'percent', 'adjust_value', -10))), 'PS5', '2026-10-01T09:00:00Z')->>'name', 'Happy hours',
  'upper case sorts before lower case (code point order, not the database locale)');

select * from finish();
rollback;
