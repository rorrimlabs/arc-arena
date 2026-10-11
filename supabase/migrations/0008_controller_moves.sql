-- arena_ops — controller location history + staff borrowing, server mirror.
--
-- Mirrors the Drift v12->v13 change: an append-only controller_moves table (one
-- row per physical carry of a pad: loan / permanent / returnHome) and the
-- borrow step that runs INSIDE a start / reconfigure / group transaction. On the
-- device that step is ControllerAllocator.borrow; here it is borrow_controllers,
-- callable on its own or folded into allocate_controllers (p_borrow => true) so
-- move + loan bookkeeping + history + allocation commit or roll back together.
-- Like 0007 these rules MIRROR the on-device enforcement; they do not replace it.

-- Location history. from_resource_id is where the pad actually was (which may
-- not be its home). session_ref is the app string 's:<sessionId>' / 'g:<groupId>'
-- (as controllers.loan_session_ref), not an FK. arena_id / created_by are
-- server-only additions for RLS and attribution.
create table controller_moves (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null references arenas(id) on delete cascade,
  controller_id    uuid not null references controllers(id),
  from_resource_id uuid not null references resources(id),
  to_resource_id   uuid not null references resources(id),
  kind             text not null check (kind in ('loan','permanent','returnHome')),
  session_ref      text,
  moved_at         timestamptz not null,
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now()
);
create index ix_moves_controller on controller_moves(controller_id, moved_at);

-- RLS: members read; writes only through the SECURITY DEFINER RPCs below.
alter table controller_moves enable row level security;
create policy p_sel_controller_moves on controller_moves for select
  using (arena_id in (select app_arena_ids()));
revoke insert, update, delete, truncate on controller_moves from authenticated, anon;
-- 0005's blanket TRUNCATE revoke ran before 0007 created controller_allocations;
-- close that gap so its append-only timeline cannot be wiped by a client either.
revoke truncate on controller_allocations from authenticated, anon;

-- borrow_controllers: physically bring pads to p_resource for the session that
-- is about to hold them (brief §5). A pad already there is left alone, so a
-- sync retry is a no-op. Each moved pad gets its location updated, owes a return
-- home (loan_return_to / loan_session_ref) unless it is arriving home, and one
-- controller_moves row with its real origin. Refused — and, being one
-- statement, rolled back as a whole — when a pad is unknown, not usable, held
-- by an open allocation, or at a station whose count-only (untracked) session
-- may have it in a player's hands. Returns the number of pads moved.
create or replace function borrow_controllers(
  p_arena          uuid,
  p_controller_ids uuid[],
  p_resource       uuid,
  p_session_ref    text,
  p_at             timestamptz
) returns int as $$
declare
  v_now    timestamptz := statement_timestamp();
  v_cid    uuid;
  v_status text;
  v_loc    uuid;
  v_home   uuid;
  v_return boolean;
  v_moved  int := 0;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform 1 from resources where id = p_resource and arena_id = p_arena;
  if not found then raise exception 'resource_missing'; end if;

  foreach v_cid in array p_controller_ids loop
    select status, current_resource_id, home_resource_id
      into v_status, v_loc, v_home
      from controllers where id = v_cid and arena_id = p_arena for update;
    if not found then raise exception 'controller_missing'; end if;
    if v_loc = p_resource then continue; end if;
    if v_status <> 'usable' then
      raise exception 'controller_unusable' using hint = v_status;
    end if;
    if exists (select 1 from controller_allocations
                 where controller_id = v_cid and ended_at is null) then
      raise exception 'controller_taken';
    end if;
    -- The origin station runs a controller-using stretch that holds no tracked
    -- pad: its pads may be in players' hands (ControllerAllocator._untrackedBusy).
    if exists (
         select 1 from session_segments s
           join activities a on a.arena_id = s.arena_id and a.code = s.activity_code
          where s.resource_id = v_loc and s.ended_at is null and a.uses_controllers
            and not exists (select 1 from controller_allocations ca
                              where ca.segment_id = s.id and ca.ended_at is null))
       or exists (
         select 1 from group_assignments g
           join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
          where g.resource_id = v_loc and g.ended_at is null and a.uses_controllers
            and not exists (select 1 from controller_allocations ca
                              where ca.assignment_id = g.id and ca.ended_at is null)) then
      raise exception 'controller_taken' using hint = 'station_in_use';
    end if;

    v_return := v_home = p_resource;
    update controllers
       set current_resource_id = p_resource,
           loan_return_to      = case when v_return then null else v_home::text end,
           loan_session_ref    = case when v_return then null else p_session_ref end
     where id = v_cid;
    insert into controller_moves(arena_id, controller_id, from_resource_id, to_resource_id,
        kind, session_ref, moved_at, created_by, created_at)
      values (p_arena, v_cid, v_loc, p_resource,
        case when v_return then 'returnHome' else 'loan' end,
        case when v_return then null else p_session_ref end,
        p_at, auth.uid(), v_now);
    v_moved := v_moved + 1;
  end loop;
  return v_moved;
