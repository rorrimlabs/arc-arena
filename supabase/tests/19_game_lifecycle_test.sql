-- Game lifecycle: create and edit (game.upsert: name rules), archive and restore
-- (game.set_active), and permanent delete (game.delete) only for a game nothing ever used.
-- A game in play or with history is refused and can be archived instead; history keeps it.
-- Retries are idempotent, a deleted game never comes back, an edit over a newer archive is
-- refused, and nothing crosses arenas.
--
-- Thu 2026-10-01, 13:30 IST = 08:00Z (standard band).
begin;
create extension if not exists pgtap;
select * from no_plan();

insert into arenas(id, name) values
  ('e0000000-0000-4000-8000-000000000190'::uuid, 'pgtap 19'),
  ('e0000000-0000-4000-8000-000000000191'::uuid, 'pgtap 19 neighbour');
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
      ('19000000-0000-0000-0000-000000000001', 'owner19@test.local'),
      ('19000000-0000-0000-0000-000000000002', 'staff19@test.local'),
      ('19000000-0000-0000-0000-000000000003', 'neighbour19@test.local')) u(id, email)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active) values
  ('e0000000-0000-4000-8000-000000000190','19000000-0000-0000-0000-000000000001','Owner','owner',
    _known_perms(), true),
  ('e0000000-0000-4000-8000-000000000190','19000000-0000-0000-0000-000000000002','Staff','staff',
    array['start','bill','members'], true),
  ('e0000000-0000-4000-8000-000000000191','19000000-0000-0000-0000-000000000003','Owner B','owner',
    _known_perms(), true);
insert into games(id, arena_id, name)
  values ('d1900000-0000-0000-0000-0000000000ff', 'e0000000-0000-4000-8000-000000000191', 'Elsewhere');

create function pg_temp.as_user(p_uid text) returns void as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$ language sql;
create function pg_temp.push_as(p_op uuid, p_kind text, p jsonb) returns jsonb as $$
  select sync_push('e0000000-0000-4000-8000-000000000190'::uuid,
    jsonb_build_array(jsonb_build_object('op_id', p_op, 'kind', p_kind, 'payload', p)),
    'pgtap') -> 'results' -> 0 $$ language sql;
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $$
  select pg_temp.push_as(gen_random_uuid(), p_kind, p) $$ language sql;
create function pg_temp.game(p_id text, p_name text, p_extra jsonb default '{}') returns jsonb as $$
  select jsonb_build_object('id', p_id, 'name', p_name, 'aliases', '[]'::jsonb,
    'platforms', '["PS5"]'::jsonb, 'play_modes', '["local"]'::jsonb, 'max_local_players', 2) || p_extra $$
  language sql;
create function pg_temp.compat(p_game text, p_status text default 'playable') returns jsonb as $$
  select jsonb_build_object('game_id', p_game, 'resource_id', 'b1900000-0000-0000-0000-000000000001',
    'status', p_status) $$ language sql;
create function pg_temp.start(p_id text, p_seg text, p_game text, p_at text, p_end text)
  returns jsonb as $$
  select pg_temp.push('session.start', jsonb_build_object(
    'id', p_id, 'segment_id', p_seg, 'customer_id', 'cccccccc-0000-0000-0000-000000000019',
    'started_at', p_at, 'scheduled_end_at', p_end,
    'pricing_snapshot', _pricing_snapshot('e0000000-0000-4000-8000-000000000190'::uuid),
    'resource_id', 'b1900000-0000-0000-0000-000000000001', 'activity_code', 'PS5',
    'game_id', p_game, 'controller_count', 1,
    'allocations', jsonb_build_array(jsonb_build_object('controller_id', 'c1900000-0000-0000-0000-000000000001')),
    'moves', '[]'::jsonb)) $$ language sql;

-- Ids: TEKKEN is played, SPARE is never used, BOOKED only has a booking.
-- TEKKEN d19…01, SPARE d19…02, BOOKED d19…03.

-- ------------------------------------------------ 1. the catalog the owner builds
select pg_temp.as_user('19000000-0000-0000-0000-000000000001');
select is(pg_temp.push('activity.upsert', jsonb_build_object('id', 'a1900000-0000-0000-0000-000000000001',
    'code', 'PS5', 'name', 'PS5', 'uses_controllers', true, 'uses_games', true,
    'duration_model', 'hourly'))->>'status', 'applied', 'a PS5 station type');
