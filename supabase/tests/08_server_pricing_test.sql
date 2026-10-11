-- Server-side pricing (0013): the server re-prices every bill and refuses money
-- that is not its own, and refuses a session frozen on a price list the arena
-- never had.
--
-- Seed price list (Thu 2026-10-01; happy hour 14:00–17:00 IST = 08:30–11:30Z):
--   PS5 standard 1/2 pads ₹150/₹280 per hour, happy ₹120/₹220. Per-minute
--   billing, session rounding scope, cash rounded to the nearest ₹1.
-- The parity of every rule with lib/domain/pricing is proven separately by a
-- Dart-vs-SQL differential run (docs/SYNC.md); these cases pin the op wiring.
begin;
create extension if not exists pgtap;
select * from no_plan();

-- ---------------------------------------------------------------- fixture
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values
  ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated',
   'authenticated','owner@test.local','',now(),now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated',
   'authenticated','staff@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ((select id from arenas limit 1),'11111111-1111-1111-1111-111111111111','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true),
  ((select id from arenas limit 1),'22222222-2222-2222-2222-222222222222','Staff','staff',
    array['start','bill','discount','members'],true);

create function pg_temp.arena() returns uuid as $$ select id from arenas limit 1 $$ language sql;
create function pg_temp.r(n text) returns uuid as $$ select id from resources where name = n $$ language sql;
create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push(pg_temp.arena(),
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)), 'pgtap')
    -> 'results' -> 0 $$ language sql;
-- The price list as an in-sync device would freeze it.
create function pg_temp.snap() returns jsonb as $$ select _pricing_snapshot(pg_temp.arena()) $$ language sql;
create function pg_temp.start(p_id text, p_seg text, p_res text, p_cc int, p_at text, p_end text,
    p_snap jsonb default null) returns jsonb as $$
  select jsonb_build_object('id', p_id::uuid, 'segment_id', p_seg::uuid,
    'customer_id', 'cccccccc-0000-0000-0000-000000000008',
    'started_at', p_at, 'scheduled_end_at', p_end,
    'pricing_snapshot', coalesce(p_snap, pg_temp.snap()),
    'resource_id', pg_temp.r(p_res), 'activity_code', 'PS5',
    'controller_count', p_cc, 'allocations', '[]'::jsonb, 'moves', '[]'::jsonb) $$ language sql;
-- One charge row as the device sends it (segment_index is unique per session).
create temp sequence ch_index;
create function pg_temp.ch(p_seg text, p_band text, p_res text, p_cc int, p_s text, p_e text,
    p_played int, p_billed int, p_price int, p_amount int) returns jsonb as $$
  select jsonb_build_object('id', gen_random_uuid(), 'segment_id', p_seg::uuid,
    'segment_index', nextval('ch_index'),
    'band_code', p_band, 'activity_code', 'PS5', 'resource_id', pg_temp.r(p_res),
    'controller_count', p_cc, 'segment_start', p_s, 'segment_end', p_e,
    'played_minutes', p_played, 'billed_minutes', p_billed, 'unit_minutes', 60,
    'unit_price_paise', p_price, 'amount_paise', p_amount) $$ language sql;
create function pg_temp.end_op(p_id text, p_segs jsonb, p_sched text, p_at text, p_billed bigint,
    p_charges jsonb, p_waive boolean default false) returns jsonb as $$
  select jsonb_build_object('session_id', p_id::uuid, 'ended_at', p_at,
    'billed_amount_paise', p_billed, 'mark_waived', p_waive, 'expected_segment_ids', p_segs,
    'expected_scheduled_end_at', p_sched, 'charges', p_charges) $$ language sql;

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.push('customer.create', jsonb_build_object(
    'id','cccccccc-0000-0000-0000-000000000008','name','Asha','phone','9800000008',
    'is_guest', false))->>'status', 'applied', 'fixture customer');

-- ------------------------------------------- 1. the price list a session freezes
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','HEX', 1,
    '2026-10-01T11:00:00Z','2026-10-01T12:00:00Z',
    jsonb_set(pg_temp.snap(), '{rates}', (select jsonb_agg(r || '{"price_paise":0}')
      from jsonb_array_elements(pg_temp.snap()->'rates') r))))->>'error',
  'pricing_snapshot_mismatch', 'a forged ₹0 price list is refused at start');
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','HEX', 1,
    '2026-10-01T11:00:00Z','2026-10-01T12:00:00Z', '{}'::jsonb))->>'error',
  'pricing_snapshot_mismatch', 'an empty price list is refused at start');
