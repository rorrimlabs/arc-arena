-- Controller location history + borrowing: the controller_moves mirror of Drift
-- v13 and the borrow step (borrow_controllers / allocate_controllers p_borrow)
-- that moves the pad, owes its return and records the move in ONE transaction.
begin;
create extension if not exists pgtap;
select * from no_plan();

-- Isolated fixture: this file works in its OWN arena (the same starter catalog
-- seed.sql uses), so whatever else is in the database — the dev seed, arenas
-- left by the two-device suite, a half-finished run — cannot change what it
-- sees. Created inside this transaction and rolled back with it.
insert into arenas(id, name) values ('e0000000-0000-4000-8000-000000000005'::uuid, 'pgtap 05');
select _seed_arena_catalog('e0000000-0000-4000-8000-000000000005'::uuid);

-- ===================== schema parity (as db owner) =====================
select has_table('public', 'controller_moves', 'controller_moves exists');
select columns_are('public', 'controller_moves', array[
  'id','arena_id','controller_id','from_resource_id','to_resource_id','kind',
  'session_ref','moved_at','created_by','created_at','sync_xid'],
  'controller_moves = Drift ControllerMoves + arena_id/created_by/sync_xid');
select col_type_is('public','controller_moves','moved_at','timestamp with time zone',
  'moved_at is timestamptz');
select col_not_null('public','controller_moves', c, c || ' is not null')
from unnest(array['controller_id','from_resource_id','to_resource_id','kind','moved_at']) as c;
select col_is_null('public','controller_moves','session_ref','session_ref is nullable');
select has_index('public', 'controller_moves', 'ix_moves_controller',
  array['controller_id','moved_at'], 'index on (controller_id, moved_at)');
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint
     where conrelid = 'public.controller_moves'::regclass and contype = 'c')
    ~ 'loan.*permanent.*returnHome',
  'kind is limited to the ControllerMoveKind codes');
select throws_ok($$
  insert into controller_moves(arena_id, controller_id, from_resource_id, to_resource_id, kind, moved_at)
  select c.arena_id, c.id, c.current_resource_id, c.home_resource_id, 'teleport', now()
  from controllers c where c.label = 'HEX-1' and c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid $$,
  '23514', null, 'an unknown move kind is rejected');

-- RLS + privileges: members read, writes only through the RPCs.
select is(
  (select relrowsecurity from pg_class where oid = 'public.controller_moves'::regclass),
  true, 'RLS is enabled on controller_moves');
select policies_are('public', 'controller_moves', array['p_sel_controller_moves'],
  'controller_moves has only the member-read policy');
select ok(has_table_privilege('authenticated', 'public.controller_moves', 'SELECT'),
  'authenticated may SELECT controller_moves (filtered by RLS)');
select ok(not has_table_privilege(r, 'public.controller_moves', p),
  r || ' has no ' || p || ' on controller_moves')
from unnest(array['authenticated','anon']) as r,
     unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) as p;
select ok(not has_table_privilege(r, 'public.controller_allocations', 'TRUNCATE'),
  r || ' cannot TRUNCATE controller_allocations')
from unnest(array['authenticated','anon']) as r;

-- RPC surface.
select has_function('public', 'borrow_controllers',
  array['uuid','uuid[]','uuid','text','timestamp with time zone'], 'borrow_controllers exists');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'allocate_controllers'),
  1, 'allocate_controllers has exactly one overload (no ambiguity)');
select ok(not has_function_privilege('anon',
    'public.borrow_controllers(uuid,uuid[],uuid,text,timestamptz)', 'EXECUTE'),
  'anon cannot execute borrow_controllers');
-- Since 0012 the pad RPCs are internal: clients borrow/allocate through
-- sync_push ops, which also tie the pads to a real session atomically.
select ok(not has_function_privilege('authenticated',
    'public.allocate_controllers(uuid,text,uuid[],uuid,text,timestamptz,uuid,uuid,uuid,uuid,int,text,uuid,text,boolean,text)',
    'EXECUTE'),
  'authenticated can NOT execute allocate_controllers directly (0012)');

