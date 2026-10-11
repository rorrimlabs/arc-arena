-- arena_ops — segments, group sessions, and the cross-world occupancy rule.
--
-- 0001 defines the catalog/config/parent tables (a strict superset of Drift
-- v11). This file adds the parts that only make sense once those exist:
--   1. session_segments — a session is a parent + segments; the OPEN segment is
--      where the session is right now. Resource/game/controllers live here.
--   2. group_sessions and their assignments/extensions/charges/payments — one
--      shared countdown across several players and systems.
--   3. The hard invariant "at most one OPEN segment OR assignment per resource",
--      which spans two tables and so is enforced by a row-locking trigger, not a
--      single unique index.
--
-- Everything here is additive on top of 0001; no table is dropped or rebuilt.

-- 1. session_segments ----------------------------------------------------------
-- NULL ended_at = the currently open segment. activity_code mirrors the Drift
-- model (segments reference activities by business code, not uuid); the
-- composite FK ties it to the arena's catalog. request_id gives the sync layer
-- idempotency for switch/change-game/change-controllers (reconfigure).
create table session_segments (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null references arenas(id) on delete cascade,
  session_id       uuid not null references sessions(id) on delete cascade,
  idx              int not null,
  resource_id      uuid not null references resources(id),
  activity_code    text not null,
  game_id          uuid references games(id),
  controller_count int check (controller_count between 1 and 4),
  started_at       timestamptz not null,
  ended_at         timestamptz,                             -- NULL = open
  request_id       text,
  created_at       timestamptz not null default now(),
  unique (session_id, idx),
  check (ended_at is null or ended_at >= started_at),
  foreign key (arena_id, activity_code) references activities(arena_id, code)
);
create index ix_segments_session on session_segments(session_id, idx);
create index ix_segments_resource_time on session_segments(resource_id, started_at);
create unique index ux_segments_request on session_segments(arena_id, request_id)
  where request_id is not null;
-- Mirrors the Drift index: at most one OPEN single-session segment per resource.
-- The cross-table rule (segment vs group assignment) is the trigger's job; this
-- index is the declarative backstop for the single-session case.
create unique index ux_one_open_segment_per_resource
  on session_segments(resource_id) where ended_at is null;

-- Charges can now trace back to the segment they priced.
alter table session_charges
  add column segment_id uuid references session_segments(id),
  add column resource_id uuid references resources(id);

-- 2. group sessions ------------------------------------------------------------
-- policy_snapshot + created_by added for parity with single sessions.
create table group_sessions (
  id                  uuid primary key default gen_random_uuid(),
  arena_id            uuid not null references arenas(id) on delete cascade,
  primary_customer_id uuid not null references customers(id),
  player_count        int not null check (player_count > 0),
  purchased_controller_count int not null default 0,
  status              text not null default 'active'
                        check (status in ('active','completed','voided')),
  payment_status      text not null default 'unpaid'
                        check (payment_status in ('unpaid','partial','paid','waived')),
  started_at          timestamptz not null,
  scheduled_end_at    timestamptz not null,
  actual_ended_at     timestamptz,
  pricing_snapshot    jsonb not null,
  policy_snapshot     jsonb,
  -- Captured per group so changing the policy never re-prices an old one.
  billing_mode        text not null default 'per_system'
                        check (billing_mode in ('per_system','shared_controller_pool')),
  billed_amount_paise bigint,
  void_reason         text,
  request_id          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references auth.users(id),
  check (scheduled_end_at > started_at)
);
create index ix_groups_arena_status on group_sessions(arena_id, status);
create unique index ux_groups_request on group_sessions(arena_id, request_id)
  where request_id is not null;
create trigger t_groups_updated before update on group_sessions
  for each row execute function set_updated_at();

-- One player's use of one (resource, game, controllers) for a stretch of the
-- group's window. Several are open at once — one per active player.
create table group_assignments (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null references arenas(id) on delete cascade,
  group_id         uuid not null references group_sessions(id) on delete cascade,
  player_number    int not null check (player_number > 0),
  player_label     text,
  idx              int not null,
  resource_id      uuid not null references resources(id),
  activity_code    text not null,
  game_id          uuid references games(id),
  controller_count int check (controller_count between 1 and 4),
  started_at       timestamptz not null,
  ended_at         timestamptz,
  request_id       text,
  created_at       timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at),
  foreign key (arena_id, activity_code) references activities(arena_id, code)
);
create index ix_assignments_group on group_assignments(group_id, idx);
create index ix_assignments_resource on group_assignments(resource_id, started_at);
create unique index ux_assignments_request on group_assignments(arena_id, request_id)
  where request_id is not null;