select is((select count(*)::int from sessions where id = 'a8000000-0000-0000-0000-000000000001'), 0,
  'nothing written by the refused starts');
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','HEX', 1,
    '2026-10-01T11:00:00Z','2026-10-01T12:00:00Z',
    pg_temp.snap() || jsonb_build_object('rate_card_name', 'Weekday card',
      'rates', (select jsonb_agg(r order by n desc)
                  from jsonb_array_elements(pg_temp.snap()->'rates') with ordinality x(r, n)))))
    ->>'status', 'applied', 'the arena''s own list starts (card name and order do not matter)');

-- ------------------------------------------- 2. happy-hour split: under-billing refused
-- HEX, 1 pad, 16:30–17:30 IST: 30 min happy (₹60) + 30 min standard (₹75) = ₹135.
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000001',
    '["b8000000-0000-0000-0000-000000000001"]', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z', 12000,
    jsonb_build_array(pg_temp.ch('b8000000-0000-0000-0000-000000000001','happy','HEX',1,
      '2026-10-01T11:00:00Z','2026-10-01T12:00:00Z',60,60,12000,12000))))->>'error',
  'price_mismatch', 'the whole hour billed at the happy rate (under-billing) is refused');
select matches(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000001',
    '["b8000000-0000-0000-0000-000000000001"]', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z', 0,
    '[]'::jsonb))->>'detail', 'server 13500 paise, device 0 paise',
  'the refusal names the server''s bill and the device''s');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000001',
    '["b8000000-0000-0000-0000-000000000001"]', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z', 13500,
    jsonb_build_array(pg_temp.ch('b8000000-0000-0000-0000-000000000001','standard','HEX',1,
      '2026-10-01T11:00:00Z','2026-10-01T12:00:00Z',60,60,13500,13500))))->>'error',
  'price_mismatch', 'the right total over invented charge rows is refused');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000001',
    '["b8000000-0000-0000-0000-000000000001"]', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z', 15000,
    '[]'::jsonb))->>'error', 'price_mismatch', 'over-billing is refused too (0 paise tolerance)');
select is((select status from sessions where id = 'a8000000-0000-0000-0000-000000000001'), 'active',
  'after the refusals the session is still running');
select is((select count(*)::int from session_charges where session_id = 'a8000000-0000-0000-0000-000000000001'), 0,
  'and has no charge rows');
select ok((select ended_at is null from session_segments where id = 'b8000000-0000-0000-0000-000000000001'),
  'and its segment is still open (the refused op rolled back whole)');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000001',
    '["b8000000-0000-0000-0000-000000000001"]', '2026-10-01T12:00:00Z', '2026-10-01T10:59:00Z', 0,
    '[]'::jsonb))->>'error', 'invalid', 'an end before the session started is refused');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000001',
    '["b8000000-0000-0000-0000-000000000001"]', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z', 13500,
    jsonb_build_array(
      pg_temp.ch('b8000000-0000-0000-0000-000000000001','happy','HEX',1,
        '2026-10-01T11:00:00Z','2026-10-01T11:30:00Z',30,30,12000,6000),
      pg_temp.ch('b8000000-0000-0000-0000-000000000001','standard','HEX',1,
        '2026-10-01T11:30:00Z','2026-10-01T12:00:00Z',30,30,15000,7500))))->>'status',
  'applied', 'the correct happy/standard split is accepted');
select is((select billed_amount_paise from sessions where id = 'a8000000-0000-0000-0000-000000000001'),
  13500::bigint, 'billed ₹135');

-- ------------------------------------------- 3. extension + switch + cash rounding
-- RIFT, Fri 18:30 IST (standard). 2 pads 13:00–13:30Z, then 1 pad to 14:15Z.
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000002','b8000000-0000-0000-0000-000000000002','RIFT', 2,
    '2026-10-02T13:00:00Z','2026-10-02T14:00:00Z'))->>'status', 'applied', 'RIFT starts with 2 pads');
select is(pg_temp.push('session.extend', jsonb_build_object('session_id','a8000000-0000-0000-0000-000000000002',
    'extension_id', gen_random_uuid(), 'added_minutes', 30, 'old_end_at','2026-10-02T14:00:00Z',
    'new_end_at','2026-10-02T14:30:00Z', 'added_amount_paise', 0))->>'error', 'price_mismatch',
  'an extension quoted at ₹0 is refused');