select is(pg_temp.push('rate.upsert', jsonb_build_object('activity_code', 'PS5', 'band', 'standard',
    'controller_count', 1, 'unit_minutes', 60, 'price_paise', 10000))->>'status', 'applied', 'its price');
select is(pg_temp.push('resource.upsert', jsonb_build_object('id', 'b1900000-0000-0000-0000-000000000001',
    'name', 'HEX', 'kind', 'station', 'activity_codes', jsonb_build_array('PS5')))->>'status', 'applied',
  'station HEX');
select is(pg_temp.push('controller.upsert', jsonb_build_object('id', 'c1900000-0000-0000-0000-000000000001',
    'label', 'HEX-1', 'home_resource_id', 'b1900000-0000-0000-0000-000000000001',
    'current_resource_id', 'b1900000-0000-0000-0000-000000000001'))->>'status', 'applied', 'pad HEX-1');

-- ------------------------------------------------ 2. create and edit: name rules
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000001', '  Tekken 8  '))
    ->>'status', 'applied', 'the owner adds a game');
select is((select name from games where id = 'd1900000-0000-0000-0000-000000000001'), 'Tekken 8',
  'its name is stored trimmed');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', 'TEKKEN 8'))
    ->>'error', 'duplicate', 'a second game with the same name in another case is refused');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', '   '))
    ->>'error', 'invalid_name', 'a blank name is refused');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', repeat('x', 81)))
    ->>'error', 'invalid_name', 'a name over 80 characters is refused');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', 'Elsewhere'))
    ->>'status', 'applied', 'a name another arena uses is fine');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', 'Spare Title',
    '{"max_local_players":4,"play_modes":["local","online"]}'))->>'status', 'applied', 'the owner renames and edits it');
select results_eq(
  $$ select name, max_local_players, play_modes from games where id = 'd1900000-0000-0000-0000-000000000002' $$,
  $$ values ('Spare Title', 4, array['local', 'online']) $$, 'the edit is stored');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', 'Spare Title',
    '{"max_local_players":9}'))->>'error', 'invalid', 'more than 8 players is refused');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000003', 'Booked Game'))
    ->>'status', 'applied', 'a third game');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-0000000000ff', 'Taken'))
    ->>'error', 'not_found', 'another arena''s game cannot be edited');

select is(pg_temp.push('game.set_compat', pg_temp.compat('d1900000-0000-0000-0000-000000000001'))->>'status',
  'applied', 'Tekken is playable on HEX');
select is(pg_temp.push('game.set_compat', pg_temp.compat('d1900000-0000-0000-0000-000000000002')
    || '{"notes":"disc in drawer"}')->>'status', 'applied', 'Spare is playable on HEX, with a note');
select is(pg_temp.push('game.set_compat', pg_temp.compat('d1900000-0000-0000-0000-000000000002'))->>'status',
  'applied', 'a status change without a notes key (the dashboard) ...');
select is((select notes from game_resources where game_id = 'd1900000-0000-0000-0000-000000000002'),
  'disc in drawer', '... keeps the note staff wrote');
select is(pg_temp.push('game.replace_controls', jsonb_build_object('game_id', 'd1900000-0000-0000-0000-000000000002',
    'controls', jsonb_build_array(jsonb_build_object('id', 'f1900000-0000-0000-0000-0000000000c1',
      'section', 'Basics', 'action', 'Jump', 'buttons', jsonb_build_array('X')))))->>'status', 'applied',
  'Spare has a control guide');

select pg_temp.as_user('19000000-0000-0000-0000-000000000002');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000004', 'Staff Game'))
    ->>'error', 'forbidden', 'staff without the settings permission cannot add a game');
select is(pg_temp.push('game.set_active', '{"id":"d1900000-0000-0000-0000-000000000002","active":false}')
    ->>'error', 'forbidden', '... nor archive one');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000002"}')->>'error', 'forbidden',
  '... nor delete one');
select ok(exists(select 1 from games where id = 'd1900000-0000-0000-0000-000000000002' and active),
  'and the game is untouched');

-- ------------------------------------------------ 3. a game in play
select is(pg_temp.push('customer.create', jsonb_build_object('id', 'cccccccc-0000-0000-0000-000000000019',
    'name', 'Kiran', 'phone', '9800001919', 'is_guest', false))->>'status', 'applied', 'a customer');
