-- Pricing parity — the server side. Run by tool/pricing_parity.sh; do not run
-- by hand against anything but the local dev stack.
--
-- Loads the cases generate.dart priced with the app's own code and checks the
-- server agrees to the paisa, at two levels:
--   1. FUNCTIONS — _pr_quote / _pr_session_bill / _pr_group_bill (migration
--      0013) against PricingService / SegmentBilling / GroupBilling; same total
--      and the same charge rows.
--   2. OPERATIONS — the real session.end / group.end (incl. waived) and
--      session.extend / group.extend through sync_push: the app's exact money
--      must be APPLIED, and the same op one paisa off (in the total, in one
--      charge row, or in the extension) must be REFUSED with price_mismatch.
--
-- Everything happens inside one transaction on a throwaway arena with fixed
-- ids, and is rolled back: the database is left exactly as it was.
--
-- psql variables: mutate_server (true/false) — when true, the server's money
-- rounding is deliberately made one paisa wrong inside the transaction, to
-- prove this harness reports it.
\set ON_ERROR_STOP on
begin;
set local client_min_messages = warning;

\if :mutate_server
-- Deliberate one-paisa server error (self-test only; rolled back below).
create or replace function _pr_money(v bigint, step int, dir text) returns bigint as $m$
  select case when step <= 1 then v
              when dir = 'up' then _pr_ceil_step(v, step)
              else _pr_round_step(v, step) end + case when v > 0 then 1 else 0 end;
$m$ language sql immutable strict;
\endif

-- ---------------------------------------------------------- isolated fixture
insert into arenas(id, name) values ('f0000000-0000-4000-8000-0000000000a0', 'pricing-parity (rolled back)');
insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible)
  values ('f0000000-0000-4000-8000-0000000000a0', 'PS5', 'PS5', true, true, 'hourly', true),
         ('f0000000-0000-4000-8000-0000000000a0', 'VR', 'VR', false, true, 'unit', false),
         ('f0000000-0000-4000-8000-0000000000a0', 'POOL', 'Pool', false, false, 'hourly', true),
         ('f0000000-0000-4000-8000-0000000000a0', 'LOUNGE', 'Lounge', false, false, 'flat_hourly', false);
insert into resources(id, arena_id, name, kind) values
  ('f0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-0000000000a0', 'HEX', 'station'),
  ('f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-0000000000a0', 'VOID', 'station'),
  ('f0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-0000000000a0', 'GHOST', 'station'),
  ('f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-0000000000a0', 'RIFT', 'station');
insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
  values ('00000000-0000-0000-0000-000000000000', 'f0000000-0000-4000-8000-0000000000b1',
    'authenticated', 'authenticated', 'pricing-parity@harness.invalid', '', now(), now(), now(),
    '{}', '{}', false, false);
insert into staff_profiles(arena_id, user_id, name, role, perms)
  values ('f0000000-0000-4000-8000-0000000000a0', 'f0000000-0000-4000-8000-0000000000b1', 'Parity', 'owner',
    array['start','bill','discount','members','stations','money','reports','settings']);
insert into customers(id, arena_id, name)
  values ('f0000000-0000-4000-8000-0000000000c1', 'f0000000-0000-4000-8000-0000000000a0', 'Parity');
select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);

create temp table cases(n serial, j jsonb) on commit drop;
\copy cases(j) from '/tmp/parity_cases.ndjson' with (format csv, quote e'\x01', delimiter e'\x02')
create temp table bad(n int, layer text, label text, detail text) on commit drop;
create temp table ran(layer text) on commit drop;

-- One op through sync_push; returns {status, error, ...}.
create function pg_temp.push(p_kind text, p jsonb) returns jsonb as $f$
  select sync_push('f0000000-0000-4000-8000-0000000000a0',
    jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'kind', p_kind, 'payload', p)),
    'pricing-parity')->'results'->0;
$f$ language sql;

do $$
declare
  c record; j jsonb; q jsonb; b jsonb; x jsonb; r jsonb; v_keys text; v_exp text;
  v_arena uuid := 'f0000000-0000-4000-8000-0000000000a0';
  v_cust uuid := 'f0000000-0000-4000-8000-0000000000c1';
  v_id uuid; v_ids jsonb; v_charges jsonb; v_payload jsonb; v_alist jsonb; v_amap jsonb;
  v_one jsonb;