select is(pg_temp.push('session.extend', jsonb_build_object('session_id','a8000000-0000-0000-0000-000000000002',
    'extension_id', gen_random_uuid(), 'added_minutes', 30, 'old_end_at','2026-10-02T14:00:00Z',
    'new_end_at','2026-10-02T13:30:00Z', 'added_amount_paise', 0))->>'error', 'invalid',
  'an extension that moves the end backwards is refused');
select is(pg_temp.push('session.extend', jsonb_build_object('session_id','a8000000-0000-0000-0000-000000000002',
    'extension_id', gen_random_uuid(), 'added_minutes', 30, 'old_end_at','2026-10-02T14:00:00Z',
    'new_end_at','2026-10-02T14:30:00Z', 'added_amount_paise', 14000))->>'status', 'applied',
  'the planner''s +30 min at the 2-pad rate (₹140) is accepted');
select is(pg_temp.push('session.reconfigure', jsonb_build_object('session_id','a8000000-0000-0000-0000-000000000002',
    'at','2026-10-02T13:30:00Z','expected_segment_id','b8000000-0000-0000-0000-000000000002',
    'new_segment_id','b8000000-0000-0000-0000-000000000003','resource_id', pg_temp.r('RIFT'),
    'activity_code','PS5','controller_count',1,'allocations','[]'::jsonb,'moves','[]'::jsonb))
    ->>'status', 'applied', 'down to 1 pad at 13:30Z');
-- ₹140.00 + ₹112.50 = ₹252.50 → cash-rounded once to ₹253 (not per segment).
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000002',
    '["b8000000-0000-0000-0000-000000000002","b8000000-0000-0000-0000-000000000003"]',
    '2026-10-02T14:30:00Z', '2026-10-02T14:15:00Z', 25200,
    jsonb_build_array(
      pg_temp.ch('b8000000-0000-0000-0000-000000000002','standard','RIFT',2,
        '2026-10-02T13:00:00Z','2026-10-02T13:30:00Z',30,30,28000,14000),
      pg_temp.ch('b8000000-0000-0000-0000-000000000003','standard','RIFT',1,
        '2026-10-02T13:30:00Z','2026-10-02T14:15:00Z',45,45,15000,11250))))->>'error',
  'price_mismatch', 'rounding the total down a rupee is refused');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000002',
    '["b8000000-0000-0000-0000-000000000002","b8000000-0000-0000-0000-000000000003"]',
    '2026-10-02T14:30:00Z', '2026-10-02T14:15:00Z', 25300,
    jsonb_build_array(
      pg_temp.ch('b8000000-0000-0000-0000-000000000003','standard','RIFT',1,
        '2026-10-02T13:30:00Z','2026-10-02T14:15:00Z',45,45,15000,11250),
      pg_temp.ch('b8000000-0000-0000-0000-000000000002','standard','RIFT',2,
        '2026-10-02T13:00:00Z','2026-10-02T13:30:00Z',30,30,28000,14000))))->>'status',
  'applied', 'two segments, rounded once to ₹253, accepted (row order is the device''s)');

-- ------------------------------------------- 4. waived
-- VOID, Sat (no happy hour) 10:00–11:00Z, 1 pad = ₹150.
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000004','b8000000-0000-0000-0000-000000000004','VOID', 1,
    '2026-10-03T10:00:00Z','2026-10-03T11:00:00Z'))->>'status', 'applied', 'VOID starts');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000004',
    '["b8000000-0000-0000-0000-000000000004"]', '2026-10-03T11:00:00Z', '2026-10-03T11:00:00Z', 0,
    '[]'::jsonb, true))->>'error', 'price_mismatch',
  'waiving does not skip pricing: a ₹0 bill marked waived is refused');
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000004',
    '["b8000000-0000-0000-0000-000000000004"]', '2026-10-03T11:00:00Z', '2026-10-03T11:00:00Z', 15000,
    jsonb_build_array(pg_temp.ch('b8000000-0000-0000-0000-000000000004','standard','VOID',1,
      '2026-10-03T10:00:00Z','2026-10-03T11:00:00Z',60,60,15000,15000)), true))->>'status',
  'applied', 'the real bill, waived, is accepted');
