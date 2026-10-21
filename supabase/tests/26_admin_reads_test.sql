-- The dashboard's aggregated reads: arena_overview, arena_station_stats, arena_game_stats,
-- arena_game_fans, arena_members and arena_activity. Owner level only; figures on a small
-- fixture: Thu 2026-10-01, Neha plays EA FC on HEX 18:30–19:30 IST (13:00–14:00Z, ₹150, paid
-- by UPI); a walk-in plays EA FC on VOID 19:30–20:00 IST (₹75, voided).
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000126'::uuid, 'pgtap 26');
-- These fixtures replay fixed past dates: widen the offline window (offline_rules, default
-- 24 h) so device-stamped times from then are accepted.
insert into settings(arena_id, key, json)
  select id, 'offline_rules', '{"max_offline_hours": 100000}' from arenas where name like 'pgtap%'
  on conflict (arena_id, key) do nothing;
select _seed_arena_catalog('e0000000-0000-4000-8000-000000000126'::uuid);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values
  ('00000000-0000-0000-0000-000000000000','26000000-0000-0000-0000-000000000001','authenticated',
   'authenticated','owner26@test.local','',now(),now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','26000000-0000-0000-0000-000000000002','authenticated',
   'authenticated','staff26@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000126'::uuid,'26000000-0000-0000-0000-000000000001','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true),
  ('e0000000-0000-4000-8000-000000000126'::uuid,'26000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill','discount','members'],true);

create function pg_temp.arena() returns uuid as $$ select 'e0000000-0000-4000-8000-000000000126'::uuid $$ language sql;
create function pg_temp.r(n text) returns uuid as $$ select id from resources where name = n and arena_id = 'e0000000-0000-4000-8000-000000000126'::uuid $$ language sql;
create function pg_temp.game() returns uuid as $$ select id from games where name = 'EA SPORTS FC 25' and arena_id = 'e0000000-0000-4000-8000-000000000126'::uuid $$ language sql;
create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push(pg_temp.arena(),
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)), 'pgtap')
    -> 'results' -> 0 $$ language sql;
create function pg_temp.session(p_id text, p_seg text, p_cust text, p_res text, p_s text, p_e text,
    p_billed int, p_minutes int) returns setof text as $$
  select pg_temp.push('session.start', jsonb_build_object('id', p_id::uuid, 'segment_id', p_seg::uuid,
      'customer_id', p_cust::uuid, 'started_at', p_s, 'scheduled_end_at', p_e,
      'pricing_snapshot', _pricing_snapshot(pg_temp.arena()), 'resource_id', pg_temp.r(p_res),
      'activity_code','PS5','game_id', pg_temp.game(), 'controller_count', 1,
      'allocations','[]'::jsonb,'moves','[]'::jsonb))->>'status'
  union all
  select pg_temp.push('session.end', jsonb_build_object('session_id', p_id::uuid, 'ended_at', p_e,
      'billed_amount_paise', p_billed, 'expected_segment_ids', jsonb_build_array(p_seg::uuid),
      'expected_scheduled_end_at', p_e,
      'charges', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'segment_id', p_seg::uuid,
        'segment_index', 0, 'band_code','standard','activity_code','PS5','resource_id', pg_temp.r(p_res),
        'controller_count', 1, 'segment_start', p_s, 'segment_end', p_e, 'played_minutes', p_minutes,
        'billed_minutes', p_minutes, 'unit_minutes', 60, 'unit_price_paise', 15000,
        'amount_paise', p_billed))))->>'status' $$ language sql;

-- ===================== fixture
select pg_temp.as_user('26000000-0000-0000-0000-000000000002');
select is(pg_temp.push('customer.create', jsonb_build_object('id','cccccccc-0000-0000-0000-000000000026',
    'name','Neha','phone','98000 26026','is_guest', false))->>'status', 'applied', 'Neha is a member');
