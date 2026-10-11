-- arena_ops — core schema
--
-- Conventions (spec §29–§32):
--   * Money is integer paise (bigint). Never store money as float.
--   * All instants are timestamptz (UTC). Business-day logic is Asia/Kolkata and
--     lives in the application / reporting layer.
--   * Every arena-scoped table carries arena_id, created_at, updated_at.
--   * Enumerations are text + CHECK (easy to extend without enum migrations).
--   * Historical data is immutable: sessions/charges/payments/extensions are
--     never hard-deleted; voids keep the row and flip status.
--
-- This schema is a strict SUPERSET of the Drift v11 on-device schema
-- (lib/data/local/database.dart). Every Drift table/column has a typed home
-- here; the only additions are multi-tenancy (arena_id), auth linkage
-- (created_by -> auth.users) and the idempotency request_id columns.

create extension if not exists "pgcrypto"; -- gen_random_uuid()
create extension if not exists "btree_gist"; -- exclusion constraints if needed

-- updated_at helper -----------------------------------------------------------
-- Only auto-stamp when the caller did NOT supply a new updated_at. The RPCs and
-- the offline-sync layer set updated_at themselves (to one fixed
-- statement_timestamp() / the client Clock), and that value must survive so
-- conflict resolution and the pull-watermark compare true write times, not the
-- moment the trigger happened to fire.
create or replace function set_updated_at() returns trigger as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$$ language plpgsql;