select is(pg_temp.start('f1900000-0000-0000-0000-000000000001', 'f1900000-0000-0000-0000-000000000002',
    'd1900000-0000-0000-0000-000000000001', '2026-10-01T08:00:00Z', '2026-10-01T09:00:00Z')->>'status',
  'applied', 'staff start a session on Tekken');
select is(pg_temp.push('booking.create', jsonb_build_object('id', 'b0019000-0000-0000-0000-000000000001',
    'activity_code', 'PS5', 'game_id', 'd1900000-0000-0000-0000-000000000003',
    'scheduled_start', '2026-11-01T08:00:00Z', 'scheduled_end', '2026-11-01T09:00:00Z',
    'party_name', 'Asha'))->>'status', 'applied', 'and book Booked Game for next month');

select pg_temp.as_user('19000000-0000-0000-0000-000000000001');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000001"}')->>'error',
  'game_in_play', 'a game a station is playing now cannot be deleted');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000001"}')->>'detail', '1',
  '... and says how many stations play it');
select is(pg_temp.push('game.set_active', '{"id":"d1900000-0000-0000-0000-000000000001","active":false}')
    ->>'status', 'applied', 'it can be archived while it is played');
select ok(exists(select 1 from session_segments where id = 'f1900000-0000-0000-0000-000000000002'
    and ended_at is null and game_id = 'd1900000-0000-0000-0000-000000000001'),
  'the running session keeps its game');

create temp table xid_before as
  select sync_xid from games where id = 'd1900000-0000-0000-0000-000000000001';
select is(pg_temp.push('game.set_active', '{"id":"d1900000-0000-0000-0000-000000000001","active":false}')
    ->>'status', 'applied', 'archiving it again is accepted ...');
select is((select sync_xid from games where id = 'd1900000-0000-0000-0000-000000000001'),
  (select sync_xid from xid_before), '... and writes nothing (no change for devices to pull)');
select is(pg_temp.push('game.set_active', '{"id":"d1900000-0000-0000-0000-000000000001"}')->>'error',
  'invalid_payload', 'a set_active without the flag is refused');

-- ------------------------------------------------ 4. edits over an archive
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000001', 'Tekken 8',
    '{"active":true,"base_active":true}'))->>'error', 'stale',
  'an edit made while the game still showed as available does not restore it');
select ok(not (select active from games where id = 'd1900000-0000-0000-0000-000000000001'),
  '... it stays archived');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000001', 'Tekken 8',
    '{"active":false,"base_active":false}'))->>'status', 'applied', 'an edit that saw the archive is applied');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000001', 'Tekken 8 Ultimate'))
    ->>'status', 'applied', 'an edit without the active key (rename only) is applied ...');
select ok(not (select active from games where id = 'd1900000-0000-0000-0000-000000000001'),
  '... and keeps it archived');

-- ------------------------------------------------ 5. history keeps a game
select is(pg_temp.push('session.void', jsonb_build_object('session_id', 'f1900000-0000-0000-0000-000000000001',
    'reason', 'test', 'at', '2026-10-01T08:30:00Z'))->>'status', 'applied', 'the owner voids the session');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000001"}')->>'error',
  'game_has_history', 'a game a past session used cannot be deleted');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000001"}')->>'detail',
  'sessions', '... and says why');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000003"}')->>'error',
  'game_has_history', 'a game only a booking names cannot be deleted either');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000003"}')->>'detail',
  'bookings', '... the booking keeps its game');
select is((select game_id from bookings where id = 'b0019000-0000-0000-0000-000000000001'),
  'd1900000-0000-0000-0000-000000000003'::uuid, 'the booking still names the game');
select results_eq(
  $$ select g.name from session_segments s join games g on g.id = s.game_id
      where s.id = 'f1900000-0000-0000-0000-000000000002' $$,
  $$ values ('Tekken 8 Ultimate') $$, 'the past session still shows the archived game');
select throws_ok(
  $$ delete from games where id = 'd1900000-0000-0000-0000-000000000001' $$, '23503', null,
  'even a direct delete of a used game is stopped by the foreign key');

-- An offline device may start a session on a game archived meanwhile; the server keeps it.
select pg_temp.as_user('19000000-0000-0000-0000-000000000002');
select is(pg_temp.start('f1900000-0000-0000-0000-000000000003', 'f1900000-0000-0000-0000-000000000004',
    'd1900000-0000-0000-0000-000000000001', '2026-10-01T09:00:00Z', '2026-10-01T10:00:00Z')->>'status',
  'applied', 'a start on an archived (still playable) game from a device that had not heard is kept');
