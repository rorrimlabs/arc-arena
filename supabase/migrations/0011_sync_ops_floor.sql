-- arena_ops — the multi-device write path, part 1: floor operations.
--
-- A device never writes floor tables directly. It records each operation in a
-- local outbox (same Drift transaction as the local write) and pushes it here
-- through sync_push, which applies each op ONCE (sync_ops ledger keyed by the
-- device-generated op id) inside its own savepoint. Each op_* function:
--   * checks the PERMISSION the app checks (start / bill / discount / settings /
--     owner) — not just membership (audit gap 1),
--   * re-validates everything against the server's current state (station
--     free + usable, mode lock, game playable, pad usable / at station / free,
--     untracked count-only pads, port ceiling, game player limit) — mirroring
--     ControllerAllocator and the Drift repositories rule for rule,
--   * writes session + segment + borrow moves + pad allocations (or the end +
--     charges + pad release) in ONE transaction (audit gap 3, §3),
--   * uses the row ids the device generated, so server and device rows share
--     identity,
--   * refuses stale writes where staleness changes the outcome (end / extend /
--     reconfigure carry what the device believed the session looked like).
--
-- Locking: every op locks all the stations it touches — target and the origin
-- of every borrowed pad — in uuid order, then the pads in uuid order. A
-- count-only start and a borrow from the same station therefore serialise, and
-- two ops never take the same pair of locks in opposite order.

-- Op ledger --------------------------------------------------------------------
create table sync_ops (
  op_id         uuid primary key,
  arena_id      uuid not null references arenas(id) on delete cascade,
  user_id       uuid not null,
  device_id     text,
  kind          text not null,
  status        text not null check (status in ('applied','rejected')),
  result        jsonb,
  error_code    text,
  error_message text,
  created_at    timestamptz not null default now()
);
create index ix_sync_ops_arena on sync_ops(arena_id, created_at);
alter table sync_ops enable row level security;
revoke all on sync_ops from anon, authenticated;

-- Shared helpers ---------------------------------------------------------------
create or replace function _need(p_arena uuid, p_perm text) returns void as $$
begin
  if not app_has_perm(p_arena, p_perm) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs ' || p_perm;
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

-- Lock stations in a fixed (uuid) order. Missing ids are ignored here; the
-- per-station checks report them.
create or replace function _lock_resources(p_arena uuid, p_ids uuid[]) returns void as $$
begin
  perform 1 from resources
    where arena_id = p_arena and id = any(p_ids)
    order by id for update;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function _lock_pads(p_arena uuid, p_ids uuid[]) returns void as $$
begin
  perform 1 from controllers
    where arena_id = p_arena and id = any(p_ids)
    order by id for update;
end;
$$ language plpgsql security definer set search_path = public;

-- Where the pads to be borrowed are now (read before locking; re-checked after).
create or replace function _pad_origins(p_arena uuid, p_ids uuid[]) returns uuid[] as $$
  select coalesce(array_agg(distinct current_resource_id), '{}')
    from controllers where arena_id = p_arena and id = any(p_ids);
$$ language sql stable security definer set search_path = public;

-- The station must exist and be available (Drift _ensureResourceUsable).
create or replace function _station_usable(p_arena uuid, p_resource uuid) returns void as $$
declare v_status text;
begin
  select status into v_status from resources where id = p_resource and arena_id = p_arena;
  if not found then raise exception 'resource_missing'; end if;
  if v_status <> 'available' then
    raise exception 'resource_unavailable' using hint = v_status;
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

create or replace function _game_playable(p_game uuid, p_resource uuid) returns void as $$
declare v_status text;
begin
  if p_game is null then return; end if;
  select status into v_status from game_resources where game_id = p_game and resource_id = p_resource;
  if not found or v_status <> 'playable' then
    raise exception 'not_playable' using hint = coalesce(v_status, 'not_installed');
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

create or replace function _mode_ok(p_arena uuid, p_resource uuid, p_activity text) returns void as $$
declare v_mode text;
begin
  select current_mode into v_mode from resources where id = p_resource and arena_id = p_arena;
  if v_mode is not null and v_mode <> p_activity then
    raise exception 'mode_locked' using hint = v_mode;
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

create or replace function _uses_controllers(p_arena uuid, p_activity text) returns boolean as $$
  select coalesce((select uses_controllers from activities
                    where arena_id = p_arena and code = p_activity), false);
$$ language sql stable security definer set search_path = public;

create or replace function _game_max_players(p_game uuid) returns int as $$
  select coalesce((select max_local_players from games where id = p_game), 1);
$$ language sql stable security definer set search_path = public;

-- Whether the arena tracks physical pads at all (ControllerAllocator.inventoryTracked).
create or replace function _inventory_tracked(p_arena uuid) returns boolean as $$
  select exists (select 1 from controllers where arena_id = p_arena and status <> 'retired');
$$ language sql stable security definer set search_path = public;

