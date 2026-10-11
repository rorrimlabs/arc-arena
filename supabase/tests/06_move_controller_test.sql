-- Explicit controller moves: move_controller, the server mirror of
-- LocalControllerAllocationRepository.moveController (loan / permanent /
-- returnHome) — location + loan bookkeeping + one history row per real move.
begin;
create extension if not exists pgtap;
select * from no_plan();

-- ===================== RPC surface (as db owner) =====================
select has_function('public', 'move_controller',
  array['uuid','uuid','text','uuid','text','timestamp with time zone'], 'move_controller exists');
select ok(not has_function_privilege('anon',
    'public.move_controller(uuid,uuid,text,uuid,text,timestamptz)', 'EXECUTE'),
  'anon cannot execute move_controller');
-- Since 0012 clients move pads through the controller.move op (sync_push).
select ok(not has_function_privilege('authenticated',
    'public.move_controller(uuid,uuid,text,uuid,text,timestamptz)', 'EXECUTE'),
  'authenticated can NOT execute move_controller directly (0012)');
select is((select prosecdef from pg_proc where oid =
    'public.move_controller(uuid,uuid,text,uuid,text,timestamptz)'::regprocedure),
  true, 'move_controller is SECURITY DEFINER');

-- ===================== fixture (as db owner) =====================
-- One owner and one staff member (Drift default staff perms).
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values
  ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
    'authenticated','authenticated','owner@test.local','',now(),now(),now(),'{}','{}',false,false),
  ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222',
    'authenticated','authenticated','staff@test.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select (select id from arenas limit 1),'11111111-1111-1111-1111-111111111111','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select (select id from arenas limit 1),'22222222-2222-2222-2222-222222222222','Staff','staff',
    array['start','bill','discount','members'],true;

-- The legacy RPCs are no longer a client surface (0012 revoked EXECUTE from
-- authenticated; clients go through sync_push). They are exercised here as the
-- internal building blocks they now are: as the function owner, with the
-- caller's JWT claims, so auth.uid() and every membership/role check still run.

-- ===================== as STAFF =====================
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

-- A permanent move re-homes the pad: owner-only.
select throws_ok($$
  select move_controller((select id from arenas limit 1),
    (select id from controllers where label='VOID-1'), 'permanent',
    (select id from resources where name='RIFT')) $$,
  '42501', null, 'staff cannot make a permanent move');
select ok(
  (select home_resource_id = (select id from resources where name='VOID')
      and current_resource_id = (select id from resources where name='VOID')
   from controllers where label='VOID-1'),
  'the refused permanent move left the pad home');

-- Loan GHOST-1 to HEX: moved, owes its return, one attributed history row.
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='GHOST-1'), 'loan',
    (select id from resources where name='HEX'), 's:hex-session', '2026-10-11 10:00+00'),
  true, 'staff can loan a pad to another station');
select ok(
  (select current_resource_id = (select id from resources where name='HEX')
      and home_resource_id = (select id from resources where name='GHOST')
      and loan_return_to = (select id::text from resources where name='GHOST')
      and loan_session_ref = 's:hex-session'
   from controllers where label='GHOST-1'),
  'the loaned pad is at HEX, still homed at GHOST, owing its return to the session');
select results_eq($$
  select m.from_resource_id, m.to_resource_id, m.kind, m.session_ref, m.moved_at, m.created_by
  from controller_moves m join controllers c on c.id = m.controller_id
  where c.label = 'GHOST-1' $$,
  $$ values ((select id from resources where name='GHOST'), (select id from resources where name='HEX'),
             'loan'::text, 's:hex-session'::text, '2026-10-11 10:00+00'::timestamptz,
             '22222222-2222-2222-2222-222222222222'::uuid) $$,
  'one loan GHOST -> HEX is recorded at p_at, attributed to staff');

-- A retry of the same loan is a same-place no-op: no second history row.
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='GHOST-1'), 'loan',
    (select id from resources where name='HEX'), 's:hex-session'),
  false, 'repeating the loan reports no move');
select is((select count(*)::int from controller_moves m join controllers c on c.id = m.controller_id
            where c.label = 'GHOST-1'),
  1, 'and records no history');

-- "Returned": carry it home. p_to_resource is ignored for returnHome.
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='GHOST-1'), 'returnHome',
    (select id from resources where name='RIFT'), 's:ignored'),
  true, 'staff can return a loaned pad home');