-- ===================== fixture (as db owner) =====================
-- One staff member (Drift default staff perms) — borrowing is a floor action.
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222',
    'authenticated','authenticated','staff@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select 'e0000000-0000-4000-8000-000000000005'::uuid,'22222222-2222-2222-2222-222222222222','Staff','staff',
    array['start','bill','discount','members'],true;

-- RIFT-2 is out of service.
update controllers set status = 'faulty' where label = 'RIFT-2';

-- VOID runs a count-only PS5 session (open segment, no tracked pad): its pads
-- may be in players' hands.
insert into customers(id,arena_id,name) values
  ('cccccccc-0000-0000-0000-000000000005','e0000000-0000-4000-8000-000000000005'::uuid,'Count-only walk-in');
insert into sessions(id,arena_id,customer_id,started_at,scheduled_end_at,pricing_snapshot,policy_snapshot)
  values ('55555555-0000-0000-0000-000000000001','e0000000-0000-4000-8000-000000000005'::uuid,
    'cccccccc-0000-0000-0000-000000000005',now(),now() + interval '1 hour','{}','{}');
insert into session_segments(arena_id,session_id,idx,resource_id,activity_code,controller_count,started_at)
  values ('e0000000-0000-4000-8000-000000000005'::uuid,'55555555-0000-0000-0000-000000000001',0,
    (select id from resources where name='VOID' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),'PS5',2,now());

-- The legacy RPCs are no longer a client surface (0012 revoked EXECUTE from
-- authenticated; clients go through sync_push). They are exercised here as the
-- internal building blocks they now are: as the function owner, with the
-- caller's JWT claims, so auth.uid() and every membership/role check still run.
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

-- ===================== as STAFF =====================
-- History is RPC-only (a table privilege, so asserted on the grant).
select ok(not has_table_privilege('authenticated', 'public.controller_moves', 'INSERT'),
  'staff cannot write controller_moves directly');

