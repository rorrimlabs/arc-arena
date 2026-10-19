-- Catalog from scratch: arenas start empty, so the owner must be able to build
-- a working arena through sync_push alone — station type (activity.upsert),
-- price (rate.upsert), station (resource.upsert), pad (controller.upsert),
-- game (game.upsert) — and the floor can then start a session priced by it.
--
-- Thu 2026-10-01, 13:30 IST = 08:00Z (standard band).
begin;
create extension if not exists pgtap;
select * from no_plan();

-- An empty arena (as _create_arena_with_owner now makes them) and its people.
insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000150'::uuid, 'pgtap 15'),
  ('e0000000-0000-4000-8000-000000000151'::uuid, 'pgtap 15 neighbour');
-- These fixtures replay fixed past dates: widen the offline window (offline_rules, default
-- 24 h) so device-stamped times from then are accepted.
insert into settings(arena_id, key, json)
  select id, 'offline_rules', '{"max_offline_hours": 100000}' from arenas where name like 'pgtap%'
  on conflict (arena_id, key) do nothing;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('15000000-0000-0000-0000-000000000001', 'owner15@test.local'),
      ('15000000-0000-0000-0000-000000000002', 'staff15@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000150','15000000-0000-0000-0000-000000000001','Owner','owner',
    _known_perms(), true),
  ('e0000000-0000-4000-8000-000000000150','15000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill','members'], true);
-- A type in the neighbour arena, to prove ids never cross arenas.
insert into activities(id, arena_id, code, name)
  values ('a1500000-0000-0000-0000-0000000000ff', 'e0000000-0000-4000-8000-000000000151', 'PS5', 'PS5');

create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000150'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
create function pg_temp.ps5(p_name text, p_code text default 'ps5', p_pads boolean default true,
    p_model text default 'hourly', p_id text default 'a1500000-0000-0000-0000-000000000001')
  returns jsonb as $$
  select jsonb_build_object('id', p_id, 'code', p_code, 'name', p_name,
    'uses_controllers', p_pads, 'uses_games', true, 'duration_model', p_model) $$ language sql;

-- ------------------------------------------------ 1. who may add a type
select pg_temp.as_user('15000000-0000-0000-0000-000000000002');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PlayStation 5'))->>'error', 'forbidden',
  'staff without settings cannot add a station type');
select pg_temp.as_user('15000000-0000-0000-0000-000000000001');

-- ------------------------------------------------ 2. input rules
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PlayStation 5', 'ps 5'))->>'error', 'invalid_code',
  'a code with a space is refused');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PlayStation 5', 'TOOLONGCODE123'))->>'error',
  'invalid_code', 'a code over 12 characters is refused');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('  '))->>'error', 'invalid_name',
  'a blank name is refused');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PlayStation 5') || '{"duration_model":"daily"}')
    ->>'error', 'invalid', 'an unknown billing style is refused');
select is(pg_temp.push('activity.upsert',
    pg_temp.ps5('PlayStation 5', p_id => 'a1500000-0000-0000-0000-0000000000ff'))->>'error',
  'not_found', 'another arena''s type id is not found');
select is((select count(*)::int from activities where arena_id = 'e0000000-0000-4000-8000-000000000150'), 0,
  'nothing was written by the refused ops');

-- ------------------------------------------------ 3. add and edit
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PlayStation 5'))->>'status', 'applied',
  'the owner adds a PS5 type');
select is((select code || '/' || name || '/' || uses_controllers from activities
            where id = 'a1500000-0000-0000-0000-000000000001'),
  'PS5/PlayStation 5/true', 'the code is stored upper-cased');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PS5 again', 'PS5',
    p_id => 'a1500000-0000-0000-0000-000000000002'))->>'error', 'duplicate',
  'a second type cannot reuse the code');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PlayStation 5', 'PS4'))->>'error', 'code_locked',
  'an existing type keeps its code');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PS5 consoles'))->>'status', 'applied',
  'renaming is fine');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PS5 consoles') || '{"happy_hour_eligible":false}')
    ->>'status', 'applied', 'a happy_hour_eligible flag from an older client is ignored');

-- ------------------------------------------------ 4. price, station, pad, game
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'PS5', 'band', 'standard',
    'controller_count', 1, 'unit_minutes', 60, 'price_paise', 10000))->>'status', 'applied',
  'the owner prices one pad at ₹100 an hour');
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'PS5', 'band', 'happy',
    'controller_count', 1, 'unit_minutes', 60, 'price_paise', 8000))->>'error', 'invalid',
  'a happy-hour rate is refused: happy hours are a pricing rule');