-- arenas ----------------------------------------------------------------------
create table arenas (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  timezone   text not null default 'Asia/Kolkata',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger t_arenas_updated before update on arenas
  for each row execute function set_updated_at();

-- staff_profiles --------------------------------------------------------------
-- Mirrors the Drift `users` table. role is the owner/staff shortcut; perms is
-- the fine-grained capability set (the same 8 codes as the Drift
-- Permission enum: start, bill, discount, members, stations, money, reports,
-- settings). A user is an OWNER iff role='owner' OR perms overlaps
-- {money, reports} — the exact rule app_user.isOwner uses on the client.
-- The PBKDF2 PIN columns from Drift are intentionally NOT ported: Supabase Auth
-- replaces the local keypad login; the on-device users table keeps the PIN for
-- offline unlock only.
create table staff_profiles (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid not null references arenas(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  role       text not null default 'staff' check (role in ('owner','staff')),
  perms      text[] not null default '{}',
  active     boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, arena_id)
);
create index ix_staff_user on staff_profiles(user_id);
create trigger t_staff_updated before update on staff_profiles
  for each row execute function set_updated_at();

-- activities ------------------------------------------------------------------
create table activities (
  id                 uuid primary key default gen_random_uuid(),
  arena_id           uuid not null references arenas(id) on delete cascade,
  code               text not null,                       -- PS5 | VR | POOL | LOUNGE
  name               text not null,
  uses_controllers   boolean not null default false,
  uses_games         boolean not null default false,
  -- how time is priced: 'hourly' (per-hour rate), 'unit' (fixed block e.g. VR
  -- 30-min), 'flat_hourly' (lounge). The pricing engine reads the rate rows;
  -- this is a hint for the UI/new-session flow.
  duration_model     text not null default 'hourly'
                       check (duration_model in ('hourly','unit','flat_hourly')),
  happy_hour_eligible boolean not null default true,      -- §6 #10/#11
  sort_order         int not null default 0,
  active             boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (arena_id, code)
);
create trigger t_activities_updated before update on activities
  for each row execute function set_updated_at();

-- resources -------------------------------------------------------------------
-- NB: 'occupied' is DERIVED from open segments/assignments (spec §12) and is
-- NOT a stored status here. The status set equals the Drift ResourceStatus enum.
create table resources (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid not null references arenas(id) on delete cascade,
  name       text not null,                               -- HEX, VOID, RIFT ...
  kind       text not null default 'station'
               check (kind in ('station','table','room')),
  status     text not null default 'available'
               check (status in ('available','maintenance',
                                 'temporarily_unavailable','disabled')),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (arena_id, name)
);
create trigger t_resources_updated before update on resources
  for each row execute function set_updated_at();

-- controllers (loanable pads tracked per station; Drift Controllers table) ----
-- loan_session_ref holds an app string ('s:<sessionId>' / 'g:<groupId>'), not an
-- FK. current_resource_id is where the pad physically is right now.
create table controllers (
  id                  uuid primary key default gen_random_uuid(),
  arena_id            uuid not null references arenas(id) on delete cascade,
  label               text not null,
  home_resource_id    uuid not null references resources(id),
  current_resource_id uuid not null references resources(id),
  status              text not null default 'usable'
                        check (status in ('usable','faulty','missing','retired')),
  notes               text,
  loan_return_to      text,
  loan_session_ref    text,
  updated_at          timestamptz not null default now()
);
create index ix_controllers_at_station on controllers(current_resource_id, status);
create trigger t_controllers_updated before update on controllers
  for each row execute function set_updated_at();

-- resource_activities (which activities a resource can host) ------------------
-- RIFT links to both PS5 and VR; the "one open segment per resource" rule
-- (below) is what keeps PS5 and VR from running on RIFT at the same time.
create table resource_activities (
  id          uuid primary key default gen_random_uuid(),
  arena_id    uuid not null references arenas(id) on delete cascade,
  resource_id uuid not null references resources(id) on delete cascade,
  activity_id uuid not null references activities(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (resource_id, activity_id)
);
create trigger t_resource_activities_updated before update on resource_activities
  for each row execute function set_updated_at();

-- customers -------------------------------------------------------------------
create table customers (
  id            uuid primary key default gen_random_uuid(),
  arena_id      uuid not null references arenas(id) on delete cascade,
  name          text not null,
  phone         text,
  notes         text,
  last_visit_at timestamptz,
  is_guest      boolean not null default false,            -- walk-in, excluded from directory
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
-- phone unique within an arena (spec §21), but allow multiple null phones.
create unique index ux_customer_phone on customers(arena_id, phone)
  where phone is not null;
create index ix_customers_name on customers(arena_id, lower(name));
create index ix_customers_directory on customers(arena_id, name)
  where is_guest = false;
create trigger t_customers_updated before update on customers
  for each row execute function set_updated_at();

-- rate cards / bands / rates --------------------------------------------------
create table rate_cards (
  id             uuid primary key default gen_random_uuid(),
  arena_id       uuid not null references arenas(id) on delete cascade,
  name           text not null,
  effective_from timestamptz not null default now(),
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create trigger t_rate_cards_updated before update on rate_cards
  for each row execute function set_updated_at();

create table rate_bands (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid not null references arenas(id) on delete cascade,
  code       text not null,                               -- standard | happy
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (arena_id, code)
);
create trigger t_rate_bands_updated before update on rate_bands
  for each row execute function set_updated_at();

create table rates (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null references arenas(id) on delete cascade,
  rate_card_id     uuid not null references rate_cards(id) on delete cascade,
  activity_id      uuid not null references activities(id) on delete cascade,
  band_id          uuid not null references rate_bands(id) on delete cascade,
  controller_count int,                                   -- null for non-controller activities
  unit_minutes     int not null default 60,               -- 60 hourly, 30 for VR
  price_paise      bigint not null check (price_paise >= 0),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (rate_card_id, activity_id, band_id, controller_count)
);
create trigger t_rates_updated before update on rates
  for each row execute function set_updated_at();
-- One price per (card, activity, band, controller count). COALESCE because
-- Postgres, like SQLite, treats NULLs as distinct — without it two "no
-- controllers" rows could coexist and pricing would depend on row order.
create unique index ux_rate_per_combination
  on rates(rate_card_id, activity_id, band_id, coalesce(controller_count, -1));

-- billing policies (all the OWNER CONFIRMATION knobs; see docs/OWNER_CONFIRMATION.md)
create table billing_policies (
  id                      uuid primary key default gen_random_uuid(),
  arena_id                uuid not null references arenas(id) on delete cascade,
  name                    text not null,
  active                  boolean not null default true,
  billing_unit            text not null default 'per_minute'
                            check (billing_unit in ('per_minute','block_15','block_30','block_60')),
  block_rounding          text not null default 'up' check (block_rounding in ('up','nearest')),
  grace_minutes           int not null default 0,
  minimum_charge_minutes  int not null default 0,
  early_exit              text not null default 'actual' check (early_exit in ('actual','planned')),
  rounding_scope          text not null default 'session' check (rounding_scope in ('session','segment')),
  late_arrival            text not null default 'actual' check (late_arrival in ('actual','planned')),
  vr_unit_rounding        text not null default 'up' check (vr_unit_rounding in ('up','nearest','prorate')),
  money_rounding_paise    int not null default 100,        -- round to nearest ₹1
  money_rounding_dir      text not null default 'nearest' check (money_rounding_dir in ('nearest','up')),
  payment_timing          text not null default 'either' check (payment_timing in ('either','start','end')),
  allow_extend_past_close boolean not null default false,
  cleaning_gap_minutes    int not null default 0,
  group_billing_mode      text not null default 'per_system'
                            check (group_billing_mode in ('per_system','shared_controller_pool')),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create trigger t_billing_policies_updated before update on billing_policies
  for each row execute function set_updated_at();

-- holidays --------------------------------------------------------------------
-- A holiday always suspends happy hour; `closed` additionally shuts the day.
create table holidays (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid not null references arenas(id) on delete cascade,
  day        date not null,                               -- IST calendar date
  name       text not null,
  closed     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (arena_id, day)
);
create trigger t_holidays_updated before update on holidays
  for each row execute function set_updated_at();

-- game categories / games / controls ------------------------------------------
create table game_categories (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid not null references arenas(id) on delete cascade,
  name       text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (arena_id, name)
);
create trigger t_game_categories_updated before update on game_categories
  for each row execute function set_updated_at();

create table games (
  id             uuid primary key default gen_random_uuid(),
  arena_id       uuid not null references arenas(id) on delete cascade,
  name           text not null,
  aliases        text[] not null default '{}',
  category_id    uuid references game_categories(id) on delete set null,
  platforms      text[] not null default '{}',            -- e.g. {PS5}
  player_mode    text not null default 'single'
                   check (player_mode in ('single','local','online','both')),
  max_local_players int not null default 1
                   check (max_local_players between 1 and 8),
  active          boolean not null default true,
  last_played_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (arena_id, name)
);
create index ix_games_active on games(arena_id, active);
create trigger t_games_updated before update on games
  for each row execute function set_updated_at();

create table game_controls (
  id          uuid primary key default gen_random_uuid(),
  arena_id    uuid not null references arenas(id) on delete cascade,
  game_id     uuid not null references games(id) on delete cascade,
  section     text not null,                              -- Attacking, Defending ...
  action      text not null,                              -- Shoot, Short Pass ...
  buttons     text[] not null default '{}',               -- button tokens: CROSS, R2 ...
  explanation text,
  notes       text,
  image_url   text,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index ix_controls_game on game_controls(game_id, sort_order);
create trigger t_game_controls_updated before update on game_controls
  for each row execute function set_updated_at();

-- Per-system game availability (Drift game_resources). A game is never
-- "globally available": the absence of a row means not installed.
create table game_resources (
  arena_id    uuid not null references arenas(id) on delete cascade,
  game_id     uuid not null references games(id) on delete cascade,
  resource_id uuid not null references resources(id) on delete cascade,
  status      text not null
                check (status in ('playable','not_playable','not_installed',
                                  'maintenance','temporarily_unavailable')),
  notes       text,                                       -- why ("disc scratched")
  updated_at  timestamptz default now(),                  -- nullable, mirrors Drift
  primary key (game_id, resource_id)
);
create index ix_game_resources_resource on game_resources(resource_id, status);
create trigger t_game_resources_updated before update on game_resources
  for each row execute function set_updated_at();

-- bookings --------------------------------------------------------------------
create table bookings (
  id             uuid primary key default gen_random_uuid(),
  arena_id       uuid not null references arenas(id) on delete cascade,
  customer_id    uuid references customers(id) on delete set null,
  resource_id    uuid references resources(id) on delete set null,
  activity_id    uuid references activities(id) on delete set null,
  game_id        uuid references games(id) on delete set null,
  scheduled_start timestamptz not null,
  scheduled_end   timestamptz not null,
  status         text not null default 'booked'
                   check (status in ('booked','checked_in','cancelled','no_show')),
  players_required     int,
  controller_requirement int,
  party_name     text,
  phone          text,
  notes          text,
  reminder_status text not null default 'scheduled'
                   check (reminder_status in ('scheduled','off','missed','done')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (scheduled_end > scheduled_start)
);
create index ix_bookings_resource on bookings(resource_id, scheduled_start);
create trigger t_bookings_updated before update on bookings
  for each row execute function set_updated_at();

-- sessions (parent + segments) -------------------------------------------------
-- The parent owns the customer, the one authoritative time window and the
-- immutable snapshots. Per-stretch configuration (resource/activity/game/
-- controllers) lives in session_segments (0004) — the OPEN segment is the single
-- source of truth for "where this session is right now". So the parent carries
-- NO resource_id/activity_id/game_id/controller_count (matches the Drift parent).
create table sessions (
  id                uuid primary key default gen_random_uuid(),
  arena_id          uuid not null references arenas(id) on delete cascade,
  booking_id        uuid references bookings(id) on delete set null,
  customer_id       uuid not null references customers(id),
  status            text not null default 'active'
                      check (status in ('active','completed','voided')),
  payment_status    text not null default 'unpaid'
                      check (payment_status in ('unpaid','partial','paid','waived')),
  started_at        timestamptz not null,
  scheduled_end_at  timestamptz not null,
  actual_ended_at   timestamptz,
  -- Immutable snapshots captured at start (spec §31). Old sessions never change
  -- when rates/policies change later. The Drift client persists one blob with
  -- the billing policy nested under 'policy'; start_session materialises
  -- policy_snapshot from pricing_snapshot->'policy' so both are queryable.
  pricing_snapshot  jsonb not null,
  policy_snapshot   jsonb not null,
  -- Final billed amount, written at end from session_charges.
  billed_amount_paise bigint,
  void_reason       text,
  request_id        text,               -- idempotency for start
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id),
  check (scheduled_end_at > started_at),
  check (actual_ended_at is null or actual_ended_at >= started_at)
);
create index ix_sessions_arena_status on sessions(arena_id, status);
create index ix_sessions_started on sessions(arena_id, started_at);
create unique index ux_sessions_request on sessions(arena_id, request_id)
  where request_id is not null;
create trigger t_sessions_updated before update on sessions
  for each row execute function set_updated_at();

-- session_extensions (append-only history; never overwrite) -------------------
create table session_extensions (
  id                 uuid primary key default gen_random_uuid(),
  arena_id           uuid not null references arenas(id) on delete cascade,
  session_id         uuid not null references sessions(id) on delete cascade,
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
create index ix_extensions_session on session_extensions(session_id, created_at);
create unique index ux_extensions_request on session_extensions(arena_id, request_id)
  where request_id is not null;

-- session_charges (immutable final pricing segments, written at end) ----------
create table session_charges (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null references arenas(id) on delete cascade,
  session_id       uuid not null references sessions(id) on delete cascade,
  -- segment_id + resource_id are added in 0004, once session_segments exists.
  segment_index    int not null,
  band_code        text not null check (band_code in ('standard','happy')),
  activity_code    text not null,
  controller_count int,
  segment_start    timestamptz not null,
  segment_end      timestamptz not null,
  played_minutes   int not null,
  billed_minutes   int not null,
  unit_minutes     int not null,
  unit_price_paise bigint not null,
  amount_paise     bigint not null,
  created_at       timestamptz not null default now(),
  unique (session_id, segment_index),
  foreign key (arena_id, activity_code) references activities(arena_id, code)
);
create index ix_charges_session on session_charges(session_id);

-- payments (append-only; refunds are negative rows with a reason) -------------
-- amount_paise is signed: payment positive, refund negative (payment_rules
-- signedPaymentAmount). kind mirrors the Drift isRefund flag.
create table payments (
  id          uuid primary key default gen_random_uuid(),
  arena_id    uuid not null references arenas(id) on delete cascade,
  session_id  uuid not null references sessions(id) on delete cascade,
  amount_paise bigint not null,                           -- negative = refund
  method      text not null check (method in ('cash','upi','card','other')),
  kind        text not null default 'payment' check (kind in ('payment','refund')),
  note        text,
  reason      text,                                       -- required for refunds (enforced in RPC)
  request_id  text,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  -- A refund must say why; it is a correcting entry, never an edit.
  check (kind <> 'refund' or reason is not null)
);
create index ix_payments_session on payments(session_id, created_at);
create unique index ux_payments_request on payments(arena_id, request_id)
  where request_id is not null;

-- audit_log (before/after for corrections; never silently mutate — spec §33) --
create table audit_log (
  id          uuid primary key default gen_random_uuid(),
  arena_id    uuid not null references arenas(id) on delete cascade,
  entity_type text not null,
  entity_id   uuid not null,
  action      text not null,                              -- correct_game, void, etc.
  reason      text,
  before      jsonb,
  after       jsonb,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id)
);
create index ix_audit_entity on audit_log(arena_id, entity_type, entity_id);