select is(pg_temp.push('customer.create', jsonb_build_object('id','cccccccc-0000-0000-0000-000000000126',
    'name','Walk-in','is_guest', true))->>'status', 'applied', 'a walk-in guest');
select results_eq($$ select * from pg_temp.session('a2600000-0000-0000-0000-000000000001',
    'b2600000-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000026', 'HEX',
    '2026-10-01T13:00:00Z', '2026-10-01T14:00:00Z', 15000, 60) $$,
  $$ values ('applied'), ('applied') $$, 'Neha plays on HEX for an hour');
select is(pg_temp.push('payment.record', jsonb_build_object('parent_id','a2600000-0000-0000-0000-000000000001',
    'payment_id', gen_random_uuid(), 'amount_paise', 15000, 'method', 'upi'))->>'status', 'applied',
  'Neha pays ₹150 by UPI');
select results_eq($$ select * from pg_temp.session('a2600000-0000-0000-0000-000000000002',
    'b2600000-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000126', 'VOID',
    '2026-10-01T14:00:00Z', '2026-10-01T14:30:00Z', 7500, 30) $$,
  $$ values ('applied'), ('applied') $$, 'a walk-in plays on VOID for 30 minutes');
select pg_temp.as_user('26000000-0000-0000-0000-000000000001');
select is(pg_temp.push('session.void', jsonb_build_object('session_id','a2600000-0000-0000-0000-000000000002',
    'reason','test'))->>'status', 'applied', 'the walk-in''s bill is voided');

-- ===================== owner only
select pg_temp.as_user('26000000-0000-0000-0000-000000000002');
select throws_ok(q, '42501', null, 'staff cannot call ' || split_part(q, '(', 1))
  from unnest(array[
    $$ select arena_overview(pg_temp.arena(), '2026-10-01', '2026-10-02', '2026-09-30', '2026-10-01', 'hour', '2026-10-01') $$,
    $$ select arena_station_stats(pg_temp.arena(), '2026-10-01', '2026-09-02', '2026-10-02') $$,
    $$ select arena_game_stats(pg_temp.arena(), '2026-09-02') $$,
    $$ select arena_game_fans(pg_temp.arena(), pg_temp.game(), '2026-09-02') $$,
    $$ select arena_members(pg_temp.arena(), '2026-07-03', '2026-09-02') $$,
    $$ select arena_activity(pg_temp.arena(), pg_temp.r('HEX'), null, '2026-07-03') $$]) q;

select pg_temp.as_user('26000000-0000-0000-0000-000000000001');
-- ===================== overview (IST day 2026-10-01 = 2026-09-30T18:30Z … 2026-10-01T18:30Z)
create temp table ov as select arena_overview(pg_temp.arena(), '2026-09-30T18:30:00Z', '2026-10-01T18:30:00Z',
  '2026-09-29T18:30:00Z', '2026-09-30T18:30:00Z', 'hour', '2026-09-30T18:30:00Z') as o;
select is((select o->'totals' from ov), '{"takings_paise":15000,"bills":1,"minutes":60,"discount_paise":0,"discounts":0}'::jsonb,
  'totals: one bill (the voided one left out), ₹150 collected, 60 minutes');
select is((select o->'previous' from ov), '{"takings_paise":0,"bills":0,"minutes":0}'::jsonb,
  'nothing the day before');
select is((select o->'buckets' from ov),
  jsonb_build_array(jsonb_build_object('start', '2026-10-01T13:30:00+00:00'::timestamptz, 'paise', 15000)),
  'collected in the 19:00 IST hour (the bill closed at 19:30)');
select is((select o->'methods' from ov), '{"upi":{"paise":15000,"bills":1}}'::jsonb, 'all by UPI');
select is((select o->'by_type' from ov), '{"PS5":15000}'::jsonb, 'charges of the voided bill left out');
select is((select o->'top_games' from ov), '[{"name":"EA SPORTS FC 25","minutes":60}]'::jsonb, 'top game');
select is((select o->'by_staff' from ov), '[{"name":"Staff","bills":1,"paise":15000}]'::jsonb, 'by staff');
select is((select jsonb_array_length(o->'latest') from ov), 2, 'latest lists both bills, voided included');
select throws_ok($$ select arena_overview(pg_temp.arena(), '2025-01-01', '2026-10-01', '2024-01-01', '2025-01-01', 'month', '2026-10-01') $$,
  'P0001', 'invalid_range', 'more than 400 days is refused');