end;
$$ language plpgsql security definer set search_path = public;

-- allocate_controllers gains p_borrow / p_session_ref. Drop the 0007 signature
-- first so callers never hit an ambiguous overload; every existing call (all
-- trailing params defaulted) resolves to the new one unchanged.
drop function allocate_controllers(uuid, text, uuid[], uuid, text, timestamptz,
  uuid, uuid, uuid, uuid, int, text, uuid, text);

-- allocate_controllers: reserve specific pads for a player/session (brief §3).
-- Validates membership, the RIFT mode lock, and each pad (usable, physically at
-- the station, free); request_id makes an at-least-once sync retry idempotent.
-- With p_borrow, pads elsewhere are first borrowed to p_resource (as
-- borrow_controllers) in the same transaction, so a refused pad later in the
-- list undoes every earlier move.
create or replace function allocate_controllers(
  p_arena         uuid,
  p_scope         text,
  p_controller_ids uuid[],
  p_resource      uuid,
  p_activity_code text,
  p_started_at    timestamptz,
  p_session       uuid default null,
  p_group         uuid default null,
  p_segment       uuid default null,
  p_assignment    uuid default null,
  p_player_number int  default null,
  p_player_label  text default null,
  p_game          uuid default null,
  p_request_id    text default null,
  p_borrow        boolean default false,
  p_session_ref   text default null
) returns jsonb as $$
declare
  v_now  timestamptz := statement_timestamp();
  v_mode text;
  v_cid  uuid;
  v_status text;
  v_loc  uuid;
  v_id   uuid;
  v_ids  jsonb := '[]'::jsonb;
  v_prev jsonb;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- The same pad cannot be picked twice in one call (matches the Drift guard).
  if array_length(p_controller_ids, 1) is distinct from
     (select count(distinct x) from unnest(p_controller_ids) x) then
    raise exception 'controller_duplicate';
  end if;

  if p_request_id is not null then
    select coalesce(jsonb_agg(id order by created_at), '[]'::jsonb) into v_prev
      from controller_allocations where arena_id = p_arena and request_id = p_request_id;
    if v_prev <> '[]'::jsonb then return v_prev; end if;
  end if;

  select current_mode into v_mode from resources where id = p_resource and arena_id = p_arena;
  if v_mode is not null and v_mode <> p_activity_code then
    raise exception 'mode_locked' using hint = v_mode;
  end if;

  if p_borrow then
    perform borrow_controllers(p_arena, p_controller_ids, p_resource, p_session_ref, p_started_at);
  end if;

  foreach v_cid in array p_controller_ids loop
    perform 1 from controllers where id = v_cid and arena_id = p_arena for update;
    if not found then raise exception 'controller_missing'; end if;
    select status, current_resource_id into v_status, v_loc from controllers where id = v_cid;
    if v_status <> 'usable' then raise exception 'controller_unusable' using hint = v_status; end if;
    if v_loc <> p_resource then raise exception 'controller_elsewhere'; end if;
    if exists (select 1 from controller_allocations
                 where controller_id = v_cid and ended_at is null) then
      raise exception 'controller_taken';
    end if;
  end loop;

  foreach v_cid in array p_controller_ids loop
    v_id := gen_random_uuid();
    insert into controller_allocations(id, arena_id, controller_id, scope, session_id,
        group_id, segment_id, assignment_id, player_number, player_label, resource_id,
        activity_code, game_id, started_at, request_id, created_by, created_at)
      values (v_id, p_arena, v_cid, p_scope, p_session, p_group, p_segment, p_assignment,
        p_player_number, p_player_label, p_resource, p_activity_code, p_game, p_started_at,
        p_request_id, auth.uid(), v_now);
    v_ids := v_ids || to_jsonb(v_id);
  end loop;
  return v_ids;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function
  allocate_controllers(uuid, text, uuid[], uuid, text, timestamptz, uuid, uuid, uuid, uuid,
    int, text, uuid, text, boolean, text),
  borrow_controllers(uuid, uuid[], uuid, text, timestamptz)
  from anon, public;
grant execute on function
  allocate_controllers(uuid, text, uuid[], uuid, text, timestamptz, uuid, uuid, uuid, uuid,
    int, text, uuid, text, boolean, text),
  borrow_controllers(uuid, uuid[], uuid, text, timestamptz)
  to authenticated;