select pg_temp.as_user('19000000-0000-0000-0000-000000000001');
select is(pg_temp.push('session.void', jsonb_build_object('session_id', 'f1900000-0000-0000-0000-000000000003',
    'reason', 'test', 'at', '2026-10-01T09:10:00Z'))->>'status', 'applied', '(voided again)');
select is(pg_temp.push('game.set_active', '{"id":"d1900000-0000-0000-0000-000000000001","active":true}')
    ->>'status', 'applied', 'an archived game can be restored');
select ok((select active from games where id = 'd1900000-0000-0000-0000-000000000001'), '... it is available again');

-- ------------------------------------------------ 6. deleting an unused game
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-0000000000ff"}')->>'error', 'not_found',
  'another arena''s game cannot be deleted');
select ok(exists(select 1 from games where id = 'd1900000-0000-0000-0000-0000000000ff'), '... it is still there');
select is(pg_temp.push('game.delete', '{}')->>'error', 'invalid_payload', 'a delete without an id is refused');

select is(pg_temp.push_as('f1900000-0000-0000-0000-0000000000d1', 'game.delete',
    '{"id":"d1900000-0000-0000-0000-000000000002"}')->'result', '{"deleted": true}'::jsonb,
  'a game nothing ever used is deleted');
select is((select count(*)::int from games where id = 'd1900000-0000-0000-0000-000000000002')
        + (select count(*)::int from game_resources where game_id = 'd1900000-0000-0000-0000-000000000002')
        + (select count(*)::int from game_controls where game_id = 'd1900000-0000-0000-0000-000000000002'), 0,
  'with its station statuses and control guide');
select is((select array_agg(distinct table_name order by table_name) from sync_tombstones
    where arena_id = 'e0000000-0000-4000-8000-000000000190'
      and (row_key->>'id' = 'd1900000-0000-0000-0000-000000000002'
           or row_key->>'game_id' = 'd1900000-0000-0000-0000-000000000002')),
  array['game_controls', 'game_resources', 'games']::text[], 'devices are told all three are gone');
select is(pg_temp.push_as('f1900000-0000-0000-0000-0000000000d1', 'game.delete',
    '{"id":"d1900000-0000-0000-0000-000000000002"}')->>'replayed', 'true',
  'a retried delete (same op id) replays its first answer');
select is(pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000002"}')->'result',
  '{"deleted": true}'::jsonb, 'a second delete of a gone game is a no-op');

-- ------------------------------------------------ 7. a deleted game stays deleted
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000002', 'Spare Title'))
    ->>'error', 'not_found', 'an edit queued before the delete does not bring the game back');
select is(pg_temp.push('game.set_active', '{"id":"d1900000-0000-0000-0000-000000000002","active":true}')
    ->>'error', 'not_found', 'nor does a restore');
select is(pg_temp.push('game.set_compat', pg_temp.compat('d1900000-0000-0000-0000-000000000002'))->>'error',
  'missing_reference', 'nor a station status');
select is((select count(*)::int from games where id = 'd1900000-0000-0000-0000-000000000002'), 0,
  'the game is still gone');
select pg_temp.as_user('19000000-0000-0000-0000-000000000002');
select is(pg_temp.start('f1900000-0000-0000-0000-000000000005', 'f1900000-0000-0000-0000-000000000006',
    'd1900000-0000-0000-0000-000000000002', '2026-10-01T10:00:00Z', '2026-10-01T11:00:00Z')->>'error',
  'not_playable', 'a session cannot start on a deleted game');
select pg_temp.as_user('19000000-0000-0000-0000-000000000001');
select is(pg_temp.push('game.upsert', pg_temp.game('d1900000-0000-0000-0000-000000000005', 'Spare Title'))
    ->>'status', 'applied', 'its name is free again for a new game');

-- ------------------------------------------------ 8. other arenas, other people
select pg_temp.as_user('19000000-0000-0000-0000-000000000003');
select throws_ok($$ select pg_temp.push('game.delete', '{"id":"d1900000-0000-0000-0000-000000000003"}') $$,
  '42501', 'forbidden', 'an owner of another arena cannot push to this one');
select ok(exists(select 1 from games where id = 'd1900000-0000-0000-0000-000000000003'),
  'and the game is untouched');

select * from finish();
rollback;