begin
  for c in select * from cases order by n loop
    j := c.j;
    -- ============================================================ quotes
    if j->>'k' = 'q' then
      insert into ran values ('function');
      q := _pr_quote(j->'snap', j->>'act', (j->>'cc')::int, (j->>'s')::timestamptz, (j->>'e')::timestamptz);
      if (q is null) <> (j->'exp' = 'null'::jsonb) then
        insert into bad values (c.n, 'function', j->>'label', format('priced? server %s app %s', q is not null, j->'exp' <> 'null'));
        continue;
      end if;
      continue when q is null;
      select string_agg(k, ',' order by k) into v_keys from unnest(_pr_keys(q, j->>'act', null, (j->>'cc')::int)) k;
      select string_agg(k, ',' order by k) into v_exp from jsonb_array_elements_text(j->'exp'->'keys') k;
      if (q->>'subtotal')::bigint <> (j->'exp'->>'subtotal')::bigint
         or (q->>'amount')::bigint <> (j->'exp'->>'amount')::bigint
         or coalesce(v_keys, '') <> coalesce(v_exp, '') then
        insert into bad values (c.n, 'function', j->>'label', format('server %s/%s app %s/%s',
          q->>'subtotal', q->>'amount', j->'exp'->>'subtotal', j->'exp'->>'amount'));
      end if;

    -- ====================================================== single sessions
    elsif j->>'k' = 's' then
      v_id := gen_random_uuid();
      insert into sessions(id, arena_id, customer_id, status, started_at, scheduled_end_at,
          pricing_snapshot, policy_snapshot)
        values (v_id, v_arena, v_cust, 'active', (j->>'start')::timestamptz, (j->>'end')::timestamptz,
          j->'snap', j->'snap'->'policy');
      v_ids := '{}';
      for x in select value from jsonb_array_elements(j->'segs') loop
        v_ids := v_ids || jsonb_build_object(x->>'idx', gen_random_uuid());
        insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
            controller_count, started_at, ended_at)
          values ((v_ids->>(x->>'idx'))::uuid, v_arena, v_id, (x->>'idx')::int, (x->>'res')::uuid,
            x->>'act', (x->>'cc')::int, (x->>'s')::timestamptz, (x->>'e')::timestamptz);
      end loop;
      -- 1. function
      insert into ran values ('function');
      b := _pr_session_bill(v_id, (j->>'end')::timestamptz);
      select string_agg(k, ',' order by k) into v_keys from jsonb_array_elements_text(b->'keys') k;
      select string_agg(k, ',' order by k) into v_exp from jsonb_array_elements_text(j->'keys') k;
      if (b->>'total')::bigint <> (j->>'total')::bigint or coalesce(v_keys, '') <> coalesce(v_exp, '') then
        insert into bad values (c.n, 'function', j->>'label', format('server %s app %s', b->>'total', j->>'total'));
      end if;
      -- 2. the real session.end (the app does not end a bill it cannot price)
      if (j->>'unpriced')::int = 0 then
        insert into ran values ('operation');
        select coalesce(jsonb_agg(ch - 'seg_idx' || jsonb_build_object('id', gen_random_uuid(),
                 'segment_id', v_ids->>(ch->>'seg_idx'))), '[]')
          into v_charges from jsonb_array_elements(j->'charges') ch;
        v_payload := jsonb_build_object('session_id', v_id, 'ended_at', j->>'end',
          'billed_amount_paise', (j->>'total')::bigint, 'mark_waived', (j->>'waived')::boolean,
          'expected_segment_ids', (select jsonb_agg(value) from jsonb_each_text(v_ids)),
          'expected_scheduled_end_at', j->>'end', 'charges', v_charges);
        r := pg_temp.push('session.end', v_payload || jsonb_build_object('billed_amount_paise', (j->>'total')::bigint + 1));
        if r->>'error' is distinct from 'price_mismatch' then
          insert into bad values (c.n, 'operation', j->>'label', 'end one paisa over not refused: ' || r::text);
        end if;
        if jsonb_array_length(v_charges) > 0 then
          v_one := jsonb_set(v_charges, '{0,amount_paise}', to_jsonb((v_charges->0->>'amount_paise')::bigint + 1));
          r := pg_temp.push('session.end', v_payload || jsonb_build_object('charges', v_one));
          if r->>'error' is distinct from 'price_mismatch' then
            insert into bad values (c.n, 'operation', j->>'label', 'charge row one paisa over not refused: ' || r::text);
          end if;
        end if;
        r := pg_temp.push('session.end', v_payload);
        if r->>'status' <> 'applied' then
          insert into bad values (c.n, 'operation', j->>'label', 'app''s exact end refused: ' || r::text);
        end if;
      end if;
      delete from sessions where id = v_id;

    -- ============================================================= groups
    elsif j->>'k' in ('g', 'gx') then
      v_id := gen_random_uuid();
      insert into group_sessions(id, arena_id, primary_customer_id, player_count, purchased_controller_count,
          started_at, scheduled_end_at, pricing_snapshot, policy_snapshot, billing_mode)
        values (v_id, v_arena, v_cust, 4, (j->>'purchased')::int, (j->>'start')::timestamptz,
          coalesce(j->>'end', j->>'old_end')::timestamptz, j->'snap', j->'snap'->'policy', j->>'mode');
      v_amap := '{}';
      for x in select value from jsonb_array_elements(j->'as') loop
        v_amap := v_amap || jsonb_build_object(x->>'id', gen_random_uuid());
        insert into group_assignments(id, arena_id, group_id, player_number, idx, resource_id,
            activity_code, controller_count, started_at, ended_at)
          values ((v_amap->>(x->>'id'))::uuid, v_arena, v_id, (x->>'p')::int, (x->>'idx')::int,
            (x->>'res')::uuid, x->>'act', (x->>'cc')::int, (x->>'s')::timestamptz, (x->>'e')::timestamptz);
      end loop;
      if j->>'k' = 'g' then
        insert into ran values ('function');
        b := _pr_group_bill(v_id, (j->>'end')::timestamptz);
        select string_agg(k, ',' order by k) into v_keys from jsonb_array_elements_text(b->'keys') k;
        select string_agg(k, ',' order by k) into v_exp from jsonb_array_elements_text(j->'keys') k;
        if (b->>'total')::bigint <> (j->>'total')::bigint or (b->>'subtotal')::bigint <> (j->>'subtotal')::bigint
           or coalesce(v_keys, '') <> coalesce(v_exp, '') then
          insert into bad values (c.n, 'function', j->>'label', format('server %s/%s app %s/%s',
            b->>'subtotal', b->>'total', j->>'subtotal', j->>'total'));
        end if;
        insert into ran values ('operation');
        select coalesce(jsonb_agg(ch - 'assignment' || jsonb_build_object('id', gen_random_uuid(),
                 'assignment_id', v_amap->>(ch->>'assignment'))), '[]')
          into v_charges from jsonb_array_elements(j->'charges') ch;
        select jsonb_agg(value) into v_alist from jsonb_each_text(v_amap);
        v_payload := jsonb_build_object('group_id', v_id, 'ended_at', j->>'end',
          'billed_amount_paise', (j->>'total')::bigint, 'mark_waived', (j->>'waived')::boolean,
          'expected_assignment_ids', v_alist, 'expected_scheduled_end_at', j->>'end', 'charges', v_charges);
        r := pg_temp.push('group.end', v_payload || jsonb_build_object('billed_amount_paise', (j->>'total')::bigint + 1));
        if r->>'error' is distinct from 'price_mismatch' then
          insert into bad values (c.n, 'operation', j->>'label', 'group end one paisa over not refused: ' || r::text);
        end if;
        r := pg_temp.push('group.end', v_payload);
        if r->>'status' <> 'applied' then
          insert into bad values (c.n, 'operation', j->>'label', 'app''s exact group end refused: ' || r::text);
        end if;
      else
        insert into ran values ('operation');
        v_payload := jsonb_build_object('group_id', v_id, 'extension_id', gen_random_uuid(),
          'added_minutes', 30, 'old_end_at', j->>'old_end', 'new_end_at', j->>'new_end',
          'added_amount_paise', (j->>'added')::bigint);
        r := pg_temp.push('group.extend', v_payload || jsonb_build_object('added_amount_paise', (j->>'added')::bigint + 1));
        if r->>'error' is distinct from 'price_mismatch' then
          insert into bad values (c.n, 'operation', j->>'label', 'group extension one paisa over not refused: ' || r::text);
        end if;
        r := pg_temp.push('group.extend', v_payload);
        if r->>'status' <> 'applied' then
          insert into bad values (c.n, 'operation', j->>'label', 'app''s exact group extension refused: ' || r::text);
        end if;
      end if;
      delete from group_sessions where id = v_id;

    -- ==================================================== single extensions
    elsif j->>'k' = 'x' then
      insert into ran values ('operation');
      v_id := gen_random_uuid();
      insert into sessions(id, arena_id, customer_id, status, started_at, scheduled_end_at,
          pricing_snapshot, policy_snapshot)
        values (v_id, v_arena, v_cust, 'active', (j->>'start')::timestamptz, (j->>'old_end')::timestamptz,
          j->'snap', j->'snap'->'policy');
      insert into session_segments(arena_id, session_id, idx, resource_id, activity_code,
          controller_count, started_at)
        values (v_arena, v_id, 0, 'f0000000-0000-4000-8000-000000000001', j->>'act', (j->>'cc')::int,
          (j->>'start')::timestamptz);
      v_payload := jsonb_build_object('session_id', v_id, 'extension_id', gen_random_uuid(),
        'added_minutes', (j->>'added_minutes')::int, 'old_end_at', j->>'old_end', 'new_end_at', j->>'new_end',
        'added_amount_paise', (j->>'added')::bigint);
      r := pg_temp.push('session.extend', v_payload || jsonb_build_object('added_amount_paise', (j->>'added')::bigint + 1));
      if r->>'error' is distinct from 'price_mismatch' then
        insert into bad values (c.n, 'operation', j->>'label', 'extension one paisa over not refused: ' || r::text);
      end if;
      r := pg_temp.push('session.extend', v_payload);
      if r->>'status' <> 'applied' then
        insert into bad values (c.n, 'operation', j->>'label', 'app''s exact extension refused: ' || r::text);
      end if;
      delete from sessions where id = v_id;
    end if;
  end loop;
end $$;

\pset footer off
select j->>'k' as kind, count(*) as cases from cases group by 1 order by 1;
select n, layer, label, left(detail, 300) as detail from bad order by n limit 10;
select 'PARITY cases=' || (select count(*) from cases)
    || ' checks_function=' || (select count(*) from ran where layer = 'function')
    || ' checks_operation=' || (select count(*) from ran where layer = 'operation')
    || ' mismatches_function=' || (select count(*) from bad where layer = 'function')
    || ' mismatches_operation=' || (select count(*) from bad where layer = 'operation') as result;
rollback;