-- Usable pads physically at the station that no open allocation holds.
create or replace function _free_pads_at(p_arena uuid, p_resource uuid) returns int as $$
  select count(*)::int from controllers c
   where c.arena_id = p_arena and c.current_resource_id = p_resource and c.status = 'usable'
     and not exists (select 1 from controller_allocations a
                      where a.controller_id = c.id and a.ended_at is null);
$$ language sql stable security definer set search_path = public;

create or replace function _usable_pads_at(p_arena uuid, p_resource uuid) returns int as $$
  select count(*)::int from controllers
   where arena_id = p_arena and current_resource_id = p_resource and status = 'usable';
$$ language sql stable security definer set search_path = public;

-- A controller-using stretch open on the station that holds NO tracked pad: its
-- pads may be in players' hands (ControllerAllocator._untrackedBusy).
create or replace function _untracked_busy(p_arena uuid, p_resource uuid, p_except uuid[] default '{}')
returns boolean as $$
  select exists (
      select 1 from session_segments s
        join activities a on a.arena_id = s.arena_id and a.code = s.activity_code
       where s.arena_id = p_arena and s.resource_id = p_resource and s.ended_at is null
         and a.uses_controllers and not (s.id = any(p_except))
         and not exists (select 1 from controller_allocations ca
                          where ca.segment_id = s.id and ca.ended_at is null))
    or exists (
      select 1 from group_assignments g
        join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
       where g.arena_id = p_arena and g.resource_id = p_resource and g.ended_at is null
         and a.uses_controllers and not (g.id = any(p_except))
         and not exists (select 1 from controller_allocations ca
                          where ca.assignment_id = g.id and ca.ended_at is null));
$$ language sql stable security definer set search_path = public;

create or replace function _jsonb_uuids(p jsonb) returns uuid[] as $$
  select coalesce(array_agg(value::text::uuid), '{}')
    from jsonb_array_elements_text(coalesce(p, '[]'::jsonb)) value;
$$ language sql immutable;

-- Pads named by an allocation/move list ([{id, controller_id}]).
create or replace function _pad_ids(p jsonb) returns uuid[] as $$
  select coalesce(array_agg((e->>'controller_id')::uuid), '{}')
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) e;
$$ language sql immutable;