-- ===================== stations
create temp table st as select arena_station_stats(pg_temp.arena(), '2026-09-30T18:30:00Z',
  '2026-09-01T18:30:00Z', '2026-10-01T18:30:00Z') as s;
select is((select s->(pg_temp.r('HEX')::text) from st),
  '{"billed_today":15000,"sessions_today":1,"minutes_30":60,"billed_30":15000,"accessories":2}'::jsonb,
  'HEX: ₹150 today and over 30 days, one session, 60 minutes, two pads');
select is((select s->(pg_temp.r('VOID')::text) from st),
  '{"billed_today":0,"sessions_today":0,"minutes_30":0,"billed_30":0,"accessories":2}'::jsonb,
  'VOID: its only bill was voided');
select is((select count(*)::int from st, jsonb_object_keys(s)), 6, 'every station is listed');

-- ===================== games
select is(arena_game_stats(pg_temp.arena(), '2026-09-01T18:30:00Z')->(pg_temp.game()::text),
  '{"minutes_30":60,"sessions_30":1,"playing_now":0}'::jsonb, 'EA FC: 60 minutes, one bill, nobody now');
select is(arena_game_fans(pg_temp.arena(), pg_temp.game(), '2026-09-01T18:30:00Z'),
  '[{"customer_id":"cccccccc-0000-0000-0000-000000000026","name":"Neha","sessions":1,"minutes":60}]'::jsonb,
  'Neha is the top fan (guests left out)');

-- ===================== members
select is(arena_members(pg_temp.arena(), '2026-07-03T18:30:00Z', '2026-09-01T18:30:00Z')->'total', '1'::jsonb,
  'only registered members are listed');
select is((arena_members(pg_temp.arena(), '2026-07-03T18:30:00Z', '2026-09-01T18:30:00Z')->'rows'->0)
    - 'created_at' - 'last_visit',
  '{"id":"cccccccc-0000-0000-0000-000000000026","name":"Neha","phone":"98000 26026","birth_year":null,
    "visits":1,"minutes":60,"spent_30_paise":15000}'::jsonb, 'Neha: one visit, 60 minutes, ₹150');
select is(arena_members(pg_temp.arena(), '2026-07-03T18:30:00Z', '2026-09-01T18:30:00Z', '26026')->'total',
  '1'::jsonb, 'search by phone digits');
select is(arena_members(pg_temp.arena(), '2026-07-03T18:30:00Z', '2026-09-01T18:30:00Z', 'nobody')->'total',
  '0'::jsonb, 'a search with no match');

-- ===================== activity
select is(arena_activity(pg_temp.arena(), pg_temp.r('VOID'), null, '2026-07-03T18:30:00Z')->'bills'->0->>'status',
  'voided', 'a station''s bills include voided ones');
select is(arena_activity(pg_temp.arena(), pg_temp.r('VOID'), null, '2026-07-03T18:30:00Z')->'bills'->0->'customer',
  'null'::jsonb, 'a walk-in has no name');
select is(arena_activity(pg_temp.arena(), null, 'cccccccc-0000-0000-0000-000000000026', '2026-07-03T18:30:00Z')->'games',
  jsonb_build_array(jsonb_build_object('game_id', pg_temp.game(), 'name', 'EA SPORTS FC 25', 'minutes', 60)),
  'a member''s minutes per game');
select throws_ok($$ select arena_activity(pg_temp.arena(), null, null, '2026-07-03') $$, 'P0001', 'invalid',
  'one of station or member is required');

select * from finish();
rollback;
