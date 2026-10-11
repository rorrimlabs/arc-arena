-- 0016: money integrity, staff/owner protection, pad-move permission,
-- same-arena references, pinned search_path.
--
-- Found by the 2026-10-12 audit (docs/SYNC.md "0016"). Additive: existing op
-- bodies are renamed to *_v1 and wrapped (the 0013 pattern), so every check
-- the earlier migrations make still runs, in the same order, after these.
--
--  1. payment.record: once a bill is final, payments may only fill it up to
--     the bill, and a refund may never exceed what was collected. Two devices
--     that each saw "₹300 remaining" can no longer both collect it.
--     Mirrors paymentBalanceProblem() in lib/domain/services/payment_rules.dart.
--  2. staff.update: a role='owner' profile always holds every permission and
--     stays active (so an arena can never be left without an owner, and the
--     app — which reads perms only — and the server agree on what an owner
--     can do). Unknown permission codes are refused.
--  3. add_staff_by_email: may not overwrite an existing owner's profile, must
--     leave someone holding Settings, and refuses unknown permission codes.
--  4. controller.move loan / returnHome now need start or settings (was: any
--     active member).
--  5. resource.upsert refuses a station id that belongs to another arena (its
--     link clean-up used to run on that arena's rows).
--  6. Every cross-table reference must stay inside the row's arena (trigger),
--     so no op can point at another arena's customer, station, game, … .
--  7. Every remaining public function gets a pinned search_path (Supabase
--     advisor 0011_function_search_path_mutable).

-- =============================================================================
-- 1. Payments: no overpayment of a final bill, no refund beyond what was paid
-- =============================================================================

alter function op_payment(uuid, jsonb) rename to _op_payment_v1;

create or replace function _rupees(p bigint) returns text as $$
  select '₹' || to_char(p / 100.0, 'FM999999990.00');
$$ language sql immutable set search_path = public;

create or replace function op_payment(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_scope  text    := coalesce(p->>'scope', 'single');
  v_parent uuid    := (p->>'parent_id')::uuid;
  v_refund boolean := coalesce((p->>'is_refund')::boolean, false);
  v_amount bigint  := (p->>'amount_paise')::bigint;
  v_pay text; v_billed bigint; v_paid bigint;
begin
  -- Permission refusals keep their own code, ahead of any balance check.
  perform _need(p_arena, 'bill');
  if v_refund then perform _need(p_arena, 'discount'); end if;

  -- Lock the parent so two pushes for the same bill queue here and the second
  -- sees the first one's payment.
  if v_scope = 'group' then
    select payment_status, billed_amount_paise into v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from group_payments where group_id = v_parent;
    end if;
  else
    select payment_status, billed_amount_paise into v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from payments where session_id = v_parent;
    end if;
  end if;

  if v_paid is not null and coalesce(v_amount, 0) <> 0 then
    if v_refund then
      if v_paid - abs(v_amount) < 0 then
        raise exception 'refund_exceeds_paid'
          using hint = 'only ' || _rupees(greatest(v_paid, 0)) || ' was collected';
      end if;
    elsif v_amount > 0 and v_billed is not null and v_pay <> 'waived'
          and v_paid + v_amount > v_billed then
      raise exception 'overpayment'
        using hint = case when v_billed - v_paid <= 0 then 'this bill is already paid'
                          else 'only ' || _rupees(v_billed - v_paid) || ' is due' end;
    end if;
  end if;

  -- Not found / voided / zero / sign / reason / method: unchanged (0011).
  return _op_payment_v1(p_arena, p);
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- 2. Staff: an owner profile is always complete and active
-- =============================================================================

create or replace function _known_perms() returns text[] as $$
  select array['start','bill','discount','members','stations','money','reports','settings'];
$$ language sql immutable set search_path = public;

create or replace function _assert_known_perms(p_perms text[]) returns void as $$
begin
  if exists (select 1 from unnest(coalesce(p_perms, '{}')) x where x <> all(_known_perms())) then
    raise exception 'invalid_permission'
      using hint = 'permissions must be among ' || array_to_string(_known_perms(), ', ');
  end if;
end;
$$ language plpgsql immutable set search_path = public;

alter function op_staff_update(uuid, jsonb) rename to _op_staff_update_v1;

create or replace function op_staff_update(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_role  text;
  v_perms text[] := array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb)));
  v_q     jsonb := p;
  v_adj   boolean := false;
  v_res   jsonb;