-- Borrow (ControllerAllocator.borrow): bring each pad to p_resource for the
-- session that is about to hold it. A pad already there is left alone (and its
-- move id unused). Caller holds the station + pad locks.
-- Returns how many listed moves were NOT needed (device's view was stale).
create or replace function _pad_borrow(
  p_arena uuid, p_moves jsonb, p_resource uuid, p_session_ref text, p_at timestamptz
) returns int as $$
declare
  v_now  timestamptz := statement_timestamp();
  v_m    jsonb;
  v_cid  uuid;
  v_status text; v_loc uuid; v_home uuid; v_return boolean;
  v_skipped int := 0;
begin
  for v_m in select value from jsonb_array_elements(coalesce(p_moves, '[]'::jsonb)) loop
    v_cid := (v_m->>'controller_id')::uuid;
    select status, current_resource_id, home_resource_id into v_status, v_loc, v_home
      from controllers where id = v_cid and arena_id = p_arena;
    if not found then raise exception 'controller_missing'; end if;
    if v_loc = p_resource then v_skipped := v_skipped + 1; continue; end if;
    if v_status <> 'usable' then raise exception 'controller_unusable' using hint = v_status; end if;
    if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
      raise exception 'controller_taken';
    end if;
    if _untracked_busy(p_arena, v_loc) then
      raise exception 'controller_taken' using hint = 'station_in_use';
    end if;
    v_return := v_home = p_resource;
    update controllers
       set current_resource_id = p_resource,
           loan_return_to   = case when v_return then null else v_home::text end,
           loan_session_ref = case when v_return then null else p_session_ref end,
           updated_at = v_now
     where id = v_cid;
    insert into controller_moves(id, arena_id, controller_id, from_resource_id, to_resource_id,
        kind, session_ref, moved_at, created_by, created_at)
      values (coalesce(nullif(v_m->>'id','')::uuid, gen_random_uuid()), p_arena, v_cid, v_loc,
        p_resource, case when v_return then 'returnHome' else 'loan' end,
        case when v_return then null else p_session_ref end, p_at, auth.uid(), v_now);
  end loop;
  return v_skipped;
end;
$$ language plpgsql security definer set search_path = public;

-- Allocate (ControllerAllocator.allocate): reserve each listed pad, with the
-- device's allocation ids. Caller holds the station + pad locks.
create or replace function _pad_allocate(
  p_arena uuid, p_allocs jsonb, p_scope text,
  p_session uuid, p_group uuid, p_segment uuid, p_assignment uuid,
  p_player int, p_label text, p_resource uuid, p_activity text, p_game uuid,
  p_started timestamptz
) returns void as $$
declare
  v_now timestamptz := statement_timestamp();
  v_a jsonb; v_cid uuid; v_status text; v_loc uuid;
  v_ids uuid[] := _pad_ids(p_allocs);
begin
  if coalesce(array_length(v_ids, 1), 0) = 0 then return; end if;
  if array_length(v_ids, 1) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'controller_duplicate';
  end if;
  for v_a in select value from jsonb_array_elements(p_allocs) loop
    v_cid := (v_a->>'controller_id')::uuid;
    select status, current_resource_id into v_status, v_loc
      from controllers where id = v_cid and arena_id = p_arena;
    if not found then raise exception 'controller_missing'; end if;
    if v_status <> 'usable' then raise exception 'controller_unusable' using hint = v_status; end if;
    if v_loc <> p_resource then raise exception 'controller_elsewhere'; end if;
    if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
      raise exception 'controller_taken';
    end if;
    if _untracked_busy(p_arena, p_resource, array_remove(array[p_segment, p_assignment], null)) then
      raise exception 'controller_taken' using hint = 'untracked_player';
    end if;
  end loop;
  for v_a in select value from jsonb_array_elements(p_allocs) loop
    insert into controller_allocations(id, arena_id, controller_id, scope, session_id, group_id,
        segment_id, assignment_id, player_number, player_label, resource_id, activity_code,
        game_id, started_at, created_by, created_at)
      values (coalesce(nullif(v_a->>'id','')::uuid, gen_random_uuid()), p_arena,
        (v_a->>'controller_id')::uuid, p_scope, p_session, p_group, p_segment, p_assignment,
        p_player, p_label, p_resource, p_activity, p_game, p_started, auth.uid(), v_now);
  end loop;
end;
$$ language plpgsql security definer set search_path = public;

-- Single-session controller supply (LocalSessionRepository._ensureControllerSupply).
create or replace function _single_supply(
  p_arena uuid, p_resource uuid, p_activity text, p_game uuid,
  p_pad_count int, p_count int, p_prev_resource uuid default null, p_prev_count int default null
) returns void as $$
declare v_n int; v_free int; v_max int;
begin
  perform _mode_ok(p_arena, p_resource, p_activity);
  if coalesce(p_pad_count, 0) = 0 then
    v_n := coalesce(p_count, 0);
    if v_n > 0
       and not (p_prev_resource is not distinct from p_resource and v_n <= coalesce(p_prev_count, 0))
       and _uses_controllers(p_arena, p_activity) and _inventory_tracked(p_arena) then
      v_free := _free_pads_at(p_arena, p_resource);
      if v_n > v_free then
        raise exception 'controllers_unavailable' using hint = v_free::text || ' free';
      end if;
    end if;
    return;
  end if;
  if p_count is not null and p_count <> p_pad_count then
    raise exception 'controller_count_mismatch';
  end if;
  if p_pad_count > 4 then raise exception 'controllers_exceeded'; end if;
  if p_game is not null then
    v_max := _game_max_players(p_game);
    if p_pad_count > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

create or replace function _station_free_for_single(p_resource uuid) returns void as $$
begin
  if exists (select 1 from session_segments where resource_id = p_resource and ended_at is null)
     or exists (select 1 from group_assignments where resource_id = p_resource and ended_at is null) then
    raise exception 'resource_busy';
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

-- Group assignability (LocalGroupSessionRepository._ensureAssignable), rule for
-- rule, so the server never refuses what the device allowed or vice versa.
create or replace function _group_assignable(
  p_arena uuid, p_group uuid, p_resource uuid, p_activity text, p_game uuid,
  p_cc int, p_player int, p_exclude_player int, p_borrowed int
) returns void as $$
declare
  v_used int; v_usable int; v_max int; v_others int; v_players int;
begin
  perform _station_usable(p_arena, p_resource);
  perform _mode_ok(p_arena, p_resource, p_activity);
  perform _game_playable(p_game, p_resource);
  if exists (select 1 from session_segments where resource_id = p_resource and ended_at is null) then
    raise exception 'resource_busy';
  end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id <> p_group) then
    raise exception 'resource_busy' using hint = 'another group';
  end if;
  select count(*), coalesce(sum(coalesce(controller_count, 0)), 0)
    into v_others, v_used
    from group_assignments
   where resource_id = p_resource and ended_at is null and group_id = p_group
     and not (p_exclude_player is not null and player_number = p_exclude_player);
  if v_used + p_cc > 4 then raise exception 'controllers_exceeded'; end if;
  if p_game is not null then
    v_max := _game_max_players(p_game);
    if v_used + p_cc > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
  v_usable := _usable_pads_at(p_arena, p_resource) + coalesce(p_borrowed, 0);
  if v_used + p_cc > v_usable then
    raise exception 'controllers_unavailable' using hint = v_usable::text || ' usable';
  end if;
  if v_others = 0 then return; end if;
  if not _uses_controllers(p_arena, p_activity) then raise exception 'resource_busy'; end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id = p_group
                and not (p_exclude_player is not null and player_number = p_exclude_player)
                and (activity_code is distinct from p_activity or game_id is distinct from p_game)) then
    raise exception 'game_conflict';
  end if;
  if p_game is not null then
    select count(distinct player_number) + (case when exists (
             select 1 from group_assignments where resource_id = p_resource and ended_at is null
               and group_id = p_group and player_number = p_player
               and not (p_exclude_player is not null and player_number = p_exclude_player))
           then 0 else 1 end)
      into v_players from group_assignments
     where resource_id = p_resource and ended_at is null and group_id = p_group
       and not (p_exclude_player is not null and player_number = p_exclude_player);
    if v_players > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
