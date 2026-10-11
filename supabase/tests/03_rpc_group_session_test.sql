-- Group-session RPCs: create, idempotency, cross-group exclusion, and the
-- richer co-location legality the trigger alone cannot express.
begin;
create extension if not exists pgtap;
select * from no_plan();

-- Isolated fixture: this file works in its OWN arena (the same starter catalog
-- seed.sql uses), so whatever else is in the database — the dev seed, arenas
-- left by the two-device suite, a half-finished run — cannot change what it
-- sees. Created inside this transaction and rolled back with it.
insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000003'::uuid, 'pgtap 03');
select _seed_arena_catalog('e0000000-0000-4000-8000-000000000003'::uuid);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,
    email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
      'authenticated','authenticated','owner@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select 'e0000000-0000-4000-8000-000000000003'::uuid,'11111111-1111-1111-1111-111111111111','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true;
insert into customers(id,arena_id,name) values
  ('cccccccc-0000-0000-0000-000000000001','e0000000-0000-4000-8000-000000000003'::uuid,'Group Host');
-- 4 usable controllers at HEX so co-location capacity can be satisfied there;
-- GHOST deliberately has none (to exercise the usable-pads rule).
insert into controllers(arena_id,label,home_resource_id,current_resource_id,status)
  select 'e0000000-0000-4000-8000-000000000003'::uuid, 'Pad '||g, (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid), 'usable'
  from generate_series(1,4) g;

