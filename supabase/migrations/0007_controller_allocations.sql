-- arena_ops — physical controller allocation (brief §3–§9), server mirror.
--
-- Mirrors the Drift v11->v12 change so the same guarantees hold once sync is
-- turned on: a specific physical pad is recorded per player/session with
-- start/end, and a pad can be in at most ONE active allocation. The live app is
-- still local-first; these rules MIRROR the on-device enforcement (they do not
-- replace it). Additive: adds resources.current_mode, widens the controller
-- status set, and adds the controller_allocations table + its RPCs.

-- RIFT PS5/VR mode lock (brief §1); null = not mode-locked.
alter table resources add column current_mode text;

-- Owner-marked out-of-service pads (brief §2, §7).
alter table controllers drop constraint if exists controllers_status_check;
alter table controllers add constraint controllers_status_check
  check (status in ('usable','faulty','missing','retired','unavailable'));

-- Append-only per-pad timeline. resource_id is where the pad is USED (which can
-- differ from the pad's physical current_resource_id after a borrow, brief §5).
create table controller_allocations (
  id            uuid primary key default gen_random_uuid(),
  arena_id      uuid not null references arenas(id) on delete cascade,
  controller_id uuid not null references controllers(id),
  scope         text not null check (scope in ('single','group')),
  session_id    uuid references sessions(id) on delete cascade,
  group_id      uuid references group_sessions(id) on delete cascade,
  segment_id    uuid references session_segments(id),
  assignment_id uuid references group_assignments(id),
  player_number int,
  player_label  text,
  resource_id   uuid not null references resources(id),
  activity_code text not null,
  game_id       uuid references games(id),
  started_at    timestamptz not null,
  ended_at      timestamptz,                 -- null = active
  request_id    text,
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at),
  foreign key (arena_id, activity_code) references activities(arena_id, code)
);
-- The double-allocation guarantee (brief §4, §9): one open row per pad.
create unique index ux_one_open_allocation_per_controller
  on controller_allocations(controller_id) where ended_at is null;
create index ix_alloc_open_by_resource
  on controller_allocations(resource_id) where ended_at is null;
create index ix_alloc_session on controller_allocations(session_id);
create index ix_alloc_group on controller_allocations(group_id);
create index ix_alloc_assignment on controller_allocations(assignment_id);
create index ix_alloc_request on controller_allocations(arena_id, request_id)
  where request_id is not null;

-- Race-safe backstop, mirroring assert_resource_free_for_segment: a pad already
-- holding an open allocation cannot take another. The caller also locks the
-- controller row FOR UPDATE, so two online devices resolve to one winner.
create or replace function assert_controller_free_for_allocation()
returns trigger as $$
declare busy int;
begin
  if new.ended_at is not null then return new; end if;
  perform 1 from controllers where id = new.controller_id for update;
  select count(*) into busy from controller_allocations
    where controller_id = new.controller_id and ended_at is null and id <> new.id;
  if busy > 0 then
    raise exception 'controller_taken'
      using hint = 'That controller is already in use.';
  end if;
  return new;
end;
$$ language plpgsql;
create trigger t_controller_free
  before insert or update of controller_id, ended_at on controller_allocations
  for each row execute function assert_controller_free_for_allocation();

-- RLS: members read; writes only through the SECURITY DEFINER RPCs below.
alter table controller_allocations enable row level security;
create policy p_sel_controller_allocations on controller_allocations for select
  using (arena_id in (select app_arena_ids()));
revoke insert, update, delete on controller_allocations from authenticated, anon;

-- allocate_controllers: reserve specific pads for a player/session (brief §3).
-- Validates membership, the RIFT mode lock, and each pad (usable, physically at
-- the station, free); request_id makes an at-least-once sync retry idempotent.
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
  p_request_id    text default null
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

-- release_controllers: end-date the open allocations for the given pads (used by
-- a move/return, and by session/group end once the end RPCs thread pad ids).
create or replace function release_controllers(
  p_arena uuid,
  p_controller_ids uuid[],
  p_at timestamptz
) returns int as $$
declare v_count int;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update controller_allocations set ended_at = p_at
    where arena_id = p_arena and ended_at is null
      and controller_id = any(p_controller_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function
  allocate_controllers(uuid, text, uuid[], uuid, text, timestamptz, uuid, uuid, uuid, uuid, int, text, uuid, text),
  release_controllers(uuid, uuid[], timestamptz)
  from anon, public;
grant execute on function
  allocate_controllers(uuid, text, uuid[], uuid, text, timestamptz, uuid, uuid, uuid, uuid, int, text, uuid, text),
  release_controllers(uuid, uuid[], timestamptz)
  to authenticated;
