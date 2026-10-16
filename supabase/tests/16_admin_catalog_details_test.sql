-- Admin catalog details: a game's age rating and media (game.upsert), and the arena's name, area
-- and phone (arena.update). Both go through sync_push with the settings permission, stay inside
-- the caller's arena, and edits from builds that do not send the new fields keep them.
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000160'::uuid, 'pgtap 16'),
  ('e0000000-0000-4000-8000-000000000161'::uuid, 'pgtap 16 neighbour');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated',
         u.email, '', now(), now(), now(), '{}', '{}', false, false
    from (values
      ('16000000-0000-0000-0000-000000000001', 'owner16@test.local'),
      ('16000000-0000-0000-0000-000000000002', 'staff16@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000160','16000000-0000-0000-0000-000000000001','Owner','owner',
    _known_perms(), true),
  ('e0000000-0000-4000-8000-000000000160','16000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill','members'], true);
insert into games(id, arena_id, name)
  values ('91600000-0000-0000-0000-0000000000ff', 'e0000000-0000-4000-8000-000000000161', 'Elsewhere');

create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000160'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
create function pg_temp.game(p_extra jsonb default '{}') returns jsonb as $$
  select jsonb_build_object('id', '91600000-0000-0000-0000-000000000001', 'name', 'Tekken 8',
    'aliases', '[]'::jsonb, 'platforms', '["PS5"]'::jsonb) || p_extra $$ language sql;

-- ------------------------------------------------ 1. game age rating and media
select pg_temp.as_user('16000000-0000-0000-0000-000000000001');
select is(pg_temp.push('game.upsert', pg_temp.game('{"age_rating":16,"media":"disc"}'))->>'status',
  'applied', 'the owner adds a game with an age rating and media');
select results_eq(
  $$ select age_rating::int, media from games where id = '91600000-0000-0000-0000-000000000001' $$,
  $$ values (16, 'disc') $$, 'age rating and media are stored');

select is(pg_temp.push('game.upsert', pg_temp.game('{"name":"Tekken 8 Ultimate"}'))->>'status',
  'applied', 'an edit without the new fields (as the floor app sends) is applied');
select results_eq(
  $$ select name, age_rating::int, media from games where id = '91600000-0000-0000-0000-000000000001' $$,
  $$ values ('Tekken 8 Ultimate', 16, 'disc') $$, '... and keeps the stored age rating and media');

select is(pg_temp.push('game.upsert', pg_temp.game('{"age_rating":null,"media":null}'))->>'status',
  'applied', 'sending null clears them');
select results_eq(
  $$ select age_rating, media from games where id = '91600000-0000-0000-0000-000000000001' $$,
  $$ values (null::smallint, null::text) $$, '... both are cleared');

select is(pg_temp.push('game.upsert', pg_temp.game('{"age_rating":15}'))->>'status', 'rejected',
  'an age rating outside 3/7/12/16/18 is refused');
select is(pg_temp.push('game.upsert', pg_temp.game('{"media":"cartridge"}'))->>'status', 'rejected',
  'an unknown media is refused');

select is(pg_temp.push('game.upsert',
    jsonb_build_object('id', '91600000-0000-0000-0000-0000000000ff', 'name', 'Taken', 'age_rating', 18))
    ->>'error', 'not_found', 'a game of another arena cannot be edited');
select is((select age_rating from games where id = '91600000-0000-0000-0000-0000000000ff'), null::smallint,
  '... and stays unchanged');

select pg_temp.as_user('16000000-0000-0000-0000-000000000002');
select is(pg_temp.push('game.upsert', pg_temp.game('{"age_rating":3}'))->>'error', 'forbidden',
  'staff without the settings permission cannot edit a game');

-- ------------------------------------------------ 2. arena name, area and phone
select is(pg_temp.push('arena.update', '{"name":"Renamed"}')->>'error', 'forbidden',
  'staff without the settings permission cannot edit the arena');

select pg_temp.as_user('16000000-0000-0000-0000-000000000001');
select is(pg_temp.push('arena.update',
    '{"name":"  404 Arena  ","area":"Koramangala","phone":"080 4110 2209"}')->>'status', 'applied',
  'the owner sets name, area and phone');
select results_eq(
  $$ select name, area, phone from arenas where id = 'e0000000-0000-4000-8000-000000000160' $$,
  $$ values ('404 Arena', 'Koramangala', '080 4110 2209') $$, 'they are stored (name trimmed)');

select is(pg_temp.push('arena.update', '{"area":""}')->>'status', 'applied',
  'an empty area clears it, leaving the rest');
select results_eq(
  $$ select name, area, phone from arenas where id = 'e0000000-0000-4000-8000-000000000160' $$,
  $$ values ('404 Arena', null::text, '080 4110 2209') $$, '... only the area changed');