-- The legacy RPCs are no longer a client surface (0012 revoked EXECUTE from
-- authenticated; clients go through sync_push). They are exercised here as the
-- internal building blocks they now are: as the function owner, with the
-- caller's JWT claims, so auth.uid() and every membership/role check still run.
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- create_group with two players on two different stations.
select is(
  create_group('e0000000-0000-4000-8000-000000000003'::uuid, jsonb_build_object(
    'id','11110000-0000-0000-0000-000000000001','primary_customer_id','cccccccc-0000-0000-0000-000000000001',
    'player_count',2,'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot', jsonb_build_object('policy','{}'::jsonb), 'billing_mode','per_system',
    'assignments', jsonb_build_array(
      jsonb_build_object('id','a1110000-0000-0000-0000-000000000001','player_number',1,'idx',0,
        'resource_id',(select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'activity_code','PS5','controller_count',2),
      jsonb_build_object('id','a1110000-0000-0000-0000-000000000002','player_number',2,'idx',0,
        'resource_id',(select id from resources where name='VOID' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'activity_code','PS5','controller_count',2))),
    'req-grp-1')::text,
  '11110000-0000-0000-0000-000000000001', 'create_group returns the client id');
select is((select count(*)::int from group_assignments
  where group_id='11110000-0000-0000-0000-000000000001' and ended_at is null), 2,
  'two open assignments after create_group');

-- Idempotent create_group.
select is(
  create_group('e0000000-0000-4000-8000-000000000003'::uuid, jsonb_build_object(
    'id','11110000-0000-0000-0000-000000000099','primary_customer_id','cccccccc-0000-0000-0000-000000000001',
    'player_count',1,'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,
    'assignments', jsonb_build_array(jsonb_build_object('player_number',1,'idx',0,
      'resource_id',(select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'activity_code','PS5'))),
    'req-grp-1')::text,
  '11110000-0000-0000-0000-000000000001', 'duplicate request_id returns the first group');

-- Cross-group exclusion: another group cannot take HEX (held by group 1).
select throws_ok($$
  select create_group('e0000000-0000-4000-8000-000000000003'::uuid, jsonb_build_object(
    'id','11110000-0000-0000-0000-000000000002','primary_customer_id','cccccccc-0000-0000-0000-000000000001',
    'player_count',1,'started_at','2026-10-01T09:10:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,
    'assignments', jsonb_build_array(jsonb_build_object('player_number',1,'idx',0,
      'resource_id',(select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'activity_code','PS5'))), 'req-grp-2') $$,
  'resource_busy', 'a different group cannot co-locate on an occupied station');

-- Co-location ALLOWED: a third player shares HEX with player 1 (same PS5, same
-- null game, summed controllers 2+2=4 <= 4, and 4 usable pads).
select isnt(add_assignment('11110000-0000-0000-0000-000000000001','2026-10-01T09:15:00Z',
  3, 'P3', (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'PS5', null, 2,
  'a1110000-0000-0000-0000-000000000003','req-add-3')::text, null,
  'co-location allowed within capacity and pads');

-- capacity_exceeded: a fourth controller on HEX pushes the sum past 4.
select throws_ok($$
  select add_assignment('11110000-0000-0000-0000-000000000001','2026-10-01T09:16:00Z',
    4,'P4',(select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'PS5',null,1,null,'req-add-4') $$,
  'capacity_exceeded', 'co-location beyond 4 controllers is rejected');

-- not_enough_pads: co-locate on GHOST (which has zero usable controllers).
select isnt(create_group('e0000000-0000-4000-8000-000000000003'::uuid, jsonb_build_object(
    'id','11110000-0000-0000-0000-000000000003','primary_customer_id','cccccccc-0000-0000-0000-000000000001',
    'player_count',1,'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,
    'assignments', jsonb_build_array(jsonb_build_object('id','a3330000-0000-0000-0000-000000000001',
      'player_number',1,'idx',0,'resource_id',(select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),
      'activity_code','PS5','controller_count',2))), 'req-grp-3')::text, null,
  'sole assignment on a pad-less station is allowed (pads only matter for sharing)');
select throws_ok($$
  select add_assignment('11110000-0000-0000-0000-000000000003','2026-10-01T09:20:00Z',
    2,'P2',(select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'PS5',null,2,null,'req-add-ghost') $$,
  'not_enough_pads', 'co-location without enough usable pads is rejected');

-- colocation_not_allowed: a non-controller activity cannot share a station.
select isnt(create_group('e0000000-0000-4000-8000-000000000003'::uuid, jsonb_build_object(
    'id','11110000-0000-0000-0000-000000000004','primary_customer_id','cccccccc-0000-0000-0000-000000000001',
    'player_count',1,'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot','{}'::jsonb,
    'assignments', jsonb_build_array(jsonb_build_object('player_number',1,'idx',0,
      'resource_id',(select id from resources where name='Pool Table 1' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'activity_code','POOL'))),
    'req-grp-4')::text, null, 'a pool group starts');
select throws_ok($$
  select add_assignment('11110000-0000-0000-0000-000000000004','2026-10-01T09:25:00Z',
    2,'P2',(select id from resources where name='Pool Table 1' and arena_id = 'e0000000-0000-4000-8000-000000000003'::uuid),'POOL',null,null,null,'req-add-pool') $$,
  'colocation_not_allowed', 'a non-controller activity cannot be co-located');

-- end_group closes all assignments and records the bill.
select is((end_group('11110000-0000-0000-0000-000000000001','2026-10-01T10:00:00Z',
  jsonb_build_array(jsonb_build_object('charge_index',0,'band_code','standard','activity_code','PS5',
    'segment_start','2026-10-01T09:00:00Z','segment_end','2026-10-01T10:00:00Z',
    'played_minutes',60,'billed_minutes',60,'unit_minutes',60,'unit_price_paise',28000,'amount_paise',56000)),
  56000, false))->>'status', 'completed', 'end_group completes the group');
select is((select count(*)::int from group_assignments
  where group_id='11110000-0000-0000-0000-000000000001' and ended_at is null), 0,
  'all assignments closed at end_group');

-- record_group_payment + idempotency.
select isnt(record_group_payment('11110000-0000-0000-0000-000000000001', 56000, 'cash',
  false, null, null, 'req-gpay-1')::text, null, 'group payment recorded');
select is(record_group_payment('11110000-0000-0000-0000-000000000001', 56000, 'cash',
  false, null, null, 'req-gpay-1')::text,
  (select id::text from group_payments where request_id='req-gpay-1'),
  'duplicate group payment request_id returns the same row');
select is((select payment_status from group_sessions where id='11110000-0000-0000-0000-000000000001'),
  'paid', 'group payment_status -> paid');

-- void_group (owner) is idempotent.
select void_group('11110000-0000-0000-0000-000000000003','test');
select is((select status from group_sessions where id='11110000-0000-0000-0000-000000000003'),
  'voided', 'void_group sets status voided');
select lives_ok($$ select void_group('11110000-0000-0000-0000-000000000003','again') $$,
  'void_group is idempotent');

select set_config('request.jwt.claims','', true);
select * from finish();
rollback;
