-- Local development seed: one demo arena with logins, the 404 Arena catalog, customers, a week of
-- paid bills, two sessions running now and upcoming bookings. Loaded by `supabase db reset`
-- (config.toml [db.seed]). LOCAL ONLY: never run it against a hosted project.
--
-- Logins (password for both: password123):
--   owner@arena.test  Demo Owner, owner (admin dashboard and floor app)
--   staff@arena.test  Demo Staff, floor staff (start, bill, discount, members)
--
-- Bills are written through sync_push, the apps' only write path, so the server checks and prices
-- them exactly as it does the floor app's (charges come from the server's own _pr_quote). Times are
-- relative to the moment of the reset, in IST. The pgTAP suites build their own fixtures.

-- ------------------------------------------------------------------------------------ logins
insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
         extensions.crypt('password123', extensions.gen_salt('bf')), now(), now(), now(),
         '{"provider": "email", "providers": ["email"]}', jsonb_build_object('name', u.name),
         false, false, '', '', '', ''
    from (values
      ('5eed0000-0000-4000-8000-000000000001'::uuid, 'owner@arena.test', 'Demo Owner'),
      ('5eed0000-0000-4000-8000-000000000002'::uuid, 'staff@arena.test', 'Demo Staff')
    ) u(id, email, name);

insert into auth.identities(id, provider_id, user_id, identity_data, provider, last_sign_in_at,
    created_at, updated_at)
  select gen_random_uuid(), u.id::text, u.id,
         jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
         'email', now(), now(), now()
    from auth.users u
   where u.id in ('5eed0000-0000-4000-8000-000000000001', '5eed0000-0000-4000-8000-000000000002');