create table group_extensions (
  id                 uuid primary key default gen_random_uuid(),
  arena_id           uuid not null references arenas(id) on delete cascade,
  group_id           uuid not null references group_sessions(id) on delete cascade,
  added_minutes      int not null check (added_minutes > 0),
  old_end_at         timestamptz not null,
  new_end_at         timestamptz not null,
  added_amount_paise bigint not null default 0,
  reason             text,
  request_id         text,
  created_at         timestamptz not null default now(),
  created_by         uuid references auth.users(id),
  check (new_end_at > old_end_at)
);
create unique index ux_group_extensions_request
  on group_extensions(arena_id, request_id) where request_id is not null;

create table group_charges (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null references arenas(id) on delete cascade,
  group_id         uuid not null references group_sessions(id) on delete cascade,
  assignment_id    uuid references group_assignments(id),
  player_number    int,
  charge_index     int not null,
  band_code        text not null check (band_code in ('standard','happy')),
  activity_code    text not null,
  resource_id      uuid references resources(id),
  controller_count int,
  segment_start    timestamptz not null,
  segment_end      timestamptz not null,
  played_minutes   int not null,
  billed_minutes   int not null,
  unit_minutes     int not null,
  unit_price_paise bigint not null,
  amount_paise     bigint not null,
  created_at       timestamptz not null default now(),
  foreign key (arena_id, activity_code) references activities(arena_id, code)
);
create index ix_group_charges_group on group_charges(group_id, charge_index);

create table group_payments (
  id           uuid primary key default gen_random_uuid(),
  arena_id     uuid not null references arenas(id) on delete cascade,
  group_id     uuid not null references group_sessions(id) on delete cascade,
  amount_paise bigint not null,
  method       text not null check (method in ('cash','upi','card','other')),
  is_refund    boolean not null default false,
  note         text,
  reason       text,
  request_id   text,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  -- A refund must say why; it is a correcting entry, never an edit.
  check (not is_refund or reason is not null)
);
create index ix_group_payments_group on group_payments(group_id, created_at);
create unique index ux_group_payments_request
  on group_payments(arena_id, request_id) where request_id is not null;

-- 3. One open segment/assignment per resource, across BOTH worlds --------------
-- Occupancy now means "an open segment OR an open group assignment", living in
-- two tables, so a unique index cannot span them. A row-locking trigger does it,
-- and every caller must take the resource row lock first (the RPCs do). This is
-- the race-safe structural backstop; the RICHER co-location legality (same
-- activity+game, controller sum <= capacity, enough usable pads) is enforced in
-- the group RPCs before insert.
create or replace function assert_resource_free_for_segment()
returns trigger as $$
declare
  busy int;
begin
  if new.ended_at is not null then
    return new;
  end if;
  -- Serialise claims on this resource: two concurrent starts must not both see
  -- it free. A unique index cannot do this because occupancy spans two tables,
  -- so the lock is what makes the check sound.
  perform 1 from resources where id = new.resource_id for update;

  select count(*) into busy from (
    select 1 from session_segments
      where resource_id = new.resource_id
        and ended_at is null
        and id <> new.id
    union all
    select 1 from group_assignments
      where resource_id = new.resource_id
        and ended_at is null
  ) t;

  if busy > 0 then
    raise exception 'resource_busy'
      using hint = 'That station already has a session on it.';
  end if;
  return new;
end;
$$ language plpgsql;

-- A group assignment may share a station with another player of the SAME group
-- (co-location), but never with a single session or another group.
create or replace function assert_resource_free_for_assignment()
returns trigger as $$
declare
  busy int;
begin
  if new.ended_at is not null then
    return new;
  end if;
  perform 1 from resources where id = new.resource_id for update;

  select count(*) into busy from (
    select 1 from session_segments
      where resource_id = new.resource_id
        and ended_at is null
    union all
    select 1 from group_assignments
      where resource_id = new.resource_id
        and ended_at is null
        and group_id <> new.group_id
        and id <> new.id
  ) t;

  if busy > 0 then
    raise exception 'resource_busy'
      using hint = 'That station already has a session on it.';
  end if;
  return new;
end;
$$ language plpgsql;

create trigger t_segment_resource_free
  before insert or update of resource_id, ended_at on session_segments
  for each row execute function assert_resource_free_for_segment();

create trigger t_assignment_resource_free
  before insert or update of resource_id, ended_at on group_assignments
  for each row execute function assert_resource_free_for_assignment();

-- 4. Owner-configurable single-row config (opening hours etc.), as JSON so a new
-- config block needs no migration of its own. Drift Settings is keyed by `key`;
-- Postgres adds arena_id to the key.
create table settings (
  arena_id   uuid not null references arenas(id) on delete cascade,
  key        text not null,
  json       jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (arena_id, key)
);
create trigger t_settings_updated before update on settings
  for each row execute function set_updated_at();