select is((select count(*)::int from rate_bands where arena_id = 'e0000000-0000-4000-8000-000000000150'
            and code <> 'standard'), 0, 'and no other band was created');
-- An arena priced before happy hours became a rule still holds happy rates: they stay out of
-- the price list, so a floor app (which drops them too) can still start sessions.
insert into rates(arena_id, rate_card_id, activity_id, band_id, controller_count, unit_minutes, price_paise)
  select 'e0000000-0000-4000-8000-000000000150', _active_card('e0000000-0000-4000-8000-000000000150'),
    id, _band_id('e0000000-0000-4000-8000-000000000150', 'happy'), 1, 60, 8000
    from activities where arena_id = 'e0000000-0000-4000-8000-000000000150' and code = 'PS5';
select is((select jsonb_agg(distinct r->>'band') from jsonb_array_elements(
             _pricing_snapshot('e0000000-0000-4000-8000-000000000150')->'rates') r),
  '["standard"]'::jsonb, 'a leftover happy rate is not in the price list');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b1500000-0000-0000-0000-000000000001',
    'name', 'HEX', 'kind', 'station', 'activity_codes', jsonb_build_array('PS5')))->>'status', 'applied',
  'adds station HEX offering PS5');
select is(pg_temp.push('controller.upsert', jsonb_build_object('id', 'c1500000-0000-0000-0000-000000000001',
    'label', 'HEX-1', 'home_resource_id', 'b1500000-0000-0000-0000-000000000001',
    'current_resource_id', 'b1500000-0000-0000-0000-000000000001'))->>'status', 'applied',
  'adds pad HEX-1');
select is(pg_temp.push('game.upsert', jsonb_build_object('id', 'd1500000-0000-0000-0000-000000000001',
    'name', 'Tekken 8', 'platforms', jsonb_build_array('PS5'), 'player_mode', 'local',
    'max_local_players', 2))->>'status', 'applied', 'adds a game');
select is(pg_temp.push('game.set_compat', jsonb_build_object('game_id', 'd1500000-0000-0000-0000-000000000001',
    'resource_id', 'b1500000-0000-0000-0000-000000000001', 'status', 'playable'))->>'status', 'applied',
  'and marks it installed on HEX (a game is playable only where it is marked)');

-- ------------------------------------------------ 5. the floor can use it
select pg_temp.as_user('15000000-0000-0000-0000-000000000002');
select is(pg_temp.push('customer.create', jsonb_build_object('id', 'cccccccc-0000-0000-0000-000000000015',
    'name', 'Kiran', 'phone', '9800001515', 'is_guest', false))->>'status', 'applied', 'staff adds a customer');
select is(pg_temp.push('session.start', jsonb_build_object(
    'id', 'f1500000-0000-0000-0000-000000000001', 'segment_id', 'f1500000-0000-0000-0000-000000000002',
    'customer_id', 'cccccccc-0000-0000-0000-000000000015',
    'started_at', '2026-10-01T08:00:00Z', 'scheduled_end_at', '2026-10-01T09:00:00Z',
    'pricing_snapshot', _pricing_snapshot('e0000000-0000-4000-8000-000000000150'::uuid),
    'resource_id', 'b1500000-0000-0000-0000-000000000001', 'activity_code', 'PS5',
    'game_id', 'd1500000-0000-0000-0000-000000000001', 'controller_count', 1,
    'allocations', jsonb_build_array(jsonb_build_object('controller_id', 'c1500000-0000-0000-0000-000000000001')),
    'moves', '[]'::jsonb))->>'error', null,
  'staff start a session on the owner-built station, priced by the owner-built list');

-- ------------------------------------------------ 6. edits while it runs
select pg_temp.as_user('15000000-0000-0000-0000-000000000001');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PS5 consoles', p_pads => false))->>'error',
  'activity_busy', 'pad tracking cannot be switched while a PS5 session runs');
create temp table history_before as select count(*) as n from pricing_catalog_history
  where arena_id = 'e0000000-0000-4000-8000-000000000150';
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PS5 consoles', p_model => 'flat_hourly'))->>'status',
  'applied', 'the billing model can change');
select is((select count(*)::int from pricing_catalog_history
            where arena_id = 'e0000000-0000-4000-8000-000000000150') - (select n::int from history_before), 1,
  'and that retires the previous price list, so the running session still validates');