select ok(
  (select current_resource_id = (select id from resources where name='GHOST')
      and loan_return_to is null and loan_session_ref is null
   from controllers where label='GHOST-1'),
  'the returned pad is home with its loan cleared');
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='GHOST-1'), 'returnHome'),
  false, 'returning a pad already home is a no-op');
select results_eq($$
  select m.kind, m.session_ref, m.from_resource_id, m.to_resource_id
  from controller_moves m join controllers c on c.id = m.controller_id
  where c.label = 'GHOST-1' order by m.created_at, m.kind $$,
  $$ values ('loan'::text, 's:hex-session'::text,
             (select id from resources where name='GHOST'), (select id from resources where name='HEX')),
            ('returnHome'::text, null::text,
             (select id from resources where name='HEX'), (select id from resources where name='GHOST')) $$,
  'the timeline is loan then returnHome, with no session_ref on the return');

-- A pad held by an open allocation cannot be moved — not even "returned".
select is(jsonb_array_length(
    allocate_controllers((select id from arenas limit 1), 'single',
      array[(select id from controllers where label='HEX-1')],
      (select id from resources where name='HEX'), 'PS5', now())),
  1, 'HEX-1 is in use at HEX');
select throws_ok($$
  select move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-1'), 'loan',
    (select id from resources where name='VOID'), 's:void-session') $$,
  'controller_in_use', 'a pad in use cannot be loaned away');
select throws_ok($$
  select move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-1'), 'returnHome') $$,
  'controller_in_use', 'a pad in use cannot be returned');
select is((select current_resource_id from controllers where label='HEX-1'),
  (select id from resources where name='HEX'), 'and it stays where it is');

-- Bad input.
select throws_ok($$
  select move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-2'), 'teleport',
    (select id from resources where name='VOID')) $$,
  'move_kind_invalid', 'an unknown move kind is rejected');
select throws_ok($$
  select move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-2'), 'loan') $$,
  'resource_missing', 'a loan needs a destination');
select throws_ok($$
  select move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-2'), 'loan', gen_random_uuid()) $$,
  'resource_missing', 'a loan to an unknown station is rejected');
select throws_ok($$
  select move_controller((select id from arenas limit 1), gen_random_uuid(), 'returnHome') $$,
  'controller_missing', 'an unknown pad is rejected');
select throws_ok($$
  select move_controller(gen_random_uuid(),
    (select id from controllers where label='HEX-2'), 'returnHome') $$,
  '42501', null, 'moving in an arena you are not a member of is forbidden');

-- Loan HEX-2 to RIFT, for the owner's same-place permanent move below.
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-2'), 'loan',
    (select id from resources where name='RIFT'), 's:rift-session'),
  true, 'HEX-2 is loaned to RIFT');

-- ===================== as OWNER =====================
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- Permanent move: new home and location, no loan, no session_ref in history.
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='VOID-1'), 'permanent',
    (select id from resources where name='RIFT'), 's:ignored'),
  true, 'the owner can move a pad permanently');
select ok(
  (select current_resource_id = (select id from resources where name='RIFT')
      and home_resource_id = (select id from resources where name='RIFT')
      and loan_return_to is null and loan_session_ref is null
   from controllers where label='VOID-1'),
  'the pad now lives at RIFT and owes no return');
select results_eq($$
  select m.from_resource_id, m.to_resource_id, m.kind, m.session_ref, m.created_by
  from controller_moves m join controllers c on c.id = m.controller_id
  where c.label = 'VOID-1' $$,
  $$ values ((select id from resources where name='VOID'), (select id from resources where name='RIFT'),
             'permanent'::text, null::text, '11111111-1111-1111-1111-111111111111'::uuid) $$,
  'one permanent VOID -> RIFT move is recorded, attributed to the owner');

-- Re-homing a loaned pad where it already is: no move, but the row is still
-- written (as on the device), so it is homed there and the loan is cleared.
select is(
  move_controller((select id from arenas limit 1),
    (select id from controllers where label='HEX-2'), 'permanent',
    (select id from resources where name='RIFT')),
  false, 'a permanent move to where the pad already is records no move');
select ok(
  (select home_resource_id = (select id from resources where name='RIFT')
      and current_resource_id = (select id from resources where name='RIFT')
      and loan_return_to is null and loan_session_ref is null
   from controllers where label='HEX-2'),
  'but it re-homes the pad and clears its loan');
select is((select count(*)::int from controller_moves m join controllers c on c.id = m.controller_id
            where c.label = 'HEX-2'),
  1, 'HEX-2 history is just the loan');

select set_config('request.jwt.claims','', true);
select * from finish();
rollback;