select is(pg_temp.push('arena.update', '{"name":"   "}')->>'error', 'invalid_name',
  'a blank name is refused');
select is(pg_temp.push('arena.update', '{"phone":"call me"}')->>'error', 'invalid_phone',
  'a phone with letters is refused');
select is(pg_temp.push('arena.update', jsonb_build_object('area', repeat('x', 81)))->>'error',
  'invalid_area', 'an area over 80 characters is refused');
select is((select name from arenas where id = 'e0000000-0000-4000-8000-000000000161'),
  'pgtap 16 neighbour', 'the neighbour arena is never touched');

-- ------------------------------------------------ 3. floor options (settings.save)
create function pg_temp.opts(p jsonb) returns jsonb as $$
  select pg_temp.push('settings.save', jsonb_build_object('key', 'floor_options', 'json', p)) $$
  language sql;
select is(pg_temp.opts('{"payment_methods":["upi","cash","upi"],"start_presets":[90,30,60,30],"warn_minutes":10}')
    ->>'status', 'applied', 'the owner saves floor options');
select is((select json from settings where arena_id = 'e0000000-0000-4000-8000-000000000160'
    and key = 'floor_options'),
  '{"payment_methods":["cash","upi"],"start_presets":[30,60,90],"warn_minutes":10}'::jsonb,
  'they are stored de-duplicated and sorted');
select is(pg_temp.opts('{"payment_methods":[],"start_presets":[60],"warn_minutes":5}')->>'error',
  'invalid_floor_options', 'at least one payment method is required');
select is(pg_temp.opts('{"payment_methods":["cheque"],"start_presets":[60],"warn_minutes":5}')->>'error',
  'invalid_floor_options', 'an unknown payment method is refused');
select is(pg_temp.opts('{"payment_methods":["cash"],"start_presets":[2],"warn_minutes":5}')->>'error',
  'invalid_floor_options', 'a 2-minute preset is refused');
select is(pg_temp.opts('{"payment_methods":["cash"],"start_presets":[30,45,60,90,120,150,180,240,300]
    ,"warn_minutes":5}')->>'error', 'invalid_floor_options', 'more than 8 presets is refused');
select is(pg_temp.opts('{"payment_methods":["cash"],"start_presets":[60],"warn_minutes":45}')->>'error',
  'invalid_floor_options', 'a 45-minute warning is refused');
select is(pg_temp.opts('{"payment_methods":["cash"],"start_presets":[60],"warn_minutes":5,"x":1}')->>'error',
  'invalid_floor_options', 'unknown fields are refused');
select is(pg_temp.push('settings.save', '{"key":"gst","json":{}}')->>'error', 'setting_not_shared',
  'other keys stay refused');
select is((select count(*)::int from pricing_catalog_history
    where arena_id = 'e0000000-0000-4000-8000-000000000160'), 0,
  'floor options are not part of the price list (nothing archived)');

-- ------------------------------------------------ 4. member birth year (customer.create / update)
select is(pg_temp.push('customer.create', '{"id":"c1600000-0000-0000-0000-000000000001","name":"Diya",
    "notes":"","birth_year":2009}')->>'status', 'applied', 'a member is registered with a birth year');
select is((select birth_year::int from customers where id = 'c1600000-0000-0000-0000-000000000001'), 2009,
  'the birth year is stored');
select is(pg_temp.push('customer.update', jsonb_build_object('id', 'c1600000-0000-0000-0000-000000000001',
    'base_version', (select sync_xid::text from customers where id = 'c1600000-0000-0000-0000-000000000001'),
    'name', 'Diya Menon', 'notes', ''))->>'status', 'applied',
  'an update without birth_year (older builds) is applied');
select results_eq(
  $$ select name, birth_year::int from customers where id = 'c1600000-0000-0000-0000-000000000001' $$,
  $$ values ('Diya Menon', 2009) $$, '... and keeps the birth year');
select is(pg_temp.push('customer.update', jsonb_build_object('id', 'c1600000-0000-0000-0000-000000000001',
    'base_version', (select sync_xid::text from customers where id = 'c1600000-0000-0000-0000-000000000001'),
    'name', 'Diya Menon', 'notes', '', 'birth_year', 2999))->>'error', 'invalid_birth_year',
  'a future birth year is refused');
select is(pg_temp.push('customer.create', '{"id":"c1600000-0000-0000-0000-000000000002","name":"Old",
    "notes":"","birth_year":1850}')->>'error', 'invalid_birth_year', 'a birth year before 1900 is refused');

-- ------------------------------------------------ 3. not a client function
select ok(not has_function_privilege('authenticated', 'public.op_arena_update(uuid, jsonb)', 'execute'),
  'op_arena_update is reachable only through sync_push');

select * from finish();
rollback;