-- Without p_borrow, a pad elsewhere is still refused (0007 behaviour unchanged).
select throws_ok($$
  select allocate_controllers('e0000000-0000-4000-8000-000000000005'::uuid, 'single',
    array[(select id from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'PS5', now()) $$,
  'controller_elsewhere', 'without p_borrow a pad at another station is rejected');

-- Borrow GHOST-1 into a HEX session: moved, owes its return, history row, held.
select is(jsonb_array_length(
    allocate_controllers('e0000000-0000-4000-8000-000000000005'::uuid, 'single',
      array[(select id from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
      (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'PS5', now(),
      p_borrow => true, p_session_ref => 's:hex-session')),
  1, 'allocate_controllers with p_borrow reserves the borrowed pad');
select is((select current_resource_id from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
  (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'the borrowed pad is now at HEX');
select is((select loan_return_to from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
  (select id::text from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'it owes a return to GHOST (its home)');
select is((select loan_session_ref from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
  's:hex-session', 'the borrowing session owes the return');
select results_eq($$
  select m.from_resource_id, m.to_resource_id, m.kind, m.session_ref, m.created_by
  from controller_moves m join controllers c on c.id = m.controller_id
  where c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid and c.label = 'GHOST-1' $$,
  $$ values ((select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
             'loan'::text, 's:hex-session'::text, '22222222-2222-2222-2222-222222222222'::uuid) $$,
  'one loan move GHOST -> HEX is recorded, readable by staff, attributed to them');
select is((select resource_id from controller_allocations a join controllers c on c.id = a.controller_id
            where c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid and c.label = 'GHOST-1' and a.ended_at is null),
  (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'the open allocation is at HEX');

-- A pad held by an open allocation cannot be borrowed away.
select is(jsonb_array_length(
    allocate_controllers('e0000000-0000-4000-8000-000000000005'::uuid, 'single',
      array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
      (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'PS5', now())),
  1, 'HEX-1 is in use at HEX');
select throws_ok($$
  select borrow_controllers('e0000000-0000-4000-8000-000000000005'::uuid,
    array[(select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 's:ghost-session', now()) $$,
  'controller_taken', 'a pad in use cannot be borrowed');

-- Atomic: a refused pad later in the list undoes the earlier borrow.
select throws_ok($$
  select allocate_controllers('e0000000-0000-4000-8000-000000000005'::uuid, 'single',
    array[(select id from controllers where label='GHOST-2' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
          (select id from controllers where label='HEX-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='RIFT' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'PS5', now(),
    p_borrow => true, p_session_ref => 's:rift-session') $$,
  'controller_taken', 'a borrow that hits a busy pad is refused');
select is((select current_resource_id from controllers where label='GHOST-2' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
  (select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'the earlier pad in the refused call stayed home');
select is((select count(*)::int from controller_moves m join controllers c on c.id = m.controller_id
            where c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid and c.label = 'GHOST-2'),
  0, 'the refused call left no move history');

-- Unusable pads are refused.
select throws_ok($$
  select borrow_controllers('e0000000-0000-4000-8000-000000000005'::uuid,
    array[(select id from controllers where label='RIFT-2' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 's:hex-session', now()) $$,
  'controller_unusable', 'a faulty pad cannot be borrowed');

-- A pad at a station running a count-only (untracked) session is refused.
select throws_ok($$
  select borrow_controllers('e0000000-0000-4000-8000-000000000005'::uuid,
    array[(select id from controllers where label='VOID-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 's:hex-session', now()) $$,
  'controller_taken', 'a pad at a station with an untracked open session cannot be borrowed');
select is((select current_resource_id from controllers where label='VOID-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
  (select id from resources where name='VOID' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'and it stays where it is');

-- Idempotency: a repeated request_id neither re-borrows nor re-allocates.
select is(
  allocate_controllers('e0000000-0000-4000-8000-000000000005'::uuid, 'single',
    array[(select id from controllers where label='RIFT-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'PS5', now(), p_request_id => 'req-borrow',
    p_borrow => true, p_session_ref => 's:hex-session'),
  allocate_controllers('e0000000-0000-4000-8000-000000000005'::uuid, 'single',
    array[(select id from controllers where label='RIFT-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 'PS5', now(), p_request_id => 'req-borrow',
    p_borrow => true, p_session_ref => 's:hex-session'),
  'a repeated borrow request_id returns the same allocation');
select is((select count(*)::int from controller_moves m join controllers c on c.id = m.controller_id
            where c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid and c.label = 'RIFT-1'),
  1, 'the idempotent retry recorded only one move');

-- A pad already at the station is not "moved".
select is(
  borrow_controllers('e0000000-0000-4000-8000-000000000005'::uuid,
    array[(select id from controllers where label='HEX-2' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='HEX' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 's:hex-session', now()),
  0, 'borrowing a pad already at the station is a no-op');
select is((select count(*)::int from controller_moves m join controllers c on c.id = m.controller_id
            where c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid and c.label = 'HEX-2'),
  0, 'and records no move');

-- Carrying a pad back to its home station clears the loan (kind returnHome).
select is(release_controllers('e0000000-0000-4000-8000-000000000005'::uuid,
    array[(select id from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)], now()),
  1, 'the HEX session releases GHOST-1');
select is(
  borrow_controllers('e0000000-0000-4000-8000-000000000005'::uuid,
    array[(select id from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), 's:ghost-session', now()),
  1, 'GHOST-1 is borrowed back to GHOST');
select ok(
  (select loan_return_to is null and loan_session_ref is null
     and current_resource_id = (select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)
   from controllers where label='GHOST-1' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid),
  'arriving home clears loan_return_to / loan_session_ref');
select results_eq($$
  select m.kind, m.session_ref from controller_moves m join controllers c on c.id = m.controller_id
  where c.arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid and c.label = 'GHOST-1' order by m.created_at, m.kind $$,
  $$ values ('loan'::text, 's:hex-session'::text), ('returnHome'::text, null::text) $$,
  'the timeline is loan then returnHome (append-only)');

-- Another arena is forbidden.
select throws_ok($$
  select borrow_controllers(gen_random_uuid(),
    array[(select id from controllers where label='HEX-2' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid)],
    (select id from resources where name='GHOST' and arena_id = 'e0000000-0000-4000-8000-000000000005'::uuid), null, now()) $$,
  '42501', null, 'borrowing in an arena you are not a member of is forbidden');

select set_config('request.jwt.claims','', true);
select * from finish();
rollback;