end;
$$ language plpgsql stable security definer set search_path = public;

create or replace function _payment_status(p_billed bigint, p_paid bigint) returns text as $$
  select case
    when p_billed is null then (case when p_paid > 0 then 'partial' else 'unpaid' end)
    when p_paid >= p_billed then 'paid'
    when p_paid > 0 then 'partial'
    else 'unpaid' end;
$$ language sql immutable;

-- Same set of ids, ignoring order and duplicates.
create or replace function _same_ids(a uuid[], b uuid[]) returns boolean as $$
  select coalesce((select array_agg(distinct x order by x) from unnest(a) x), '{}')
       = coalesce((select array_agg(distinct x order by x) from unnest(b) x), '{}');
$$ language sql immutable;

-- =============================================================================
-- Single sessions
-- =============================================================================

-- session.start {id, segment_id, customer_id, booking_id?, started_at,
--   scheduled_end_at, pricing_snapshot, resource_id, activity_code, game_id?,
--   controller_count?, allocations:[{id,controller_id}], moves:[{id,controller_id}]}
-- With booking_id the booking is checked in atomically (refused unless 'booked').
create or replace function op_session_start(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now      timestamptz := statement_timestamp();
  v_session  uuid := (p->>'id')::uuid;
  v_segment  uuid := (p->>'segment_id')::uuid;
  v_resource uuid := (p->>'resource_id')::uuid;
  v_game     uuid := nullif(p->>'game_id','')::uuid;
  v_started  timestamptz := (p->>'started_at')::timestamptz;
  v_customer uuid := (p->>'customer_id')::uuid;
  v_booking  uuid := nullif(p->>'booking_id','')::uuid;
  v_act      text := p->>'activity_code';
  v_cc       int  := nullif(p->>'controller_count','')::int;
  v_borrow   uuid[] := _pad_ids(p->'moves');
  v_pads     uuid[] := _pad_ids(p->'allocations');
  v_bstatus  text;
  v_skipped  int;
  v_origins  uuid[];
begin
  perform _need(p_arena, 'start');
  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, array[v_resource] || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  -- A pad that moved between the read and the lock sits at a station we do not
  -- hold: retry rather than check it unlocked.
  if not (_pad_origins(p_arena, v_borrow) <@ (array[v_resource] || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;

  perform _station_usable(p_arena, v_resource);
  perform _game_playable(v_game, v_resource);
  perform _single_supply(p_arena, v_resource, v_act, v_game,
    coalesce(array_length(v_pads, 1), 0), v_cc);
  perform _station_free_for_single(v_resource);

  if v_booking is not null then
    select status into v_bstatus from bookings
      where id = v_booking and arena_id = p_arena for update;
    if not found then raise exception 'booking_missing'; end if;
    if v_bstatus <> 'booked' then raise exception 'booking_not_open' using hint = v_bstatus; end if;
    update bookings set status = 'checked_in', updated_at = v_now where id = v_booking;
  end if;

  insert into sessions(id, arena_id, booking_id, customer_id, status, payment_status,
      started_at, scheduled_end_at, pricing_snapshot, policy_snapshot, request_id,
      created_by, created_at, updated_at)
    values (v_session, p_arena, v_booking, v_customer, 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      coalesce(p->'pricing_snapshot'->'policy', '{}'::jsonb), null, auth.uid(), v_now, v_now);
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
      game_id, controller_count, started_at, created_at)
    values (v_segment, p_arena, v_session, 0, v_resource, v_act, v_game, v_cc, v_started, v_now);

  v_skipped := _pad_borrow(p_arena, p->'moves', v_resource, 's:' || v_session::text, v_started);
  perform _pad_allocate(p_arena, p->'allocations', 'single', v_session, null, v_segment, null,
    null, null, v_resource, v_act, v_game, v_started);

  update customers set last_visit_at = v_started, updated_at = v_now
    where id = v_customer and arena_id = p_arena;
  if v_game is not null then
    update games set last_played_at = v_started, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;
  return jsonb_build_object('session_id', v_session, 'adjusted', v_skipped > 0);
end;
$$ language plpgsql security definer set search_path = public;

-- session.reconfigure {session_id, at, expected_segment_id, new_segment_id,
--   resource_id, activity_code, game_id?, controller_count?, allocations, moves}
-- Switch system / change game / change controllers. Refused as stale when the
-- session's open segment is not the one the device changed.
create or replace function op_session_reconfigure(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_resource uuid := (p->>'resource_id')::uuid;
  v_game uuid := nullif(p->>'game_id','')::uuid;
  v_act text := p->>'activity_code';
  v_cc int := nullif(p->>'controller_count','')::int;
  v_new uuid := (p->>'new_segment_id')::uuid;
  v_borrow uuid[] := _pad_ids(p->'moves');
  v_pads uuid[] := _pad_ids(p->'allocations');
  v_status text; v_open uuid; v_open_res uuid; v_open_start timestamptz; v_idx int; v_open_cc int;
  v_skipped int;
  v_origins uuid[];
begin
  perform _need(p_arena, 'start');
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select id, resource_id, started_at, idx, controller_count
    into v_open, v_open_res, v_open_start, v_idx, v_open_cc
    from session_segments where session_id = v_session and ended_at is null;
  if not found then raise exception 'no_open_segment'; end if;
  if v_open is distinct from nullif(p->>'expected_segment_id','')::uuid then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;
  if v_at < v_open_start then raise exception 'invalid_time'; end if;

  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, array[v_resource, v_open_res] || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  if not (_pad_origins(p_arena, v_borrow) <@ (array[v_resource, v_open_res] || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;

  if v_resource <> v_open_res then
    perform _station_usable(p_arena, v_resource);
    perform _station_free_for_single(v_resource);
  end if;
  perform _game_playable(v_game, v_resource);
  perform _single_supply(p_arena, v_resource, v_act, v_game,
    coalesce(array_length(v_pads, 1), 0), v_cc, v_open_res, v_open_cc);

  update session_segments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where segment_id = v_open and ended_at is null;
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
      game_id, controller_count, started_at, created_at)
    values (v_new, p_arena, v_session, v_idx + 1, v_resource, v_act, v_game, v_cc, v_at, v_now);
  v_skipped := _pad_borrow(p_arena, p->'moves', v_resource, 's:' || v_session::text, v_at);
  perform _pad_allocate(p_arena, p->'allocations', 'single', v_session, null, v_new, null,
    null, null, v_resource, v_act, v_game, v_at);
  update sessions set updated_at = v_now where id = v_session;
  if v_game is not null then
    update games set last_played_at = v_at, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;
  return jsonb_build_object('segment_id', v_new, 'adjusted', v_skipped > 0);
end;
$$ language plpgsql security definer set search_path = public;

-- session.extend {session_id, extension_id, added_minutes, old_end_at,
--   new_end_at, added_amount_paise, reason?}
-- Two devices extending from the same end would otherwise stack on a stale base.
create or replace function op_session_extend(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_status text; v_end timestamptz;
begin
  perform _need(p_arena, 'start');
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  if v_end <> (p->>'old_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the session was extended on another device';
  end if;
  insert into session_extensions(id, arena_id, session_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_session, (p->>'added_minutes')::int, v_end,
      (p->>'new_end_at')::timestamptz, coalesce((p->>'added_amount_paise')::bigint, 0),
      p->>'reason', auth.uid(), v_now);
  update sessions set scheduled_end_at = (p->>'new_end_at')::timestamptz, updated_at = v_now
    where id = v_session;
  return jsonb_build_object('new_end_at', p->>'new_end_at');
end;
$$ language plpgsql security definer set search_path = public;

-- session.end {session_id, ended_at, billed_amount_paise, mark_waived,
--   expected_segment_ids, expected_scheduled_end_at, charges:[{id, ...}]}
-- The bill was priced from the segments + end the device saw; if another device
-- switched or extended meanwhile, the bill is wrong — refused as stale.
-- Releases every pad the session holds (audit gap 3).
create or replace function op_session_end(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_status text; v_end timestamptz; v_segs uuid[]; v_paid bigint; v_pay text; v_c jsonb;
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select coalesce(array_agg(id), '{}') into v_segs from session_segments where session_id = v_session;
  if not _same_ids(v_segs, _jsonb_uuids(p->'expected_segment_ids'))
     or v_end <> (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;

  update session_segments set ended_at = v_ended where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = v_ended where session_id = v_session and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into session_charges(id, arena_id, session_id, segment_id, segment_index, band_code,
        activity_code, resource_id, controller_count, segment_start, segment_end, played_minutes,
        billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_session, nullif(v_c->>'segment_id','')::uuid,
        (v_c->>'segment_index')::int, v_c->>'band_code', v_c->>'activity_code',
        nullif(v_c->>'resource_id','')::uuid, nullif(v_c->>'controller_count','')::int,
        (v_c->>'segment_start')::timestamptz, (v_c->>'segment_end')::timestamptz,
        (v_c->>'played_minutes')::int, (v_c->>'billed_minutes')::int,
        (v_c->>'unit_minutes')::int, (v_c->>'unit_price_paise')::bigint,
        (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_session;
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_session;
  return jsonb_build_object('payment_status', v_pay);
end;
$$ language plpgsql security definer set search_path = public;

-- session.void {session_id, reason, at}: owner-only; releases pads. Voiding an
-- already-voided session changes nothing but asks the device to refetch.
create or replace function op_session_void(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_status text;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update session_segments set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'session', v_session, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$$ language plpgsql security definer set search_path = public;

-- payment {scope: single|group, parent_id, payment_id, amount_paise (signed as
--   recorded on the device), method, is_refund, note?, reason?}
-- Append-only; the payment id is the device's, so a retried push can never
-- charge twice (the ledger replays, and the primary key refuses a second row).
create or replace function op_payment(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_scope text := coalesce(p->>'scope', 'single');
  v_parent uuid := (p->>'parent_id')::uuid;
  v_refund boolean := coalesce((p->>'is_refund')::boolean, false);
  v_amount bigint := (p->>'amount_paise')::bigint;
  v_status text; v_pay text; v_billed bigint; v_paid bigint;
begin
  perform _need(p_arena, 'bill');
  if v_refund then perform _need(p_arena, 'discount'); end if;
  if v_amount is null or v_amount = 0 then raise exception 'amount_zero'; end if;
  if v_refund then
    if coalesce(btrim(p->>'reason'), '') = '' then raise exception 'refund_reason_required'; end if;
    v_amount := -abs(v_amount);
  elsif v_amount < 0 then
    raise exception 'amount_negative';
  end if;
  if (p->>'method') not in ('cash','upi','card','other') then raise exception 'invalid_method'; end if;

  if v_scope = 'group' then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    if v_status = 'voided' then raise exception 'voided'; end if;
    insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
        reason, created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method', v_refund,
        p->>'note', p->>'reason', auth.uid(), v_now);
    if v_pay <> 'waived' then
      select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update group_sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    if v_status = 'voided' then raise exception 'voided'; end if;
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method',
        case when v_refund then 'refund' else 'payment' end, p->>'note', p->>'reason',
        auth.uid(), v_now);
    if v_pay <> 'waived' then
      select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Group sessions
-- =============================================================================

-- Insert one assignment + its borrows + pads. Caller holds every lock.
create or replace function _group_place(
  p_arena uuid, p_group uuid, a jsonb, p_at timestamptz, p_idx int, p_exclude_player int
) returns int as $$
declare
  v_now timestamptz := statement_timestamp();
  v_res uuid := (a->>'resource_id')::uuid;
  v_game uuid := nullif(a->>'game_id','')::uuid;
  v_act text := a->>'activity_code';
  v_player int := (a->>'player_number')::int;
  v_pads uuid[] := _pad_ids(a->'allocations');
  v_npads int := coalesce(array_length(_pad_ids(a->'allocations'), 1), 0);
  v_cc int := case when v_npads > 0 then v_npads else nullif(a->>'controller_count','')::int end;
  v_aid uuid := (a->>'id')::uuid;
  v_skipped int;
begin
  perform _group_assignable(p_arena, p_group, v_res, v_act, v_game, coalesce(v_cc, 0),
    v_player, p_exclude_player, coalesce(jsonb_array_length(coalesce(a->'moves','[]'::jsonb)), 0));
  insert into group_assignments(id, arena_id, group_id, player_number, player_label, idx,
      resource_id, activity_code, game_id, controller_count, started_at, created_at)
    values (v_aid, p_arena, p_group, v_player, a->>'player_label', p_idx, v_res, v_act, v_game,
      v_cc, p_at, v_now);
  if v_game is not null then
    update games set last_played_at = p_at, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;
  v_skipped := _pad_borrow(p_arena, a->'moves', v_res, 'g:' || p_group::text, p_at);
  perform _pad_allocate(p_arena, a->'allocations', 'group', null, p_group, null, v_aid,
    v_player, a->>'player_label', v_res, v_act, v_game, p_at);
  return v_skipped;
end;
$$ language plpgsql security definer set search_path = public;

-- Every station + pad an assignment list touches, locked in order.
create or replace function _group_lock(p_arena uuid, p_assignments jsonb, p_extra uuid[] default '{}')
returns void as $$
declare
  v_res uuid[] := p_extra; v_borrow uuid[] := '{}'; v_pads uuid[] := '{}'; a jsonb;
  v_origins uuid[];
begin
  for a in select value from jsonb_array_elements(p_assignments) loop
    v_res := v_res || (a->>'resource_id')::uuid;
    v_borrow := v_borrow || _pad_ids(a->'moves');
    v_pads := v_pads || _pad_ids(a->'allocations');
  end loop;
  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, v_res || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  if not (_pad_origins(p_arena, v_borrow) <@ (v_res || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

-- group.create {id, primary_customer_id, player_count, purchased_controller_count,
--   started_at, scheduled_end_at, pricing_snapshot, billing_mode,
--   assignments:[{id, player_number, player_label?, idx, resource_id,
--   activity_code, game_id?, controller_count?, allocations, moves}]}
create or replace function op_group_create(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'id')::uuid;
  v_started timestamptz := (p->>'started_at')::timestamptz;
  v_skipped int := 0; a jsonb;
begin
  perform _need(p_arena, 'start');
  if jsonb_array_length(coalesce(p->'assignments', '[]'::jsonb)) = 0 then
    raise exception 'no_assignments';
  end if;
  perform _group_lock(p_arena, p->'assignments');
  insert into group_sessions(id, arena_id, primary_customer_id, player_count,
      purchased_controller_count, status, payment_status, started_at, scheduled_end_at,
      pricing_snapshot, policy_snapshot, billing_mode, created_by, created_at, updated_at)
    values (v_group, p_arena, (p->>'primary_customer_id')::uuid, (p->>'player_count')::int,
      coalesce((p->>'purchased_controller_count')::int, 0), 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      p->'pricing_snapshot'->'policy', coalesce(nullif(p->>'billing_mode',''), 'per_system'),
      auth.uid(), v_now, v_now);
  -- Device order: each check sees the players placed before it (as on device).
  for a in select value from jsonb_array_elements(p->'assignments') loop
    v_skipped := v_skipped + _group_place(p_arena, v_group, a, v_started,
      coalesce((a->>'idx')::int, 0), null);
  end loop;
  update customers set last_visit_at = v_started, updated_at = v_now
    where id = (p->>'primary_customer_id')::uuid and arena_id = p_arena;
  return jsonb_build_object('group_id', v_group, 'adjusted', v_skipped > 0);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function _group_active(p_arena uuid, p_group uuid) returns void as $$
declare v_status text;
begin
  select status into v_status from group_sessions where id = p_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
end;
$$ language plpgsql security definer set search_path = public;

-- group.add {group_id, at, assignment:{...}}: a player with no open assignment.
create or replace function op_group_add(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  a jsonb := p->'assignment';
  v_player int := (p->'assignment'->>'player_number')::int;
  v_idx int; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  if exists (select 1 from group_assignments
              where group_id = v_group and player_number = v_player and ended_at is null) then
    raise exception 'player_busy';
  end if;
  perform _group_lock(p_arena, jsonb_build_array(a));
  select coalesce(max(idx), -1) + 1 into v_idx from group_assignments
    where group_id = v_group and player_number = v_player;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx, null);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$$ language plpgsql security definer set search_path = public;

-- group.switch {group_id, at, player_number, expected_assignment_id, assignment:{...}}
create or replace function op_group_switch(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_player int := (p->>'player_number')::int;
  a jsonb := p->'assignment';
  v_open uuid; v_open_res uuid; v_start timestamptz; v_idx int; v_label text; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  select id, resource_id, started_at, idx, player_label
    into v_open, v_open_res, v_start, v_idx, v_label
    from group_assignments
   where group_id = v_group and player_number = v_player and ended_at is null for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  perform _group_lock(p_arena, jsonb_build_array(a), array[v_open_res]);
  -- The player keeps their label across a switch (as on the device).
  a := a || jsonb_build_object('player_number', v_player, 'player_label', v_label);
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx + 1, v_player);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$$ language plpgsql security definer set search_path = public;

-- group.end_player {group_id, player_number, at, expected_assignment_id}
create or replace function op_group_end_player(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_open uuid; v_start timestamptz;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  select id, started_at into v_open, v_start from group_assignments
   where group_id = v_group and player_number = (p->>'player_number')::int and ended_at is null
   for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- group.extend {group_id, extension_id, added_minutes, old_end_at, new_end_at,
--   added_amount_paise, reason?}
create or replace function op_group_extend(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid; v_end timestamptz;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  if v_end <> (p->>'old_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the group was extended on another device';
  end if;
  insert into group_extensions(id, arena_id, group_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_group, (p->>'added_minutes')::int, v_end,
      (p->>'new_end_at')::timestamptz, coalesce((p->>'added_amount_paise')::bigint, 0),
      p->>'reason', auth.uid(), v_now);
  update group_sessions set scheduled_end_at = (p->>'new_end_at')::timestamptz, updated_at = v_now
    where id = v_group;
  return '{}'::jsonb;
end;
$$ language plpgsql security definer set search_path = public;

-- group.end {group_id, ended_at, billed_amount_paise, mark_waived,
--   expected_assignment_ids, expected_scheduled_end_at, charges:[{id, ...}]}
create or replace function op_group_end(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_end timestamptz; v_ids uuid[]; v_paid bigint; v_pay text; v_c jsonb;
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end <> (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the group was changed on another device';
  end if;
  update group_assignments set ended_at = v_ended where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = v_ended where group_id = v_group and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into group_charges(id, arena_id, group_id, assignment_id, player_number, charge_index,
        band_code, activity_code, resource_id, controller_count, segment_start, segment_end,
        played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_group, nullif(v_c->>'assignment_id','')::uuid,
        nullif(v_c->>'player_number','')::int, (v_c->>'charge_index')::int, v_c->>'band_code',
        v_c->>'activity_code', nullif(v_c->>'resource_id','')::uuid,
        nullif(v_c->>'controller_count','')::int, (v_c->>'segment_start')::timestamptz,
        (v_c->>'segment_end')::timestamptz, (v_c->>'played_minutes')::int,
        (v_c->>'billed_minutes')::int, (v_c->>'unit_minutes')::int,
        (v_c->>'unit_price_paise')::bigint, (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_group;
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_group;
  return jsonb_build_object('payment_status', v_pay);
end;
$$ language plpgsql security definer set search_path = public;

-- group.void {group_id, reason, at}: owner-only; releases pads.
create or replace function op_group_void(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_status text;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from group_sessions where id = v_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update group_assignments set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'group_session', v_group, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$$ language plpgsql security definer set search_path = public;

-- =============================================================================
-- Pads outside a session
-- =============================================================================

-- controller.move {controller_id, kind: loan|permanent|returnHome,
--   to_resource_id?, session_ref?, at, move_id}
-- (LocalControllerAllocationRepository.moveController.) Staff carry pads
-- (loan / return); re-homing changes inventory and needs settings.
create or replace function op_controller_move(p_arena uuid, p jsonb) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp();
  v_cid uuid := (p->>'controller_id')::uuid;
  v_kind text := p->>'kind';
  v_to uuid := nullif(p->>'to_resource_id','')::uuid;
  v_loc uuid; v_home uuid;
begin
  if v_kind is null or v_kind not in ('loan','permanent','returnHome') then
    raise exception 'move_kind_invalid';
  end if;
  -- Carrying a pad (loan / return) is floor work any member does; re-homing it
  -- changes the inventory.
  if v_kind = 'permanent' then perform _need(p_arena, 'settings'); end if;
  select current_resource_id, home_resource_id into v_loc, v_home
    from controllers where id = v_cid and arena_id = p_arena;
  if not found then raise exception 'controller_missing'; end if;
  if v_kind = 'returnHome' then v_to := v_home; end if;
  if not exists (select 1 from resources where id = v_to and arena_id = p_arena) then
    raise exception 'resource_missing';
  end if;
  perform _lock_resources(p_arena, array[v_loc, v_to]);
  perform _lock_pads(p_arena, array[v_cid]);
  select current_resource_id, home_resource_id into v_loc, v_home from controllers where id = v_cid;
  if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  update controllers
     set current_resource_id = v_to,
         home_resource_id = case when v_kind = 'permanent' then v_to else home_resource_id end,
         loan_return_to   = case when v_kind = 'loan' then v_home::text end,
         loan_session_ref = case when v_kind = 'loan' then p->>'session_ref' end,
         updated_at = v_now
   where id = v_cid;
  if v_to = v_loc then
    -- Nothing physically moved (e.g. a return already done on another device):
    -- the device's history row is not mirrored, so it should refetch.
    return jsonb_build_object('moved', false, 'adjusted', nullif(p->>'move_id','') is not null);
  end if;
  insert into controller_moves(id, arena_id, controller_id, from_resource_id, to_resource_id, kind,
      session_ref, moved_at, created_by, created_at)
    values (coalesce(nullif(p->>'move_id','')::uuid, gen_random_uuid()), p_arena, v_cid, v_loc,
      v_to, v_kind, case when v_kind = 'loan' then p->>'session_ref' end,
      coalesce((p->>'at')::timestamptz, v_now), auth.uid(), v_now);
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$$ language plpgsql security definer set search_path = public;

-- Ops touch every table through SECURITY DEFINER bodies only.
do $$
declare f text;
begin
  foreach f in array array[
    '_need(uuid,text)','_lock_resources(uuid,uuid[])','_lock_pads(uuid,uuid[])',
    '_pad_origins(uuid,uuid[])','_station_usable(uuid,uuid)','_game_playable(uuid,uuid)',
    '_mode_ok(uuid,uuid,text)','_uses_controllers(uuid,text)','_game_max_players(uuid)',
    '_inventory_tracked(uuid)','_free_pads_at(uuid,uuid)','_usable_pads_at(uuid,uuid)',
    '_untracked_busy(uuid,uuid,uuid[])','_jsonb_uuids(jsonb)','_pad_ids(jsonb)',
    '_pad_borrow(uuid,jsonb,uuid,text,timestamptz)',
    '_pad_allocate(uuid,jsonb,text,uuid,uuid,uuid,uuid,int,text,uuid,text,uuid,timestamptz)',
    '_single_supply(uuid,uuid,text,uuid,int,int,uuid,int)','_station_free_for_single(uuid)',
    '_group_assignable(uuid,uuid,uuid,text,uuid,int,int,int,int)',
    '_payment_status(bigint,bigint)','_same_ids(uuid[],uuid[])',
    'op_session_start(uuid,jsonb)','op_session_reconfigure(uuid,jsonb)',
    'op_session_extend(uuid,jsonb)','op_session_end(uuid,jsonb)','op_session_void(uuid,jsonb)',
    'op_payment(uuid,jsonb)','_group_place(uuid,uuid,jsonb,timestamptz,int,int)',
    '_group_lock(uuid,jsonb,uuid[])','op_group_create(uuid,jsonb)','_group_active(uuid,uuid)',
    'op_group_add(uuid,jsonb)','op_group_switch(uuid,jsonb)','op_group_end_player(uuid,jsonb)',
    'op_group_extend(uuid,jsonb)','op_group_end(uuid,jsonb)','op_group_void(uuid,jsonb)',
    'op_controller_move(uuid,jsonb)'
  ] loop
    execute format('revoke execute on function %s from anon, public, authenticated', f);
  end loop;
end $$;