select is((select payment_status || ' ' || billed_amount_paise from sessions
            where id = 'a8000000-0000-0000-0000-000000000004'), 'waived 15000',
  'waived, with the true amount on record');

-- ------------------------------------------- 5. groups
create function pg_temp.grp(p_id text, p_mode text, p_snap jsonb default null) returns jsonb as $$
  select jsonb_build_object('id', p_id::uuid,
    'primary_customer_id','cccccccc-0000-0000-0000-000000000008','player_count',2,
    'purchased_controller_count',2,'started_at','2026-10-01T11:00:00Z',
    'scheduled_end_at','2026-10-01T12:00:00Z','pricing_snapshot', coalesce(p_snap, pg_temp.snap()),
    'billing_mode', p_mode,
    'assignments', jsonb_build_array(
      jsonb_build_object('id','98800000-0000-0000-0000-000000000001','player_number',1,'idx',0,
        'resource_id', pg_temp.r('GHOST'),'activity_code','PS5','controller_count',1,
        'allocations','[]'::jsonb,'moves','[]'::jsonb),
      jsonb_build_object('id','98800000-0000-0000-0000-000000000002','player_number',2,'idx',0,
        'resource_id', pg_temp.r('GHOST'),'activity_code','PS5','controller_count',1,
        'allocations','[]'::jsonb,'moves','[]'::jsonb))) $$ language sql;
select is(pg_temp.push('group.create', pg_temp.grp('98880000-0000-0000-0000-000000000001',
    'shared_controller_pool'))->>'error', 'pricing_snapshot_mismatch',
  'a group billing mode other than the price list''s is refused');
select is(pg_temp.push('group.create', pg_temp.grp('98880000-0000-0000-0000-000000000001', 'per_system',
    jsonb_set(pg_temp.snap(), '{policy,money_rounding_paise}', '100000')))->>'error',
  'pricing_snapshot_mismatch', 'a group frozen on an altered policy is refused');
select is(pg_temp.push('group.create', pg_temp.grp('98880000-0000-0000-0000-000000000001', 'per_system'))
    ->>'status', 'applied', 'two players share GHOST (one system, 2 pads)');
select is(pg_temp.push('group.extend', jsonb_build_object('group_id','98880000-0000-0000-0000-000000000001',
    'extension_id', gen_random_uuid(), 'added_minutes', 30, 'old_end_at','2026-10-01T12:00:00Z',
    'new_end_at','2026-10-01T12:30:00Z', 'added_amount_paise', 7500))->>'error', 'price_mismatch',
  'a group extension quoted at the 1-pad rate is refused');
select is(pg_temp.push('group.extend', jsonb_build_object('group_id','98880000-0000-0000-0000-000000000001',
    'extension_id', gen_random_uuid(), 'added_minutes', 30, 'old_end_at','2026-10-01T12:00:00Z',
    'new_end_at','2026-10-01T12:30:00Z', 'added_amount_paise', 14000))->>'status', 'applied',
  'the 2-pad rate for +30 min (₹140) is accepted');
-- 16:30–17:30 IST at the 2-pad rate: ₹110 happy + ₹140 standard = ₹250.
create function pg_temp.gch(p_band text, p_s text, p_e text, p_price int, p_amount int) returns jsonb as $$
  select jsonb_build_object('id', gen_random_uuid(), 'charge_index', 0, 'band_code', p_band,
    'activity_code','PS5','resource_id', pg_temp.r('GHOST'),'controller_count',2,
    'segment_start', p_s, 'segment_end', p_e, 'played_minutes',30,'billed_minutes',30,
    'unit_minutes',60,'unit_price_paise', p_price,'amount_paise', p_amount) $$ language sql;
create function pg_temp.gend(p_billed bigint, p_charges jsonb) returns jsonb as $$
  select jsonb_build_object('group_id','98880000-0000-0000-0000-000000000001',
    'ended_at','2026-10-01T12:00:00Z','billed_amount_paise', p_billed,
    'expected_assignment_ids', '["98800000-0000-0000-0000-000000000001","98800000-0000-0000-0000-000000000002"]'::jsonb,
    'expected_scheduled_end_at','2026-10-01T12:30:00Z','charges', p_charges) $$ language sql;