begin
  perform _need(p_arena, 'settings');
  perform _assert_known_perms(v_perms);
  select role into v_role from staff_profiles
   where arena_id = p_arena and user_id = (p->>'user_id')::uuid;
  if v_role = 'owner' then
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    if not (v_perms @> _known_perms()) or coalesce((p->>'active')::boolean, true) = false then
      v_adj := true;
    end if;
    v_q := p || jsonb_build_object('perms', to_jsonb(_known_perms()), 'active', true);
  end if;
  -- Owner-only-edits-owner and the last-Settings-holder check: unchanged (0012).
  v_res := _op_staff_update_v1(p_arena, v_q);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then coalesce(v_res, '{}'::jsonb) || '{"adjusted": true}'::jsonb
              else v_res end;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- 3. add_staff_by_email: link a login; never rewrite an owner
-- =============================================================================

create or replace function add_staff_by_email(
  p_arena uuid, p_email text, p_name text, p_perms text[]
) returns uuid as $$
declare v_user uuid;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
  end if;
  perform _assert_known_perms(p_perms);
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create their login first: Authentication → Users → Add user';
  end if;
  if exists (select 1 from staff_profiles
              where arena_id = p_arena and user_id = v_user and role = 'owner') then
    raise exception 'owner_profile'
      using hint = 'that login is an owner of this arena; edit it in Settings → Staff';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user, coalesce(nullif(btrim(p_name), ''), 'Staff'), 'staff',
      coalesce(p_perms, '{}'), true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  -- Re-adding someone with fewer permissions must not strand Settings.
  perform _assert_settings_holder(p_arena);
  return v_user;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- 4. controller.move: carrying a pad is floor work, but still needs a floor role
-- =============================================================================

alter function op_controller_move(uuid, jsonb) rename to _op_controller_move_v1;

create or replace function op_controller_move(p_arena uuid, p jsonb) returns jsonb as $$
begin
  if coalesce(p->>'kind', '') in ('loan', 'returnHome')
     and not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'settings')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or settings';
  end if;
  -- 'permanent' still needs settings, checked in v1 (0011).
  return _op_controller_move_v1(p_arena, p);
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- 5. resource.upsert: never touch another arena's station
-- =============================================================================

alter function op_resource_upsert(uuid, jsonb) rename to _op_resource_upsert_v1;

