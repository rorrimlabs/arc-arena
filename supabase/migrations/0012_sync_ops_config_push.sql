-- arena_ops — the multi-device write path, part 2: customers, bookings, owner
-- configuration, staff, arena bootstrap, and the sync_push dispatcher. Then the
-- old direct write paths are closed so sync_push is the ONLY way a client
-- changes data (audit gaps 1, 2, 5, 6, 7).

create or replace function _stale(p_current xid8, p_base text) returns boolean as $$
  select p_base is not null and p_base <> '' and p_current::text <> p_base;
$$ language sql immutable;

-- =============================================================================
-- Customers
-- =============================================================================

-- customer.create {id, name, phone?, notes?, is_guest, last_visit_at?, created_at?}
-- A phone already used in the arena (two devices registering the same person
-- offline) must not sink the session that references this customer, so the
-- row is kept without the phone and the clash is put on the audit log.
create or replace function op_customer_create(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_phone text := nullif(btrim(p->>'phone'), '');
  v_other uuid;
begin
  if not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  if v_phone is not null then
    select id into v_other from customers where arena_id = p_arena and phone = v_phone;
  end if;
  insert into customers(id, arena_id, name, phone, notes, last_visit_at, is_guest, created_at, updated_at)
    values ((p->>'id')::uuid, p_arena, p->>'name', case when v_other is null then v_phone end,
      p->>'notes', (p->>'last_visit_at')::timestamptz, coalesce((p->>'is_guest')::boolean, false),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now);
  if v_other is not null then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
      values (p_arena, 'customer', (p->>'id')::uuid, 'duplicate_phone_on_sync',
        'phone already belongs to another customer', jsonb_build_object('phone', v_phone,
        'existing_customer_id', v_other), auth.uid(), v_now);
    return jsonb_build_object('adjusted', true, 'phone_taken_by', v_other);
  end if;
  return jsonb_build_object('adjusted', false);
end;
$$ language plpgsql security definer set search_path = public;

-- customer.update {id, name, phone?, notes?, base_version}
create or replace function op_customer_update(p_arena uuid, p jsonb) returns jsonb as $$
declare v_xid xid8;
begin
  if not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  select sync_xid into v_xid from customers where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'customer'; end if;
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the customer was edited on another device';
  end if;
  begin
    update customers set name = p->>'name', phone = nullif(btrim(p->>'phone'), ''),
        notes = p->>'notes', updated_at = statement_timestamp()
      where id = (p->>'id')::uuid;
  exception when unique_violation then
    raise exception 'phone_taken';
  end;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Bookings
-- =============================================================================

create or replace function _activity_id(p_arena uuid, p_code text) returns uuid as $$
declare v uuid;
begin
  select id into v from activities where arena_id = p_arena and code = p_code;
  if not found then raise exception 'activity_missing' using hint = coalesce(p_code, 'null'); end if;
  return v;
end;
$$ language plpgsql stable security definer set search_path = public;

-- A specific station cannot hold two overlapping open bookings
-- (BookingAvailabilityService.checkSpecific, half-open overlap).
create or replace function _booking_free(p_arena uuid, p_id uuid, p_resource uuid,
    p_start timestamptz, p_end timestamptz) returns void as $$
begin
  if p_resource is null then return; end if;
  perform 1 from resources where id = p_resource and arena_id = p_arena for update;
  if exists (select 1 from bookings
              where arena_id = p_arena and resource_id = p_resource and status = 'booked'
                and id <> p_id and scheduled_start < p_end and scheduled_end > p_start) then
    raise exception 'booking_conflict';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

-- booking.create {id, customer_id?, activity_code, game_id?, resource_id?,
--   scheduled_start, scheduled_end, players_required?, controller_requirement?,
--   party_name?, phone?, notes?, reminder_status?, created_at?}
create or replace function op_booking_create(p_arena uuid, p jsonb) returns jsonb as $$
declare v_now timestamptz := statement_timestamp(); v_res uuid := nullif(p->>'resource_id','')::uuid;
begin
  perform _need(p_arena, 'start');
  perform _booking_free(p_arena, (p->>'id')::uuid, v_res,
    (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz);
  insert into bookings(id, arena_id, customer_id, resource_id, activity_id, game_id, scheduled_start,
      scheduled_end, status, players_required, controller_requirement, party_name, phone, notes,
      reminder_status, created_at, updated_at)
    values ((p->>'id')::uuid, p_arena, nullif(p->>'customer_id','')::uuid, v_res,
      _activity_id(p_arena, p->>'activity_code'), nullif(p->>'game_id','')::uuid,
      (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz, 'booked',
      nullif(p->>'players_required','')::int, nullif(p->>'controller_requirement','')::int,
      p->>'party_name', p->>'phone', p->>'notes', coalesce(p->>'reminder_status', 'scheduled'),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now);
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- booking.update {id, base_version, ...same fields as create}. Only an open
-- booking can be edited (a checked-in one is history).
create or replace function op_booking_update(p_arena uuid, p jsonb) returns jsonb as $$
declare v_xid xid8; v_status text; v_res uuid := nullif(p->>'resource_id','')::uuid;
begin
  perform _need(p_arena, 'start');
  select sync_xid, status into v_xid, v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the booking was changed on another device';
  end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  perform _booking_free(p_arena, (p->>'id')::uuid, v_res,
    (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz);
  update bookings set customer_id = nullif(p->>'customer_id','')::uuid, resource_id = v_res,
      activity_id = _activity_id(p_arena, p->>'activity_code'), game_id = nullif(p->>'game_id','')::uuid,
      scheduled_start = (p->>'scheduled_start')::timestamptz,
      scheduled_end = (p->>'scheduled_end')::timestamptz,
      players_required = nullif(p->>'players_required','')::int,
      controller_requirement = nullif(p->>'controller_requirement','')::int,
      party_name = p->>'party_name', phone = p->>'phone', notes = p->>'notes',
      updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- booking.set_status {id, status: cancelled|no_show}. Check-in happens only
-- inside session.start, atomically with the session.
create or replace function op_booking_set_status(p_arena uuid, p jsonb) returns jsonb as $$
declare v_status text;
begin
  perform _need(p_arena, 'start');
  if (p->>'status') not in ('cancelled', 'no_show') then
    raise exception 'invalid_status' using hint = coalesce(p->>'status', 'null');
  end if;
  select status into v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  if v_status = p->>'status' then return '{}'::jsonb; end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  update bookings set status = p->>'status', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Owner configuration (the client gates Settings on the `settings` permission)
-- =============================================================================

-- game.upsert {id, name, aliases[], category_id?, platforms[], player_mode,
--   max_local_players, active}
create or replace function op_game_upsert(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  insert into games(id, arena_id, name, aliases, category_id, platforms, player_mode,
      max_local_players, active)
    values ((p->>'id')::uuid, p_arena, p->>'name',
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = excluded.active, updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function op_game_set_active(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  update games set active = (p->>'active')::boolean, updated_at = statement_timestamp()
    where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'game'; end if;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- game.replace_controls {game_id, controls:[{id, section, action, buttons[],
--   explanation?, notes?, image_url?, sort_order}]}
create or replace function op_game_replace_controls(p_arena uuid, p jsonb) returns jsonb as $$
declare v_game uuid := (p->>'game_id')::uuid; c jsonb;
begin
  perform _need(p_arena, 'settings');
  if not exists (select 1 from games where id = v_game and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  delete from game_controls where game_id = v_game and arena_id = p_arena;
  for c in select value from jsonb_array_elements(coalesce(p->'controls', '[]'::jsonb)) loop
    insert into game_controls(id, arena_id, game_id, section, action, buttons, explanation, notes,
        image_url, sort_order)
      values ((c->>'id')::uuid, p_arena, v_game, c->>'section', c->>'action',
        array(select jsonb_array_elements_text(coalesce(c->'buttons', '[]'::jsonb))),
        c->>'explanation', c->>'notes', c->>'image_url', coalesce((c->>'sort_order')::int, 0));
  end loop;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- game.set_compat {game_id, resource_id, status, notes?}
create or replace function op_game_set_compat(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  insert into game_resources(arena_id, game_id, resource_id, status, notes)
    values (p_arena, (p->>'game_id')::uuid, (p->>'resource_id')::uuid, p->>'status', p->>'notes')
  on conflict (game_id, resource_id) do update
    set status = excluded.status, notes = excluded.notes, updated_at = statement_timestamp()
    where game_resources.arena_id = p_arena;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- resource.upsert {id, name, kind, status, sort_order, activity_codes[]}
create or replace function op_resource_upsert(p_arena uuid, p jsonb) returns jsonb as $$
declare v_id uuid := (p->>'id')::uuid; v_code text;
begin
  perform _need(p_arena, 'settings');
  insert into resources(id, arena_id, name, kind, status, sort_order)
    values (v_id, p_arena, p->>'name', p->>'kind', coalesce(p->>'status', 'available'),
      coalesce((p->>'sort_order')::int, 0))
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      status = excluded.status, sort_order = excluded.sort_order, updated_at = statement_timestamp()
    where resources.arena_id = p_arena;
  delete from resource_activities ra using activities a
   where ra.resource_id = v_id and a.id = ra.activity_id
     and not (a.code = any(array(select jsonb_array_elements_text(coalesce(p->'activity_codes','[]'::jsonb)))));
  for v_code in select jsonb_array_elements_text(coalesce(p->'activity_codes', '[]'::jsonb)) loop
    insert into resource_activities(arena_id, resource_id, activity_id)
      values (p_arena, v_id, _activity_id(p_arena, v_code))
    on conflict (resource_id, activity_id) do nothing;
  end loop;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function op_resource_set_status(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  update resources set status = p->>'status', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'resource'; end if;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- resource.set_mode {id, mode?}: refused while the station is occupied
-- (LocalControllerAllocationRepository.setResourceMode).
create or replace function op_resource_set_mode(p_arena uuid, p jsonb) returns jsonb as $$
declare v_id uuid := (p->>'id')::uuid;
begin
  perform _need(p_arena, 'settings');
  perform 1 from resources where id = v_id and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'resource'; end if;
  if exists (select 1 from session_segments where resource_id = v_id and ended_at is null)
     or exists (select 1 from group_assignments where resource_id = v_id and ended_at is null) then
    raise exception 'mode_switch_busy';
  end if;
  update resources set current_mode = nullif(p->>'mode',''), updated_at = statement_timestamp()
    where id = v_id;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- controller.upsert {id, label, home_resource_id, current_resource_id, status,
--   notes?, loan_return_to?, loan_session_ref?}: add / rename / re-home a pad.
-- A pad in a player's hands cannot be relocated from the inventory screen.
create or replace function op_controller_upsert(p_arena uuid, p jsonb) returns jsonb as $$
declare v_id uuid := (p->>'id')::uuid; v_loc uuid;
begin
  perform _need(p_arena, 'settings');
  select current_resource_id into v_loc from controllers where id = v_id and arena_id = p_arena for update;
  if found and v_loc <> (p->>'current_resource_id')::uuid and exists (
       select 1 from controller_allocations where controller_id = v_id and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  insert into controllers(id, arena_id, label, home_resource_id, current_resource_id, status,
      notes, loan_return_to, loan_session_ref)
    values (v_id, p_arena, p->>'label', (p->>'home_resource_id')::uuid,
      (p->>'current_resource_id')::uuid, coalesce(p->>'status', 'usable'), p->>'notes',
      p->>'loan_return_to', p->>'loan_session_ref')
  on conflict (id) do update set label = excluded.label,
      home_resource_id = excluded.home_resource_id, current_resource_id = excluded.current_resource_id,
      status = excluded.status, notes = excluded.notes, loan_return_to = excluded.loan_return_to,
      loan_session_ref = excluded.loan_session_ref, updated_at = statement_timestamp()
    where controllers.arena_id = p_arena;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function op_controller_set_status(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  update controllers set status = p->>'status', notes = p->>'notes', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'controller'; end if;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- Rates live on the arena's active card; the device addresses one by its
-- natural key (activity code, band code, controller count).
create or replace function _active_card(p_arena uuid) returns uuid as $$
declare v uuid;
begin
  select id into v from rate_cards where arena_id = p_arena and active
    order by effective_from desc limit 1;
  if not found then
    insert into rate_cards(arena_id, name) values (p_arena, 'Current') returning id into v;
  end if;
  return v;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function _band_id(p_arena uuid, p_code text) returns uuid as $$
declare v uuid;
begin
  select id into v from rate_bands where arena_id = p_arena and code = p_code;
  if not found then
    insert into rate_bands(arena_id, code, name) values (p_arena, p_code, initcap(p_code))
      returning id into v;
  end if;
  return v;
end;
$$ language plpgsql security definer set search_path = public;

-- rate.upsert {activity_code, band, controller_count?, unit_minutes, price_paise}
create or replace function op_rate_upsert(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_card uuid := _active_card(p_arena);
  v_act uuid := _activity_id(p_arena, p->>'activity_code');
  v_band uuid := _band_id(p_arena, p->>'band');
  v_cc int := nullif(p->>'controller_count','')::int;
  v_id uuid;
begin
  perform _need(p_arena, 'settings');
  select id into v_id from rates where rate_card_id = v_card and activity_id = v_act
    and band_id = v_band and coalesce(controller_count, -1) = coalesce(v_cc, -1) for update;
  if found then
    update rates set unit_minutes = (p->>'unit_minutes')::int,
        price_paise = (p->>'price_paise')::bigint, updated_at = statement_timestamp()
      where id = v_id;
  else
    insert into rates(arena_id, rate_card_id, activity_id, band_id, controller_count, unit_minutes, price_paise)
      values (p_arena, v_card, v_act, v_band, v_cc, (p->>'unit_minutes')::int, (p->>'price_paise')::bigint);
  end if;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- rate.delete {activity_code, band, controller_count?}
create or replace function op_rate_delete(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  delete from rates r using rate_bands b, activities a
   where r.arena_id = p_arena and r.rate_card_id = _active_card(p_arena)
     and b.id = r.band_id and b.code = p->>'band'
     and a.id = r.activity_id and a.code = p->>'activity_code'
     and coalesce(r.controller_count, -1) = coalesce(nullif(p->>'controller_count','')::int, -1);
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- policy.save {policy: BillingPolicy.toJson()} — keys are the column names.
create or replace function op_policy_save(p_arena uuid, p jsonb) returns jsonb as $$
declare j jsonb := p->'policy'; v_id uuid;
begin
  perform _need(p_arena, 'settings');
  select id into v_id from billing_policies where arena_id = p_arena and active
    order by created_at limit 1 for update;
  if not found then
    insert into billing_policies(arena_id, name) values (p_arena, 'Default') returning id into v_id;
  end if;
  update billing_policies set
      billing_unit = j->>'billing_unit', block_rounding = j->>'block_rounding',
      grace_minutes = (j->>'grace_minutes')::int,
      minimum_charge_minutes = (j->>'minimum_charge_minutes')::int,
      early_exit = j->>'early_exit', rounding_scope = j->>'rounding_scope',
      late_arrival = j->>'late_arrival', vr_unit_rounding = j->>'vr_unit_rounding',
      money_rounding_paise = (j->>'money_rounding_paise')::int,
      money_rounding_dir = j->>'money_rounding_dir', payment_timing = j->>'payment_timing',
      allow_extend_past_close = (j->>'allow_extend_past_close')::boolean,
      cleaning_gap_minutes = (j->>'cleaning_gap_minutes')::int,
      group_billing_mode = coalesce(j->>'group_billing_mode', 'per_system'),
      updated_at = statement_timestamp()
    where id = v_id;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- settings.save {key, json}. Only arena-wide keys sync; device-local settings
-- (notification preferences) never leave the device.
create or replace function op_settings_save(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', p->'json')
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- holiday.upsert {day, name, closed} / holiday.delete {day}
create or replace function op_holiday_upsert(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  insert into holidays(arena_id, day, name, closed)
    values (p_arena, (p->>'day')::date, p->>'name', coalesce((p->>'closed')::boolean, false))
  on conflict (arena_id, day) do update set name = excluded.name, closed = excluded.closed,
      updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function op_holiday_delete(p_arena uuid, p jsonb) returns jsonb as $$
begin
  perform _need(p_arena, 'settings');
  delete from holidays where arena_id = p_arena and day = (p->>'day')::date;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Staff
-- =============================================================================

-- At least one active person must keep the Settings permission (the client's
-- staff-screen guard, now enforced server-side — audit gap 7).
create or replace function _assert_settings_holder(p_arena uuid) returns void as $$
begin
  if not exists (select 1 from staff_profiles where arena_id = p_arena and active
                   and (role = 'owner' or 'settings' = any(perms))) then
    raise exception 'last_settings_holder'
      using hint = 'someone must keep access to Settings';
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

-- staff.update {user_id, name, perms[], active, sort_order?}: edit an EXISTING
-- member. A role='owner' profile can only be changed by an owner.
create or replace function op_staff_update(p_arena uuid, p jsonb) returns jsonb as $$
declare v_role text; v_user uuid := (p->>'user_id')::uuid;
begin
  perform _need(p_arena, 'settings');
  select role into v_role from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_role = 'owner' and not exists (select 1 from staff_profiles where arena_id = p_arena
       and user_id = auth.uid() and active and role = 'owner') then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
  end if;
  update staff_profiles set name = p->>'name',
      perms = array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb))),
      active = coalesce((p->>'active')::boolean, true),
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- Enrolment without any service-role key in the app: the person signs up with
-- their own email + password, then an owner adds that email here. Until then
-- the account can sign in but sees nothing (every policy keys off staff_profiles).
create or replace function add_staff_by_email(
  p_arena uuid, p_email text, p_name text, p_perms text[]
) returns uuid as $$
declare v_user uuid; v_id uuid;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
  end if;
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account' using hint = 'ask them to create their account first';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user, coalesce(nullif(btrim(p_name), ''), 'Staff'), 'staff',
      coalesce(p_perms, '{}'), true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, perms = excluded.perms, active = true,
        updated_at = statement_timestamp()
  returning id into v_id;
  return v_user;
end;
$$ language plpgsql security definer set search_path = public;

-- The caller's memberships (including inactive ones, so a device can say
-- "your access was turned off" instead of failing silently).
create or replace function my_arenas() returns jsonb as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'arena_id', s.arena_id, 'arena_name', a.name, 'name', s.name, 'role', s.role,
      'perms', to_jsonb(s.perms), 'active', s.active) order by a.name), '[]'::jsonb)
    from staff_profiles s join arenas a on a.id = s.arena_id
   where s.user_id = auth.uid();
$$ language sql stable security definer set search_path = public;

-- =============================================================================
-- Arena bootstrap
-- =============================================================================

-- The starter catalog (also used by seed.sql for the dev arena).
create or replace function _seed_arena_catalog(v_arena uuid) returns void as $$
declare
  v_ps5 uuid; v_vr uuid; v_pool uuid; v_lounge uuid;
  v_std uuid; v_happy uuid; v_card uuid;
  c_football uuid; c_fighting uuid; c_wrestling uuid; c_racing uuid;
  c_action uuid; c_shooter uuid; c_sports uuid; c_vr uuid; v_eafc uuid;
begin
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'PS5','PlayStation 5', true, true, 'hourly', true, 1) returning id into v_ps5;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'VR','VR (PSVR2)', false, true, 'unit', false, 2) returning id into v_vr;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'POOL','Pool', false, false, 'hourly', true, 3) returning id into v_pool;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'LOUNGE','Private Lounge', false, false, 'flat_hourly', false, 4) returning id into v_lounge;

  insert into resources(arena_id,name,kind,sort_order) values
    (v_arena,'HEX','station',1),(v_arena,'VOID','station',2),(v_arena,'GHOST','station',3),
    (v_arena,'RIFT','station',4),(v_arena,'Pool Table 1','table',5),(v_arena,'Private Lounge','room',6);
  insert into resource_activities(arena_id,resource_id,activity_id)
    select v_arena, r.id, a.id from resources r join activities a on a.arena_id = v_arena
     where r.arena_id = v_arena and (
       (r.name in ('HEX','VOID','GHOST','RIFT') and a.code = 'PS5')
       or (r.name = 'RIFT' and a.code = 'VR')
       or (r.name = 'Pool Table 1' and a.code = 'POOL')
       or (r.name = 'Private Lounge' and a.code = 'LOUNGE'));

  insert into rate_bands(arena_id,code,name) values (v_arena,'standard','Standard') returning id into v_std;
  insert into rate_bands(arena_id,code,name) values (v_arena,'happy','Happy Hour') returning id into v_happy;
  insert into rate_cards(arena_id,name) values (v_arena,'Current') returning id into v_card;
  insert into rates(arena_id,rate_card_id,activity_id,band_id,controller_count,unit_minutes,price_paise) values
    (v_arena,v_card,v_ps5,v_std,  1,60,15000),(v_arena,v_card,v_ps5,v_happy,1,60,12000),
    (v_arena,v_card,v_ps5,v_std,  2,60,28000),(v_arena,v_card,v_ps5,v_happy,2,60,22000),
    (v_arena,v_card,v_ps5,v_std,  3,60,39000),(v_arena,v_card,v_ps5,v_happy,3,60,31000),
    (v_arena,v_card,v_ps5,v_std,  4,60,48000),(v_arena,v_card,v_ps5,v_happy,4,60,38000),
    (v_arena,v_card,v_vr,v_std,  null,30,20000),
    (v_arena,v_card,v_pool,v_std, null,60,27500),(v_arena,v_card,v_pool,v_happy,null,60,22000),
    (v_arena,v_card,v_lounge,v_std,null,60,200000);
  insert into billing_policies(arena_id,name) values (v_arena,'Default');

  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Football',1) returning id into c_football;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Fighting',2) returning id into c_fighting;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Wrestling',3) returning id into c_wrestling;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Racing',4) returning id into c_racing;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Action',5) returning id into c_action;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Shooter',6) returning id into c_shooter;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Sports',7) returning id into c_sports;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'VR',8) returning id into c_vr;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Other',9);

  -- player_mode / max_local_players match lib/data/local/seed_data.dart, so the
  -- server's player-limit checks agree with the device (audit §1).
  insert into games(arena_id,name,aliases,category_id,platforms,player_mode,max_local_players) values
    (v_arena,'EA SPORTS FC 25', array['EA FC','FIFA'], c_football, array['PS5'],'both',4) returning id into v_eafc;
  insert into games(arena_id,name,aliases,category_id,platforms,player_mode,max_local_players) values
    (v_arena,'eFootball', array['PES'], c_football, array['PS5'],'both',2),
    (v_arena,'Tekken 8', '{}', c_fighting, array['PS5'],'local',2),
    (v_arena,'Mortal Kombat 1', array['MK1'], c_fighting, array['PS5'],'local',2),
    (v_arena,'Street Fighter 6', array['SF6'], c_fighting, array['PS5'],'local',2),
    (v_arena,'WWE 2K24', '{}', c_wrestling, array['PS5'],'local',4),
    (v_arena,'Gran Turismo 7', array['GT7'], c_racing, array['PS5','PSVR2'],'both',2),
    (v_arena,'F1 24', '{}', c_racing, array['PS5'],'both',2),
    (v_arena,'God of War Ragnarok', array['GOW'], c_action, array['PS5'],'single',1),
    (v_arena,'Marvel''s Spider-Man 2', array['Spiderman 2'], c_action, array['PS5'],'single',1),
    (v_arena,'GTA V', array['Grand Theft Auto V'], c_action, array['PS5'],'single',1),
    (v_arena,'Call of Duty: MW III', array['COD'], c_shooter, array['PS5'],'both',2),
    (v_arena,'Fortnite', '{}', c_shooter, array['PS5'],'online',1),
    (v_arena,'NBA 2K24', '{}', c_sports, array['PS5'],'local',4),
    (v_arena,'Beat Saber', '{}', c_vr, array['PSVR2'],'single',1),
    (v_arena,'Swordsman VR', '{}', c_vr, array['PSVR2'],'single',1);

  insert into game_controls(arena_id,game_id,section,action,buttons,explanation,sort_order) values
    (v_arena,v_eafc,'Attacking','Shoot',        array['CIRCLE'],   'Hold longer for more power', 1),
    (v_arena,v_eafc,'Attacking','Short Pass',    array['CROSS'],    null, 2),
    (v_arena,v_eafc,'Attacking','Through Ball',  array['TRIANGLE'], null, 3),
    (v_arena,v_eafc,'Attacking','Lob / Cross',   array['SQUARE'],   null, 4),
    (v_arena,v_eafc,'Attacking','Sprint',        array['R2'],       'Hold while moving', 5),
    (v_arena,v_eafc,'Defending','Tackle',        array['CIRCLE'],   null, 6),
    (v_arena,v_eafc,'Defending','Jockey',        array['L2'],       null, 7),
    (v_arena,v_eafc,'Defending','Switch Player', array['L1'],       null, 8);

  insert into controllers(arena_id, label, home_resource_id, current_resource_id, status)
    select v_arena, r.name || '-' || n::text, r.id, r.id, 'usable'
      from resources r, generate_series(1,2) as n
     where r.arena_id = v_arena and r.name in ('HEX','VOID','GHOST','RIFT');

  -- Same overrides as the device seed: EA FC not on GHOST, Tekken not on RIFT,
  -- GTA V not on HEX; pure-VR games on RIFT only.
  insert into game_resources(arena_id, game_id, resource_id, status)
    select v_arena, g.id, r.id,
      case
        when g.name = 'EA SPORTS FC 25' and r.name = 'GHOST' then 'not_playable'
        when g.name = 'Tekken 8'        and r.name = 'RIFT'  then 'not_playable'
        when g.name = 'GTA V'           and r.name = 'HEX'   then 'not_playable'
        else 'playable'
      end
      from games g
      join resources r on r.arena_id = v_arena and r.name in ('HEX','VOID','GHOST','RIFT')
     where g.arena_id = v_arena and 'PS5' = any(g.platforms);
  insert into game_resources(arena_id, game_id, resource_id, status)
    select v_arena, g.id, r.id, 'playable'
      from games g join resources r on r.arena_id = v_arena and r.name = 'RIFT'
     where g.arena_id = v_arena and 'PSVR2' = any(g.platforms) and not ('PS5' = any(g.platforms));
end;
$$ language plpgsql security definer set search_path = public;

-- create_arena: a signed-in person creates a NEW arena and becomes its owner.
-- Replaces claim_arena for clients: nobody can seize an existing arena
-- (audit gap 6). claim_arena stays for the database owner / dev bootstrap only.
create or replace function create_arena(p_name text, p_owner_name text default null)
returns uuid as $$
declare v_arena uuid;
begin
  if auth.uid() is null then raise exception 'forbidden' using errcode = '42501'; end if;
  insert into arenas(name) values (coalesce(nullif(btrim(p_name), ''), 'Arena'))
    returning id into v_arena;
  perform _seed_arena_catalog(v_arena);
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, auth.uid(), coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      array['start','bill','discount','members','stations','money','reports','settings'], true);
  return v_arena;
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- sync_push — the one write path
-- =============================================================================