select is(pg_temp.push('group.end', pg_temp.gend(12000, jsonb_build_array(
    pg_temp.gch('happy','2026-10-01T11:00:00Z','2026-10-01T11:30:00Z',12000,6000),
    pg_temp.gch('standard','2026-10-01T11:30:00Z','2026-10-01T12:00:00Z',12000,6000))))->>'error',
  'price_mismatch', 'billing the shared system at the 1-pad rate (under-billing) is refused');
select is((select status from group_sessions where id = '98880000-0000-0000-0000-000000000001'), 'active',
  'the group is still running');
select is(pg_temp.push('group.end', pg_temp.gend(25000, jsonb_build_array(
    pg_temp.gch('happy','2026-10-01T11:00:00Z','2026-10-01T11:30:00Z',22000,11000),
    pg_temp.gch('standard','2026-10-01T11:30:00Z','2026-10-01T12:00:00Z',28000,14000))))->>'status',
  'applied', 'the happy/standard split at the 2-pad rate is accepted');
select is((select billed_amount_paise from group_sessions where id = '98880000-0000-0000-0000-000000000001'),
  25000::bigint, 'group billed ₹250');

-- ------------------------------------------- 6. a device offline across a price change
create temp table old_list as select pg_temp.snap() as s;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code','PS5','band','standard',
    'controller_count',1,'unit_minutes',60,'price_paise',16000))->>'status', 'applied',
  'owner raises the 1-pad price');
select is((select count(*)::int from pricing_catalog_history where arena_id = pg_temp.arena()), 1,
  'the replaced list is kept');
select is(pg_temp.push('settings.save', jsonb_build_object('key','business_hours',
    'json', pg_temp.snap()->'hours'))->>'status', 'applied', 'saving unchanged hours');
select is((select count(*)::int from pricing_catalog_history where arena_id = pg_temp.arena()), 1,
  'a save that changes nothing records no version');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000006','b8000000-0000-0000-0000-000000000006','HEX', 1,
    '2026-10-03T12:00:00Z','2026-10-03T13:00:00Z', (select s from old_list)))->>'status', 'applied',
  'a start frozen on the list replaced minutes ago is accepted (offline device)');
update pricing_catalog_history set retired_at = statement_timestamp() - interval '73 hours';
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000007','b8000000-0000-0000-0000-000000000007','RIFT', 1,
    '2026-10-03T12:00:00Z','2026-10-03T13:00:00Z', (select s from old_list)))->>'error',
  'pricing_snapshot_mismatch', 'a list replaced more than 72 h ago is refused');
select is(pg_temp.push('session.start', pg_temp.start(
    'a8000000-0000-0000-0000-000000000007','b8000000-0000-0000-0000-000000000007','RIFT', 1,
    '2026-10-03T12:00:00Z','2026-10-03T13:00:00Z'))->>'status', 'applied', 'the live list starts');
-- The old-list session is billed from ITS snapshot (₹150), not today's ₹160.
select is(pg_temp.push('session.end', pg_temp.end_op('a8000000-0000-0000-0000-000000000006',
    '["b8000000-0000-0000-0000-000000000006"]', '2026-10-03T13:00:00Z', '2026-10-03T13:00:00Z', 15000,
    jsonb_build_array(pg_temp.ch('b8000000-0000-0000-0000-000000000006','standard','HEX',1,
      '2026-10-03T12:00:00Z','2026-10-03T13:00:00Z',60,60,15000,15000))))->>'status',
  'applied', 'a session is priced from the list it was started on');

-- ------------------------------------------- 7. no client surface
select ok(not has_function_privilege('authenticated', f, 'execute'), f || ' is not client-callable')
  from unnest(array['_pr_quote(jsonb,text,int,timestamptz,timestamptz)',
    '_pr_session_bill(uuid,timestamptz)','_pr_group_bill(uuid,timestamptz)',
    '_pricing_snapshot(uuid)','_assert_snapshot(uuid,jsonb)','op_session_end(uuid,jsonb)',
    '_op_session_end_v1(uuid,jsonb)','op_group_end(uuid,jsonb)','_op_group_end_v1(uuid,jsonb)',
    'op_session_start(uuid,jsonb)','op_group_create(uuid,jsonb)','op_session_extend(uuid,jsonb)',
    'op_group_extend(uuid,jsonb)','_sync_apply(uuid,text,jsonb)','_sync_apply_v1(uuid,text,jsonb)']) f;
select ok(not has_table_privilege('authenticated', 'pricing_catalog_history', 'select'),
  'price-list history is server-only');

select * from finish();
rollback;