create or replace function op_resource_upsert(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from resources where id = (p->>'id')::uuid and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  return _op_resource_upsert_v1(p_arena, p);
end;
$$ language plpgsql security definer set search_path = public;

-- The op dispatcher (0012's _sync_apply, renamed _sync_apply_v1 by 0013 and
-- wrapped there for price-list history) is recreated with its body unchanged,
-- so every session recompiles it against the wrappers above rather than keep
-- a cached plan that calls the renamed v1 bodies. 0013's _sync_apply wrapper
-- is NOT touched.
create or replace function _sync_apply_v1(p_arena uuid, p_kind text, p jsonb) returns jsonb as $$
begin
  return case p_kind
    when 'session.start'        then op_session_start(p_arena, p)
    when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
    when 'session.extend'       then op_session_extend(p_arena, p)
    when 'session.end'          then op_session_end(p_arena, p)
    when 'session.void'         then op_session_void(p_arena, p)
    when 'payment.record'       then op_payment(p_arena, p)
    when 'group.create'         then op_group_create(p_arena, p)
    when 'group.add'            then op_group_add(p_arena, p)
    when 'group.switch'         then op_group_switch(p_arena, p)
    when 'group.end_player'     then op_group_end_player(p_arena, p)
    when 'group.extend'         then op_group_extend(p_arena, p)
    when 'group.end'            then op_group_end(p_arena, p)
    when 'group.void'           then op_group_void(p_arena, p)
    when 'controller.move'      then op_controller_move(p_arena, p)
    when 'controller.upsert'    then op_controller_upsert(p_arena, p)
    when 'controller.set_status' then op_controller_set_status(p_arena, p)
    when 'customer.create'      then op_customer_create(p_arena, p)
    when 'customer.update'      then op_customer_update(p_arena, p)
    when 'booking.create'       then op_booking_create(p_arena, p)
    when 'booking.update'       then op_booking_update(p_arena, p)
    when 'booking.set_status'   then op_booking_set_status(p_arena, p)
    when 'game.upsert'          then op_game_upsert(p_arena, p)
    when 'game.set_active'      then op_game_set_active(p_arena, p)
    when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
    when 'game.set_compat'      then op_game_set_compat(p_arena, p)
    when 'resource.upsert'      then op_resource_upsert(p_arena, p)
    when 'resource.set_status'  then op_resource_set_status(p_arena, p)
    when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
    when 'rate.upsert'          then op_rate_upsert(p_arena, p)
    when 'rate.delete'          then op_rate_delete(p_arena, p)
    when 'policy.save'          then op_policy_save(p_arena, p)
    when 'settings.save'        then op_settings_save(p_arena, p)
    when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
    when 'holiday.delete'       then op_holiday_delete(p_arena, p)
    when 'staff.update'         then op_staff_update(p_arena, p)
    else null
  end;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- 6. References never leave the row's arena
-- =============================================================================
-- The foreign keys are on id alone, so a row of arena A could point at arena
-- B's customer, station, game … if an op passed B's uuid. Each op checks most
-- ids itself; this trigger makes the rule hold for every op, present and
-- future. Arguments are (column, referenced table) pairs. errcode 23503 →
-- sync_push reports 'missing_reference'.

create or replace function _assert_same_arena() returns trigger as $$
declare
  i int := 0;
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_col text; v_tab text; v_id uuid; v_ok boolean;
begin
  while i < tg_nargs loop
    v_col := tg_argv[i];
    v_tab := tg_argv[i + 1];
    i := i + 2;
    v_id := nullif(v_new->>v_col, '')::uuid;
    continue when v_id is null;
    continue when v_old is not null and (v_old->>v_col) is not distinct from (v_new->>v_col)
                  and (v_old->>'arena_id') = (v_new->>'arena_id');
    execute format('select exists (select 1 from %I where id = $1 and arena_id = $2)', v_tab)
      into v_ok using v_id, (v_new->>'arena_id')::uuid;
    if not v_ok then
      raise exception 'cross_arena_reference' using errcode = '23503',
        hint = tg_table_name || '.' || v_col || ' must belong to the same arena';
    end if;
  end loop;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$
declare
  r record;
begin
  for r in select * from (values
    ('bookings',               array['customer_id','customers','game_id','games','resource_id','resources','activity_id','activities']),
    ('controller_allocations', array['assignment_id','group_assignments','controller_id','controllers','game_id','games',
                                     'group_id','group_sessions','resource_id','resources','segment_id','session_segments',
                                     'session_id','sessions']),
    ('controller_moves',       array['controller_id','controllers','from_resource_id','resources','to_resource_id','resources']),
    ('controllers',            array['current_resource_id','resources','home_resource_id','resources']),
    ('game_controls',          array['game_id','games']),
    ('game_resources',         array['game_id','games','resource_id','resources']),
    ('games',                  array['category_id','game_categories']),
    ('group_assignments',      array['game_id','games','group_id','group_sessions','resource_id','resources']),
    ('group_charges',          array['assignment_id','group_assignments','group_id','group_sessions','resource_id','resources']),
    ('group_extensions',       array['group_id','group_sessions']),
    ('group_payments',         array['group_id','group_sessions']),
    ('group_sessions',         array['primary_customer_id','customers']),
    ('payments',               array['session_id','sessions']),
    ('rates',                  array['activity_id','activities','band_id','rate_bands','rate_card_id','rate_cards']),
    ('resource_activities',    array['activity_id','activities','resource_id','resources']),
    ('session_charges',        array['resource_id','resources','segment_id','session_segments','session_id','sessions']),
    ('session_extensions',     array['session_id','sessions']),
    ('session_segments',       array['game_id','games','resource_id','resources','session_id','sessions']),
    ('sessions',               array['booking_id','bookings','customer_id','customers'])
  ) as t(tbl, args) loop
    execute format(
      'create trigger t_same_arena before insert or update on %I '
      'for each row execute function _assert_same_arena(%s)',
      r.tbl, (select string_agg(quote_literal(a), ', ') from unnest(r.args) a));
  end loop;
end $$;

-- =============================================================================
-- Grants: nothing new is client-callable
-- =============================================================================

do $$
declare f text;
begin
  foreach f in array array[
    '_rupees(bigint)', 'op_payment(uuid,jsonb)', '_op_payment_v1(uuid,jsonb)',
    '_known_perms()', '_assert_known_perms(text[])',
    'op_staff_update(uuid,jsonb)', '_op_staff_update_v1(uuid,jsonb)',
    'op_controller_move(uuid,jsonb)', '_op_controller_move_v1(uuid,jsonb)',
    'op_resource_upsert(uuid,jsonb)', '_op_resource_upsert_v1(uuid,jsonb)',
    '_sync_apply_v1(uuid,text,jsonb)', '_assert_same_arena()'
  ] loop
    execute format('revoke execute on function %s from anon, public, authenticated', f);
  end loop;
end $$;

-- add_staff_by_email stays the one owner RPC (0012/0015 grants, re-stated).
revoke execute on function add_staff_by_email(uuid, text, text, text[]) from anon, public;
grant execute on function add_staff_by_email(uuid, text, text, text[]) to authenticated;

-- =============================================================================
-- 7. Pin search_path on every remaining public function
-- =============================================================================
-- Same value the callers resolved with before (public, then extensions), so
-- behaviour is unchanged; only a caller's own search_path can no longer
-- redirect an unqualified name.

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('alter function %s set search_path = public, extensions', r.fn);
  end loop;
end $$;