-- ------------------------------------------------------------------------------------ helpers
-- One op through sync_push as the current login; stops the seed on any refusal.
create function pg_temp.seed_push(p_arena uuid, p_kind text, p jsonb) returns void
language plpgsql as $$
declare v_res jsonb;
begin
  v_res := sync_push(p_arena, jsonb_build_array(jsonb_build_object(
      'op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)), 'seed') -> 'results' -> 0;
  if v_res->>'status' is distinct from 'applied' then
    raise exception 'seed: % refused: %', p_kind, v_res;
  end if;
end $$;

-- A single session on a station from p_start for p_minutes; ended and billed unless p_running.
-- The charges and the total are the server's own quote on the frozen price list.
create function pg_temp.seed_session(p_arena uuid, p_customer uuid, p_station text, p_act text,
    p_pads int, p_start timestamptz, p_minutes int, p_running boolean default false) returns uuid
language plpgsql as $$
declare
  v_id uuid := gen_random_uuid(); v_seg uuid := gen_random_uuid(); v_res uuid;
  v_end timestamptz := p_start + make_interval(mins => p_minutes);
  v_snap jsonb := _pricing_snapshot(p_arena); q jsonb; v_charges jsonb;
begin
  select id into v_res from resources where arena_id = p_arena and name = p_station;
  perform pg_temp.seed_push(p_arena, 'session.start', jsonb_build_object('id', v_id,
    'segment_id', v_seg, 'customer_id', p_customer, 'started_at', p_start,
    'scheduled_end_at', v_end, 'pricing_snapshot', v_snap, 'resource_id', v_res,
    'activity_code', p_act, 'game_id', null, 'controller_count', p_pads,
    'allocations', '[]'::jsonb, 'moves', '[]'::jsonb));
  if p_running then return v_id; end if;
  q := _pr_quote(v_snap, p_act, p_pads, p_start, v_end, p_start);
  select coalesce(jsonb_agg(jsonb_build_object('id', gen_random_uuid(), 'segment_id', v_seg,
      'segment_index', n - 1, 'band_code', l->>'band', 'activity_code', p_act,
      'resource_id', v_res, 'controller_count', p_pads, 'segment_start', l->>'start',
      'segment_end', l->>'end', 'played_minutes', (l->>'played_seconds')::bigint / 60,
      'billed_minutes', (l->>'billed_minutes')::bigint, 'unit_minutes', (l->>'unit_minutes')::int,
      'unit_price_paise', (l->>'unit_price')::bigint, 'amount_paise', (l->>'amount')::bigint)
      order by n), '[]'::jsonb)
    into v_charges from jsonb_array_elements(q->'lines') with ordinality t(l, n);
  perform pg_temp.seed_push(p_arena, 'session.end', jsonb_build_object('session_id', v_id,
    'ended_at', v_end, 'billed_amount_paise', (q->>'amount')::bigint, 'mark_waived', false,
    'expected_segment_ids', jsonb_build_array(v_seg), 'expected_scheduled_end_at', v_end,
    'charges', v_charges));
  return v_id;
end $$;

create function pg_temp.seed_pay(p_arena uuid, p_session uuid, p_paise bigint, p_method text)
returns void language sql as $$
  select pg_temp.seed_push(p_arena, 'payment.record', jsonb_build_object('scope', 'single',
    'parent_id', p_session, 'payment_id', gen_random_uuid(), 'amount_paise', p_paise,
    'method', p_method))
$$;

-- Pays a session's bill in full by one method.
create function pg_temp.seed_pay_all(p_arena uuid, p_session uuid, p_method text)
returns void language sql as $$
  select pg_temp.seed_pay(p_arena, p_session,
    (select billed_amount_paise from sessions where id = p_session), p_method)
$$;

-- An IST wall-clock time p_days ago (0 = today), as an instant.
create function pg_temp.ist(p_days int, p_time time) returns timestamptz
language sql as $$
  select (((now() at time zone 'Asia/Kolkata')::date - p_days) + p_time) at time zone 'Asia/Kolkata'
$$;

-- ------------------------------------------------------------------------------------ data
do $seed$
declare
  v_arena uuid;
  v_staff uuid := '5eed0000-0000-4000-8000-000000000002';
  c uuid[] := array[
    '5eed0000-0000-4000-8000-0000000000c1', '5eed0000-0000-4000-8000-0000000000c2',
    '5eed0000-0000-4000-8000-0000000000c3', '5eed0000-0000-4000-8000-0000000000c4',
    '5eed0000-0000-4000-8000-0000000000c5', '5eed0000-0000-4000-8000-0000000000c6',
    '5eed0000-0000-4000-8000-0000000000c7', '5eed0000-0000-4000-8000-0000000000c8']::uuid[];
  s uuid;
  d int;
begin
  -- Arena with its owner, the 404 Arena catalog (4 types, 6 stations, rates, 16 games, pads)
  -- and a floor staff login.
  v_arena := bootstrap_owner('owner@arena.test', '404 Arena (demo)', 'Demo Owner');
  perform _seed_arena_catalog(v_arena);
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, v_staff, 'Demo Staff', 'staff', array['start', 'bill', 'discount', 'members'], true);

  -- Past days' bills carry device times older than the default 24 h offline window: widen it
  -- while seeding (removed again at the end).
  insert into settings(arena_id, key, json)
    values (v_arena, 'offline_rules', '{"max_offline_hours": 720}');

  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_staff, 'role', 'authenticated')::text, true);

  -- Customers.
  perform pg_temp.seed_push(v_arena, 'customer.create', jsonb_build_object('id', x.id,
      'name', x.name, 'phone', x.phone, 'is_guest', false))
    from (values
      (c[1], 'Rahul Menon', '9800000001'), (c[2], 'Ananya Iyer', '9800000002'),
      (c[3], 'Vikram Rao', '9800000003'), (c[4], 'Sneha Pillai', '9800000004'),
      (c[5], 'Arjun Nair', '9800000005'), (c[6], 'Divya Krishnan', '9800000006'),
      (c[7], 'Karthik S', '9800000007'), (c[8], 'Meera Joseph', '9800000008')) x(id, name, phone);

  -- The last six days: five bills a day across PS5, VR, pool and the lounge, paid by cash, UPI
  -- or card (the evening PS5 bill split cash + UPI).
  for d in 1..6 loop
    s := pg_temp.seed_session(v_arena, c[1 + d % 8], 'HEX', 'PS5', 1, pg_temp.ist(d, '12:00'), 60);
    perform pg_temp.seed_pay_all(v_arena, s, 'cash');
    s := pg_temp.seed_session(v_arena, c[1 + (d + 1) % 8], 'VOID', 'PS5', 2, pg_temp.ist(d, '15:00'), 90);
    perform pg_temp.seed_pay_all(v_arena, s, 'upi');
    s := pg_temp.seed_session(v_arena, c[1 + (d + 2) % 8], 'RIFT', 'VR', null, pg_temp.ist(d, '17:00'), 30);
    perform pg_temp.seed_pay_all(v_arena, s, 'upi');
    s := pg_temp.seed_session(v_arena, c[1 + (d + 3) % 8], 'Pool Table 1', 'POOL', null, pg_temp.ist(d, '18:30'), 60);
    perform pg_temp.seed_pay_all(v_arena, s, case when d % 2 = 0 then 'card' else 'cash' end);
    s := pg_temp.seed_session(v_arena, c[1 + (d + 4) % 8], 'GHOST', 'PS5', 2, pg_temp.ist(d, '20:00'), 120);
    perform pg_temp.seed_pay(v_arena, s, 50000, 'cash');
    perform pg_temp.seed_pay(v_arena, s,
      (select billed_amount_paise from sessions where id = s) - 50000, 'upi');
  end loop;

  -- A lounge party three days ago, and one bill from yesterday left unpaid (shows as due).
  s := pg_temp.seed_session(v_arena, c[6], 'Private Lounge', 'LOUNGE', null, pg_temp.ist(3, '13:00'), 120);
  perform pg_temp.seed_pay_all(v_arena, s, 'upi');
  perform pg_temp.seed_session(v_arena, c[7], 'GHOST', 'PS5', 1, pg_temp.ist(1, '10:30'), 60);

  -- Today: one bill closed an hour ago, and two sessions running now.
  s := pg_temp.seed_session(v_arena, c[2], 'VOID', 'PS5', 2, now() - interval '2 hours', 60);
  perform pg_temp.seed_pay_all(v_arena, s, 'cash');
  perform pg_temp.seed_session(v_arena, c[3], 'HEX', 'PS5', 2, now() - interval '40 minutes', 60, true);
  perform pg_temp.seed_session(v_arena, c[4], 'Pool Table 1', 'POOL', null, now() - interval '20 minutes', 60, true);

  -- Upcoming bookings.
  perform pg_temp.seed_push(v_arena, 'booking.create', jsonb_build_object('id', gen_random_uuid(),
      'customer_id', b.cust, 'resource_id', (select id from resources where arena_id = v_arena and name = b.station),
      'activity_code', b.act, 'scheduled_start', b.at_start,
      'scheduled_end', b.at_start + make_interval(mins => b.minutes),
      'players_required', b.players, 'controller_requirement', b.players,
      'party_name', b.party, 'phone', b.phone, 'notes', b.notes))
    from (values
      (c[1], 'VOID', 'PS5', pg_temp.ist(-1, '18:00'), 120, 2, 'Rahul Menon', '9800000001', 'FC 25 with a friend'),
      (c[5], 'Private Lounge', 'LOUNGE', pg_temp.ist(-1, '20:00'), 180, null, 'Arjun Nair', '9800000005', 'Birthday party'),
      (c[8], 'RIFT', 'VR', pg_temp.ist(-2, '17:00'), 60, null, 'Meera Joseph', '9800000008', null)
    ) b(cust, station, act, at_start, minutes, players, party, phone, notes);

  -- Back to the default offline window.
  delete from settings where arena_id = v_arena and key = 'offline_rules';
end
$seed$;

reset request.jwt.claims;