create or replace function _sync_apply(p_arena uuid, p_kind text, p jsonb) returns jsonb as $$
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

-- sync_push(arena, ops, device): apply each {op_id, kind, payload} in order.
-- Per op the result is one of:
--   applied   — committed now (or earlier: replayed = true). result may carry
--               adjusted = true when the server's outcome differs in detail from
--               what the device wrote (the device then refetches the entity).
--   rejected  — a deterministic refusal (station busy, pad taken, stale, not
--               permitted, …). Recorded, so a retry gets the same answer.
--   retry     — a transient condition (lock / serialisation); nothing was
--               recorded and processing STOPS so order is preserved.
-- A caller who is not an active member gets an error for the whole call.
create or replace function sync_push(p_arena uuid, p_ops jsonb, p_device text default null)
returns jsonb as $$
declare
  v_op jsonb; v_id uuid; v_kind text; v_prev sync_ops; v_res jsonb;
  v_out jsonb := '[]'::jsonb;
  v_state text; v_msg text; v_hint text; v_code text;
begin
  if auth.uid() is null or p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  for v_op in select value from jsonb_array_elements(coalesce(p_ops, '[]'::jsonb)) loop
    v_id := (v_op->>'op_id')::uuid;
    v_kind := v_op->>'kind';
    -- Two pushes of the same op (a retry racing the original) queue here.
    perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));
    select * into v_prev from sync_ops where op_id = v_id;
    if found then
      if v_prev.arena_id <> p_arena then raise exception 'op_id_reused'; end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', v_prev.status, 'result', v_prev.result, 'error', v_prev.error_code,
        'detail', v_prev.error_message, 'replayed', true));
      continue;
    end if;
    begin
      v_res := _sync_apply(p_arena, v_kind, coalesce(v_op->'payload', '{}'::jsonb));
      if v_res is null then raise exception 'unknown_op' using hint = coalesce(v_kind, 'null'); end if;
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, result)
        values (v_id, p_arena, auth.uid(), p_device, v_kind, 'applied', v_res);
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'applied', 'result', v_res, 'replayed', false));
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text,
        v_hint = pg_exception_hint;
      if v_state in ('40001', '40P01', '55P03', '57014') then
        v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
          'status', 'retry', 'error', v_state));
        exit;
      end if;
      v_code := case
        when v_state = '42501' then 'forbidden'
        when v_state = '23505' then 'duplicate'
        when v_state = '23503' then 'missing_reference'
        when v_state in ('23514', '23502') then 'invalid'
        when v_state like '22%' then 'invalid_payload'
        when v_state = 'P0001' then v_msg
        else 'server_error' end;
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, error_code, error_message)
        values (v_id, p_arena, auth.uid(), p_device, coalesce(v_kind, '?'), 'rejected', v_code,
          coalesce(v_hint, v_msg));
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'rejected', 'error', v_code, 'detail', coalesce(v_hint, v_msg), 'replayed', false));
    end;
  end loop;
  return jsonb_build_object('results', v_out, 'server_time', clock_timestamp());
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Close every other client write path
-- =============================================================================