select is(pg_temp.push('activity.upsert', pg_temp.ps5('PS5 consoles') || '{"active":false}')->>'status',
  'applied', 'a type is retired with active = false');
select ok(not (select active from activities where id = 'a1500000-0000-0000-0000-000000000001'),
  'and stays on record');

-- ------------------------------------------------ 7. the Pricing screen's read
select is((select jsonb_agg(e->>'code' || ':' || (e->>'stations') || ':' || (e->>'active'))
             from jsonb_array_elements(arena_pricing('e0000000-0000-4000-8000-000000000150')->'types') e),
  '["PS5:1:false"]'::jsonb, 'arena_pricing lists the type with its station count, retired ones too');
select is(arena_pricing('e0000000-0000-4000-8000-000000000150')->'rates',
  jsonb_build_array(jsonb_build_object('activity_code', 'PS5', 'band', 'standard',
    'controller_count', 1, 'unit_minutes', 60, 'price_paise', 10000)), 'and the active rates');
select is((select array_agg(k order by k) from jsonb_object_keys(
             arena_pricing('e0000000-0000-4000-8000-000000000150')->'hours') k), array['open'],
  'and the opening hours the price list uses (default until saved; no happy hours)');
select pg_temp.as_user('15000000-0000-0000-0000-000000000002');
select throws_ok($$ select arena_pricing('e0000000-0000-4000-8000-000000000150') $$,
  '42501', 'forbidden', 'staff cannot read pricing');

-- ------------------------------------------------ 8. removing a type
select is(pg_temp.push('activity.remove', jsonb_build_object('id', 'a1500000-0000-0000-0000-000000000001'))
    ->>'error', 'forbidden', 'staff cannot remove a type');
select pg_temp.as_user('15000000-0000-0000-0000-000000000001');
select is(pg_temp.push('activity.remove', jsonb_build_object('id', 'a1500000-0000-0000-0000-000000000001'))
    ->>'error', 'activity_has_stations', 'a type a station still offers is refused');
select is(pg_temp.push('resource.set_status', jsonb_build_object('id', 'b1500000-0000-0000-0000-000000000001',
    'status', 'disabled'))->>'error', 'resource_busy', 'HEX cannot be retired while its session runs');
select is(pg_temp.push('session.void', jsonb_build_object('session_id', 'f1500000-0000-0000-0000-000000000001',
    'reason', 'test', 'at', '2026-10-01T08:30:00Z'))->>'status', 'applied', 'the session is closed (voided)');
select is(pg_temp.push('resource.set_status', jsonb_build_object('id', 'b1500000-0000-0000-0000-000000000001',
    'status', 'disabled'))->>'status', 'applied', 'the owner retires HEX');
select is(pg_temp.push('activity.remove', jsonb_build_object('id', 'a1500000-0000-0000-0000-000000000001'))
    ->'result'->>'removed', 'retired', 'PS5 has a session on record: it is retired, not deleted');
select ok(exists(select 1 from activities where id = 'a1500000-0000-0000-0000-000000000001' and not active),
  'and stays for the bills that use it');

select is(pg_temp.push('activity.upsert', jsonb_build_object('id', 'a1500000-0000-0000-0000-000000000003',
    'code', 'VR', 'name', 'VR', 'duration_model', 'unit')) ->>'status', 'applied', 'a VR type is added');
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'VR', 'band', 'standard',
    'unit_minutes', 30, 'price_paise', 20000))->>'status', 'applied', 'and priced');
select is(pg_temp.push('activity.remove', jsonb_build_object('id', 'a1500000-0000-0000-0000-000000000003'))
    ->'result'->>'removed', 'deleted', 'never used: it is deleted');
select is((select count(*)::int from activities where id = 'a1500000-0000-0000-0000-000000000003')
        + (select count(*)::int from rates r join activities a on a.id = r.activity_id where a.code = 'VR'
             and a.arena_id = 'e0000000-0000-4000-8000-000000000150'), 0, 'with its prices');
select ok(exists(select 1 from sync_tombstones where arena_id = 'e0000000-0000-4000-8000-000000000150'
    and table_name = 'activities' and row_key->>'id' = 'a1500000-0000-0000-0000-000000000003'),
  'and devices are told it is gone');
select is(pg_temp.push('activity.remove', jsonb_build_object('id', 'a1500000-0000-0000-0000-000000000003'))
    ->'result'->>'removed', 'deleted', 'removing it again is a no-op');

select * from finish();
rollback;