do $$
declare f text;
begin
  -- New internals: reachable only through sync_push.
  foreach f in array array[
    '_stale(xid8,text)','op_customer_create(uuid,jsonb)','op_customer_update(uuid,jsonb)',
    '_activity_id(uuid,text)','_booking_free(uuid,uuid,uuid,timestamptz,timestamptz)',
    'op_booking_create(uuid,jsonb)','op_booking_update(uuid,jsonb)','op_booking_set_status(uuid,jsonb)',
    'op_game_upsert(uuid,jsonb)','op_game_set_active(uuid,jsonb)','op_game_replace_controls(uuid,jsonb)',
    'op_game_set_compat(uuid,jsonb)','op_resource_upsert(uuid,jsonb)','op_resource_set_status(uuid,jsonb)',
    'op_resource_set_mode(uuid,jsonb)','op_controller_upsert(uuid,jsonb)',
    'op_controller_set_status(uuid,jsonb)','_active_card(uuid)','_band_id(uuid,text)',
    'op_rate_upsert(uuid,jsonb)','op_rate_delete(uuid,jsonb)','op_policy_save(uuid,jsonb)',
    'op_settings_save(uuid,jsonb)','op_holiday_upsert(uuid,jsonb)','op_holiday_delete(uuid,jsonb)',
    '_assert_settings_holder(uuid)','op_staff_update(uuid,jsonb)','_seed_arena_catalog(uuid)',
    '_sync_apply(uuid,text,jsonb)',
    -- Pre-sync RPCs: kept as tested building blocks, but no longer a client
    -- surface. They gate on membership only and never release pads (audit
    -- gaps 1–3), so a client must go through the op layer instead.
    'start_session(uuid,jsonb,text)',
    'reconfigure_session(uuid,timestamptz,uuid,text,uuid,int,uuid,text)',
    'extend_session(uuid,int,timestamptz,bigint,text,uuid,text)',
    'end_session(uuid,timestamptz,jsonb,bigint,boolean)',
    'record_payment(uuid,bigint,text,text,text,text,text,uuid)',
    'void_session(uuid,text)','claim_arena(uuid,text)',
    'create_group(uuid,jsonb,text)',
    'add_assignment(uuid,timestamptz,int,text,uuid,text,uuid,int,uuid,text)',
    'switch_assignment(uuid,timestamptz,int,uuid,text,uuid,int,uuid,text)',
    'end_assignment(uuid,int,timestamptz)',
    'extend_group(uuid,int,timestamptz,bigint,text,uuid,text)',
    'end_group(uuid,timestamptz,jsonb,bigint,boolean)',
    'record_group_payment(uuid,bigint,text,boolean,text,text,text,uuid)',
    'void_group(uuid,text)',
    'allocate_controllers(uuid,text,uuid[],uuid,text,timestamptz,uuid,uuid,uuid,uuid,int,text,uuid,text,boolean,text)',
    'release_controllers(uuid,uuid[],timestamptz)',
    'borrow_controllers(uuid,uuid[],uuid,text,timestamptz)',
    'move_controller(uuid,uuid,text,uuid,text,timestamptz)'
  ] loop
    execute format('revoke execute on function %s from anon, public, authenticated', f);
  end loop;
end $$;

grant execute on function sync_push(uuid, jsonb, text), add_staff_by_email(uuid, text, text, text[]),
  my_arenas(), create_arena(text, text) to authenticated;
revoke execute on function sync_push(uuid, jsonb, text), add_staff_by_email(uuid, text, text, text[]),
  my_arenas(), create_arena(text, text) from anon, public;

-- Direct table writes: none. Members keep SELECT (RLS); every insert/update goes
-- through sync_push, so no client can skip an op's checks — e.g. edit a booking
-- status under another device, re-home a pad that is in a player's hands, or
-- promote themselves in staff_profiles.
do $$
declare t text;
begin
  foreach t in array array[
    'arenas','staff_profiles','activities','resources','resource_activities','controllers',
    'customers','rate_cards','rate_bands','rates','billing_policies','holidays',
    'game_categories','games','game_controls','game_resources','bookings','settings'
  ] loop
    execute format('revoke insert, update, delete on %I from anon, authenticated', t);
  end loop;
end $$;
