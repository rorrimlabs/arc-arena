set local check_function_bodies = off;

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from
  "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from
  "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on tables from
  "authenticated";

create schema "private";

create extension "btree_gist" schema "extensions";

create sequence "public"."sync_tombstones_id_seq" as bigint increment by 1 minvalue 1 maxvalue
  9223372036854775807 START with 1 cache 1 no cycle;

create table "public"."activities" (
  "id"                  uuid                     not null default gen_random_uuid(),
  "arena_id"            uuid                     not null,
  "code"                text                     not null,
  "name"                text                     not null,
  "uses_controllers"    boolean                  not null default false,
  "uses_games"          boolean                  not null default false,
  "duration_model"      text                     not null default 'hourly'::text,
  "happy_hour_eligible" boolean                  not null default true,
  "sort_order"          integer                  not null default 0,
  "active"              boolean                  not null default true,
  "created_at"          timestamp with time zone not null default now(),
  "updated_at"          timestamp with time zone not null default now(),
  "sync_xid"            xid8                     not null default pg_current_xact_id(),
  constraint "activities_arena_id_code_key" unique (arena_id, code),
  constraint "activities_duration_model_check"
    check ((duration_model = ANY (ARRAY['hourly'::text, 'unit'::text, 'flat_hourly'::text]))),
  constraint "activities_pkey" primary key (id)
);

alter table "public"."activities"
  enable row level security;

create table "public"."arenas" (
  "id"         uuid                     not null default gen_random_uuid(),
  "name"       text                     not null,
  "timezone"   text                     not null default 'Asia/Kolkata'::text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  "area"       text,
  "phone"      text,
  constraint "arenas_area_check" check ((char_length(area) <= 80)),
  constraint "arenas_phone_check" check ((phone ~ '^[0-9+() -]{6,20}$'::text)),
  constraint "arenas_pkey" primary key (id)
);

alter table "public"."arenas"
  enable row level security;

create table "public"."audit_log" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "entity_type" text                     not null,
  "entity_id"   uuid                     not null,
  "action"      text                     not null,
  "reason"      text,
  "before"      jsonb,
  "after"       jsonb,
  "created_at"  timestamp with time zone not null default now(),
  "created_by"  uuid,
  constraint "audit_log_pkey" primary key (id)
);

alter table "public"."audit_log"
  enable row level security;

create table "public"."billing_policies" (
  "id"                      uuid                     not null default gen_random_uuid(),
  "arena_id"                uuid                     not null,
  "name"                    text                     not null,
  "active"                  boolean                  not null default true,
  "billing_unit"            text                     not null default 'per_minute'::text,
  "block_rounding"          text                     not null default 'up'::text,
  "grace_minutes"           integer                  not null default 0,
  "minimum_charge_minutes"  integer                  not null default 0,
  "early_exit"              text                     not null default 'actual'::text,
  "rounding_scope"          text                     not null default 'session'::text,
  "late_arrival"            text                     not null default 'actual'::text,
  "vr_unit_rounding"        text                     not null default 'up'::text,
  "money_rounding_paise"    integer                  not null default 100,
  "money_rounding_dir"      text                     not null default 'nearest'::text,
  "payment_timing"          text                     not null default 'either'::text,
  "allow_extend_past_close" boolean                  not null default false,
  "cleaning_gap_minutes"    integer                  not null default 0,
  "group_billing_mode"      text                     not null default 'per_system'::text,
  "created_at"              timestamp with time zone not null default now(),
  "updated_at"              timestamp with time zone not null default now(),
  "sync_xid"                xid8                     not null default pg_current_xact_id(),
  constraint "billing_policies_billing_unit_check"
    check
    ((billing_unit = ANY (ARRAY['per_minute'::text, 'block_15'::text, 'block_30'::text,
    'block_60'::text]))),
  constraint "billing_policies_block_rounding_check"
    check ((block_rounding = ANY (ARRAY['up'::text, 'nearest'::text]))),
  constraint "billing_policies_early_exit_check"
    check ((early_exit = ANY (ARRAY['actual'::text, 'planned'::text]))),
  constraint "billing_policies_group_billing_mode_check"
    check ((group_billing_mode = ANY (ARRAY['per_system'::text, 'shared_controller_pool'::text]))),
  constraint "billing_policies_late_arrival_check"
    check ((late_arrival = ANY (ARRAY['actual'::text, 'planned'::text]))),
  constraint "billing_policies_money_rounding_dir_check"
    check ((money_rounding_dir = ANY (ARRAY['nearest'::text, 'up'::text]))),
  constraint "billing_policies_payment_timing_check"
    check ((payment_timing = ANY (ARRAY['either'::text, 'start'::text, 'end'::text]))),
  constraint "billing_policies_pkey" primary key (id),
  constraint "billing_policies_rounding_scope_check"
    check ((rounding_scope = ANY (ARRAY['session'::text, 'segment'::text]))),
  constraint "billing_policies_vr_unit_rounding_check"
    check ((vr_unit_rounding = ANY (ARRAY['up'::text, 'nearest'::text, 'prorate'::text])))
);

alter table "public"."billing_policies"
  enable row level security;

create table "public"."bookings" (
  "id"                     uuid                     not null default gen_random_uuid(),
  "arena_id"               uuid                     not null,
  "customer_id"            uuid,
  "resource_id"            uuid,
  "activity_id"            uuid,
  "game_id"                uuid,
  "scheduled_start"        timestamp with time zone not null,
  "scheduled_end"          timestamp with time zone not null,
  "status"                 text                     not null default 'booked'::text,
  "players_required"       integer,
  "controller_requirement" integer,
  "party_name"             text,
  "phone"                  text,
  "notes"                  text,
  "reminder_status"        text                     not null default 'scheduled'::text,
  "created_at"             timestamp with time zone not null default now(),
  "updated_at"             timestamp with time zone not null default now(),
  "sync_xid"               xid8                     not null default pg_current_xact_id(),
  constraint "bookings_check" check ((scheduled_end > scheduled_start)),
  constraint "bookings_pkey" primary key (id),
  constraint "bookings_reminder_status_check"
    check
    ((reminder_status = ANY (ARRAY['scheduled'::text, 'off'::text, 'missed'::text, 'done'::text]))),
  constraint "bookings_status_check"
    check
    ((status = ANY (ARRAY['booked'::text, 'checked_in'::text, 'cancelled'::text, 'no_show'::text])))
);

alter table "public"."bookings"
  enable row level security;

create table "public"."controller_allocations" (
  "id"            uuid                     not null default gen_random_uuid(),
  "arena_id"      uuid                     not null,
  "controller_id" uuid                     not null,
  "scope"         text                     not null,
  "session_id"    uuid,
  "group_id"      uuid,
  "segment_id"    uuid,
  "assignment_id" uuid,
  "player_number" integer,
  "player_label"  text,
  "resource_id"   uuid                     not null,
  "activity_code" text                     not null,
  "game_id"       uuid,
  "started_at"    timestamp with time zone not null,
  "ended_at"      timestamp with time zone,
  "request_id"    text,
  "created_by"    uuid,
  "created_at"    timestamp with time zone not null default now(),
  "sync_xid"      xid8                     not null default pg_current_xact_id(),
  constraint "controller_allocations_check"
    check (((ended_at IS NULL) OR (ended_at >= started_at))),
  constraint "controller_allocations_pkey" primary key (id),
  constraint "controller_allocations_scope_check"
    check ((scope = ANY (ARRAY['single'::text, 'group'::text])))
);

alter table "public"."controller_allocations"
  enable row level security;

create table "public"."controller_moves" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "controller_id"    uuid                     not null,
  "from_resource_id" uuid                     not null,
  "to_resource_id"   uuid                     not null,
  "kind"             text                     not null,
  "session_ref"      text,
  "moved_at"         timestamp with time zone not null,
  "created_by"       uuid,
  "created_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "controller_moves_kind_check"
    check ((kind = ANY (ARRAY['loan'::text, 'permanent'::text, 'returnHome'::text]))),
  constraint "controller_moves_pkey" primary key (id)
);

alter table "public"."controller_moves"
  enable row level security;

create table "public"."controllers" (
  "id"                  uuid                     not null default gen_random_uuid(),
  "arena_id"            uuid                     not null,
  "label"               text                     not null,
  "home_resource_id"    uuid                     not null,
  "current_resource_id" uuid                     not null,
  "status"              text                     not null default 'usable'::text,
  "notes"               text,
  "loan_return_to"      text,
  "loan_session_ref"    text,
  "updated_at"          timestamp with time zone not null default now(),
  "sync_xid"            xid8                     not null default pg_current_xact_id(),
  constraint "controllers_pkey" primary key (id),
  constraint "controllers_status_check"
    check
    ((status = ANY (ARRAY['usable'::text, 'faulty'::text, 'missing'::text, 'retired'::text,
    'unavailable'::text])))
);

alter table "public"."controllers"
  enable row level security;

create table "public"."customers" (
  "id"            uuid                     not null default gen_random_uuid(),
  "arena_id"      uuid                     not null,
  "name"          text                     not null,
  "phone"         text,
  "notes"         text,
  "last_visit_at" timestamp with time zone,
  "is_guest"      boolean                  not null default false,
  "created_at"    timestamp with time zone not null default now(),
  "updated_at"    timestamp with time zone not null default now(),
  "sync_xid"      xid8                     not null default pg_current_xact_id(),
  "birth_year"    smallint,
  constraint "customers_birth_year_check" check (((birth_year >= 1900) AND (birth_year <= 2100))),
  constraint "customers_pkey" primary key (id)
);

alter table "public"."customers"
  enable row level security;

create table "public"."game_categories" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "name"       text                     not null,
  "sort_order" integer                  not null default 0,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "game_categories_arena_id_name_key" unique (arena_id, name),
  constraint "game_categories_pkey" primary key (id)
);

alter table "public"."game_categories"
  enable row level security;

create table "public"."game_controls" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "game_id"     uuid                     not null,
  "section"     text                     not null,
  "action"      text                     not null,
  "buttons"     text[]                   not null default '{}'::text[],
  "explanation" text,
  "notes"       text,
  "image_url"   text,
  "sort_order"  integer                  not null default 0,
  "created_at"  timestamp with time zone not null default now(),
  "updated_at"  timestamp with time zone not null default now(),
  "sync_xid"    xid8                     not null default pg_current_xact_id(),
  constraint "game_controls_pkey" primary key (id)
);

alter table "public"."game_controls"
  enable row level security;

create table "public"."game_resources" (
  "arena_id"    uuid                     not null,
  "game_id"     uuid                     not null,
  "resource_id" uuid                     not null,
  "status"      text                     not null,
  "notes"       text,
  "updated_at"  timestamp with time zone default now(),
  "sync_xid"    xid8                     not null default pg_current_xact_id(),
  constraint "game_resources_pkey" primary key (game_id, resource_id),
  constraint "game_resources_status_check"
    check
    ((status = ANY (ARRAY['playable'::text, 'not_playable'::text, 'not_installed'::text,
    'maintenance'::text, 'temporarily_unavailable'::text])))
);

alter table "public"."game_resources"
  enable row level security;

create table "public"."games" (
  "id"                uuid                     not null default gen_random_uuid(),
  "arena_id"          uuid                     not null,
  "name"              text                     not null,
  "aliases"           text[]                   not null default '{}'::text[],
  "category_id"       uuid,
  "platforms"         text[]                   not null default '{}'::text[],
  "player_mode"       text                     not null default 'single'::text,
  "max_local_players" integer                  not null default 1,
  "active"            boolean                  not null default true,
  "last_played_at"    timestamp with time zone,
  "created_at"        timestamp with time zone not null default now(),
  "updated_at"        timestamp with time zone not null default now(),
  "sync_xid"          xid8                     not null default pg_current_xact_id(),
  "age_rating"        smallint,
  "media"             text,
  constraint "games_age_rating_check" check ((age_rating = ANY (ARRAY[3, 7, 12, 16, 18]))),
  constraint "games_arena_id_name_key" unique (arena_id, name),
  constraint "games_max_local_players_check"
    check (((max_local_players >= 1) AND (max_local_players <= 8))),
  constraint "games_media_check" check ((media = ANY (ARRAY['digital'::text, 'disc'::text]))),
  constraint "games_pkey" primary key (id),
  constraint "games_player_mode_check"
    check ((player_mode = ANY (ARRAY['single'::text, 'local'::text, 'online'::text, 'both'::text])))
);

alter table "public"."games"
  enable row level security;

create table "public"."group_assignments" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "group_id"         uuid                     not null,
  "player_number"    integer                  not null,
  "player_label"     text,
  "idx"              integer                  not null,
  "resource_id"      uuid                     not null,
  "activity_code"    text                     not null,
  "game_id"          uuid,
  "controller_count" integer,
  "started_at"       timestamp with time zone not null,
  "ended_at"         timestamp with time zone,
  "request_id"       text,
  "created_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "group_assignments_check" check (((ended_at IS NULL) OR (ended_at >= started_at))),
  constraint "group_assignments_controller_count_check"
    check (((controller_count >= 1) AND (controller_count <= 4))),
  constraint "group_assignments_pkey" primary key (id),
  constraint "group_assignments_player_number_check" check ((player_number > 0))
);

alter table "public"."group_assignments"
  enable row level security;

create table "public"."group_charges" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "group_id"         uuid                     not null,
  "assignment_id"    uuid,
  "player_number"    integer,
  "charge_index"     integer                  not null,
  "band_code"        text                     not null,
  "activity_code"    text                     not null,
  "resource_id"      uuid,
  "controller_count" integer,
  "segment_start"    timestamp with time zone not null,
  "segment_end"      timestamp with time zone not null,
  "played_minutes"   integer                  not null,
  "billed_minutes"   integer                  not null,
  "unit_minutes"     integer                  not null,
  "unit_price_paise" bigint                   not null,
  "amount_paise"     bigint                   not null,
  "created_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "group_charges_band_code_check"
    check ((band_code = ANY (ARRAY['standard'::text, 'happy'::text]))),
  constraint "group_charges_pkey" primary key (id)
);

alter table "public"."group_charges"
  enable row level security;

create table "public"."group_extensions" (
  "id"                 uuid                     not null default gen_random_uuid(),
  "arena_id"           uuid                     not null,
  "group_id"           uuid                     not null,
  "added_minutes"      integer                  not null,
  "old_end_at"         timestamp with time zone not null,
  "new_end_at"         timestamp with time zone not null,
  "added_amount_paise" bigint                   not null default 0,
  "reason"             text,
  "request_id"         text,
  "created_at"         timestamp with time zone not null default now(),
  "created_by"         uuid,
  "sync_xid"           xid8                     not null default pg_current_xact_id(),
  constraint "group_extensions_added_minutes_check" check ((added_minutes > 0)),
  constraint "group_extensions_check" check ((new_end_at > old_end_at)),
  constraint "group_extensions_pkey" primary key (id)
);

alter table "public"."group_extensions"
  enable row level security;

create table "public"."group_payments" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "group_id"     uuid                     not null,
  "amount_paise" bigint                   not null,
  "method"       text                     not null,
  "is_refund"    boolean                  not null default false,
  "note"         text,
  "reason"       text,
  "request_id"   text,
  "created_at"   timestamp with time zone not null default now(),
  "created_by"   uuid,
  "sync_xid"     xid8                     not null default pg_current_xact_id(),
  constraint "group_payments_amount_sign_check"
    check (((amount_paise <> 0) AND (is_refund = (amount_paise < 0)))),
  constraint "group_payments_check" check (((NOT is_refund) OR (reason IS NOT NULL))),
  constraint "group_payments_method_check"
    check ((method = ANY (ARRAY['cash'::text, 'upi'::text, 'card'::text, 'other'::text]))),
  constraint "group_payments_pkey" primary key (id)
);

alter table "public"."group_payments"
  enable row level security;

create table "public"."group_sessions" (
  "id"                         uuid                     not null default gen_random_uuid(),
  "arena_id"                   uuid                     not null,
  "primary_customer_id"        uuid                     not null,
  "player_count"               integer                  not null,
  "purchased_controller_count" integer                  not null default 0,
  "status"                     text                     not null default 'active'::text,
  "payment_status"             text                     not null default 'unpaid'::text,
  "started_at"                 timestamp with time zone not null,
  "scheduled_end_at"           timestamp with time zone not null,
  "actual_ended_at"            timestamp with time zone,
  "pricing_snapshot"           jsonb                    not null,
  "policy_snapshot"            jsonb,
  "billing_mode"               text                     not null default 'per_system'::text,
  "billed_amount_paise"        bigint,
  "void_reason"                text,
  "request_id"                 text,
  "created_at"                 timestamp with time zone not null default now(),
  "updated_at"                 timestamp with time zone not null default now(),
  "created_by"                 uuid,
  "sync_xid"                   xid8                     not null default pg_current_xact_id(),
  constraint "group_sessions_billing_mode_check"
    check ((billing_mode = ANY (ARRAY['per_system'::text, 'shared_controller_pool'::text]))),
  constraint "group_sessions_check" check ((scheduled_end_at > started_at)),
  constraint "group_sessions_payment_status_check"
    check
    ((payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text, 'paid'::text, 'waived'::text]))),
  constraint "group_sessions_pkey" primary key (id),
  constraint "group_sessions_player_count_check" check ((player_count > 0)),
  constraint "group_sessions_status_check"
    check ((status = ANY (ARRAY['active'::text, 'completed'::text, 'voided'::text])))
);

alter table "public"."group_sessions"
  enable row level security;

create table "public"."holidays" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "day"        date                     not null,
  "name"       text                     not null,
  "closed"     boolean                  not null default false,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "holidays_arena_id_day_key" unique (arena_id, day),
  constraint "holidays_pkey" primary key (id)
);

alter table "public"."holidays"
  enable row level security;

create table "public"."payments" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "session_id"   uuid                     not null,
  "amount_paise" bigint                   not null,
  "method"       text                     not null,
  "kind"         text                     not null default 'payment'::text,
  "note"         text,
  "reason"       text,
  "request_id"   text,
  "created_at"   timestamp with time zone not null default now(),
  "created_by"   uuid,
  "sync_xid"     xid8                     not null default pg_current_xact_id(),
  constraint "payments_amount_sign_check"
    check (((amount_paise <> 0) AND ((kind = 'refund'::text) = (amount_paise < 0)))),
  constraint "payments_check" check (((kind <> 'refund'::text) OR (reason IS NOT NULL))),
  constraint "payments_kind_check" check ((kind = ANY (ARRAY['payment'::text, 'refund'::text]))),
  constraint "payments_method_check"
    check ((method = ANY (ARRAY['cash'::text, 'upi'::text, 'card'::text, 'other'::text]))),
  constraint "payments_pkey" primary key (id)
);

alter table "public"."payments"
  enable row level security;

create table "public"."pricing_catalog_history" (
  "arena_id"   uuid                     not null,
  "canon"      jsonb                    not null,
  "retired_at" timestamp with time zone not null
);

alter table "public"."pricing_catalog_history"
  enable row level security;

create table "public"."rate_bands" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "code"       text                     not null,
  "name"       text                     not null,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "rate_bands_arena_id_code_key" unique (arena_id, code),
  constraint "rate_bands_pkey" primary key (id)
);

alter table "public"."rate_bands"
  enable row level security;

create table "public"."rate_cards" (
  "id"             uuid                     not null default gen_random_uuid(),
  "arena_id"       uuid                     not null,
  "name"           text                     not null,
  "effective_from" timestamp with time zone not null default now(),
  "active"         boolean                  not null default true,
  "created_at"     timestamp with time zone not null default now(),
  "updated_at"     timestamp with time zone not null default now(),
  "sync_xid"       xid8                     not null default pg_current_xact_id(),
  constraint "rate_cards_pkey" primary key (id)
);

alter table "public"."rate_cards"
  enable row level security;

create table "public"."rates" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "rate_card_id"     uuid                     not null,
  "activity_id"      uuid                     not null,
  "band_id"          uuid                     not null,
  "controller_count" integer,
  "unit_minutes"     integer                  not null default 60,
  "price_paise"      bigint                   not null,
  "created_at"       timestamp with time zone not null default now(),
  "updated_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "rates_pkey" primary key (id),
  constraint "rates_price_paise_check" check ((price_paise >= 0)),
  constraint "rates_rate_card_id_activity_id_band_id_controller_count_key" unique
    (rate_card_id, activity_id, band_id, controller_count),
  constraint "rates_unit_minutes_check" check ((unit_minutes > 0))
);

alter table "public"."rates"
  enable row level security;

create table "public"."resource_activities" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "resource_id" uuid                     not null,
  "activity_id" uuid                     not null,
  "created_at"  timestamp with time zone not null default now(),
  "updated_at"  timestamp with time zone not null default now(),
  "sync_xid"    xid8                     not null default pg_current_xact_id(),
  constraint "resource_activities_pkey" primary key (id),
  constraint "resource_activities_resource_id_activity_id_key" unique (resource_id, activity_id)
);

alter table "public"."resource_activities"
  enable row level security;

create table "public"."resources" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "name"         text                     not null,
  "kind"         text                     not null default 'station'::text,
  "status"       text                     not null default 'available'::text,
  "sort_order"   integer                  not null default 0,
  "created_at"   timestamp with time zone not null default now(),
  "updated_at"   timestamp with time zone not null default now(),
  "current_mode" text,
  "sync_xid"     xid8                     not null default pg_current_xact_id(),
  constraint "resources_arena_id_name_key" unique (arena_id, name),
  constraint "resources_kind_check"
    check ((kind = ANY (ARRAY['station'::text, 'table'::text, 'room'::text]))),
  constraint "resources_pkey" primary key (id),
  constraint "resources_status_check"
    check
    ((status = ANY (ARRAY['available'::text, 'maintenance'::text, 'temporarily_unavailable'::text,
    'disabled'::text])))
);

alter table "public"."resources"
  enable row level security;

create table "public"."session_charges" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "session_id"       uuid                     not null,
  "segment_index"    integer                  not null,
  "band_code"        text                     not null,
  "activity_code"    text                     not null,
  "controller_count" integer,
  "segment_start"    timestamp with time zone not null,
  "segment_end"      timestamp with time zone not null,
  "played_minutes"   integer                  not null,
  "billed_minutes"   integer                  not null,
  "unit_minutes"     integer                  not null,
  "unit_price_paise" bigint                   not null,
  "amount_paise"     bigint                   not null,
  "created_at"       timestamp with time zone not null default now(),
  "segment_id"       uuid,
  "resource_id"      uuid,
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "session_charges_band_code_check"
    check ((band_code = ANY (ARRAY['standard'::text, 'happy'::text]))),
  constraint "session_charges_pkey" primary key (id),
  constraint "session_charges_session_id_segment_index_key" unique (session_id, segment_index)
);

alter table "public"."session_charges"
  enable row level security;

create table "public"."session_extensions" (
  "id"                 uuid                     not null default gen_random_uuid(),
  "arena_id"           uuid                     not null,
  "session_id"         uuid                     not null,
  "added_minutes"      integer                  not null,
  "old_end_at"         timestamp with time zone not null,
  "new_end_at"         timestamp with time zone not null,
  "added_amount_paise" bigint                   not null default 0,
  "reason"             text,
  "request_id"         text,
  "created_at"         timestamp with time zone not null default now(),
  "created_by"         uuid,
  "sync_xid"           xid8                     not null default pg_current_xact_id(),
  constraint "session_extensions_added_minutes_check" check ((added_minutes > 0)),
  constraint "session_extensions_check" check ((new_end_at > old_end_at)),
  constraint "session_extensions_pkey" primary key (id)
);

alter table "public"."session_extensions"
  enable row level security;

create table "public"."session_segments" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "session_id"       uuid                     not null,
  "idx"              integer                  not null,
  "resource_id"      uuid                     not null,
  "activity_code"    text                     not null,
  "game_id"          uuid,
  "controller_count" integer,
  "started_at"       timestamp with time zone not null,
  "ended_at"         timestamp with time zone,
  "request_id"       text,
  "created_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "session_segments_check" check (((ended_at IS NULL) OR (ended_at >= started_at))),
  constraint "session_segments_controller_count_check"
    check (((controller_count >= 1) AND (controller_count <= 4))),
  constraint "session_segments_pkey" primary key (id),
  constraint "session_segments_session_id_idx_key" unique (session_id, idx)
);

alter table "public"."session_segments"
  enable row level security;

create table "public"."sessions" (
  "id"                  uuid                     not null default gen_random_uuid(),
  "arena_id"            uuid                     not null,
  "booking_id"          uuid,
  "customer_id"         uuid                     not null,
  "status"              text                     not null default 'active'::text,
  "payment_status"      text                     not null default 'unpaid'::text,
  "started_at"          timestamp with time zone not null,
  "scheduled_end_at"    timestamp with time zone not null,
  "actual_ended_at"     timestamp with time zone,
  "pricing_snapshot"    jsonb                    not null,
  "policy_snapshot"     jsonb                    not null,
  "billed_amount_paise" bigint,
  "void_reason"         text,
  "request_id"          text,
  "created_at"          timestamp with time zone not null default now(),
  "updated_at"          timestamp with time zone not null default now(),
  "created_by"          uuid,
  "sync_xid"            xid8                     not null default pg_current_xact_id(),
  constraint "sessions_check1"
    check (((actual_ended_at IS NULL) OR (actual_ended_at >= started_at))),
  constraint "sessions_check" check ((scheduled_end_at > started_at)),
  constraint "sessions_payment_status_check"
    check
    ((payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text, 'paid'::text, 'waived'::text]))),
  constraint "sessions_pkey" primary key (id),
  constraint "sessions_status_check"
    check ((status = ANY (ARRAY['active'::text, 'completed'::text, 'voided'::text])))
);

alter table "public"."sessions"
  enable row level security;

create table "public"."settings" (
  "arena_id"   uuid                     not null,
  "key"        text                     not null,
  "json"       jsonb                    not null,
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "settings_pkey" primary key (arena_id, key)
);

alter table "public"."settings"
  enable row level security;

create table "public"."staff_invites" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "email"       text                     not null,
  "name"        text                     not null,
  "role"        text                     not null,
  "perms"       text[]                   not null default '{}'::text[],
  "token_hash"  bytea                    not null,
  "invited_by"  uuid                     not null,
  "created_at"  timestamp with time zone not null default statement_timestamp(),
  "expires_at"  timestamp with time zone not null,
  "accepted_at" timestamp with time zone,
  "accepted_by" uuid,
  "revoked_at"  timestamp with time zone,
  constraint "staff_invites_email_check"
    check (((email = lower(btrim(email))) AND (POSITION(('@'::text) IN (email)) > 1))),
  constraint "staff_invites_name_check"
    check (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 80))),
  constraint "staff_invites_one_outcome" check (((accepted_at IS NULL) OR (revoked_at IS NULL))),
  constraint "staff_invites_pkey" primary key (id),
  constraint "staff_invites_role_check" check ((role = ANY (ARRAY['owner'::text, 'staff'::text]))),
  constraint "staff_invites_token_hash_check" check ((length(token_hash) = 32))
);

alter table "public"."staff_invites"
  enable row level security;

create table "public"."staff_profiles" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "user_id"    uuid                     not null,
  "name"       text                     not null,
  "role"       text                     not null default 'staff'::text,
  "perms"      text[]                   not null default '{}'::text[],
  "active"     boolean                  not null default true,
  "sort_order" integer                  not null default 0,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "staff_profiles_pkey" primary key (id),
  constraint "staff_profiles_role_check" check ((role = ANY (ARRAY['owner'::text, 'staff'::text]))),
  constraint "staff_profiles_user_id_arena_id_key" unique (user_id, arena_id)
);

alter table "public"."staff_profiles"
  enable row level security;

create table "public"."sync_ops" (
  "op_id"         uuid                     not null,
  "arena_id"      uuid                     not null,
  "user_id"       uuid                     not null,
  "device_id"     text,
  "kind"          text                     not null,
  "status"        text                     not null,
  "result"        jsonb,
  "error_code"    text,
  "error_message" text,
  "created_at"    timestamp with time zone not null default now(),
  constraint "sync_ops_pkey" primary key (op_id),
  constraint "sync_ops_status_check"
    check ((status = ANY (ARRAY['applied'::text, 'rejected'::text])))
);

alter table "public"."sync_ops"
  enable row level security;

create table "public"."sync_tombstones" (
  "id"         bigint
    not null default nextval('public.sync_tombstones_id_seq'::regclass),
  "arena_id"   uuid                     not null,
  "table_name" text                     not null,
  "row_key"    jsonb                    not null,
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  "deleted_at" timestamp with time zone not null default now(),
  constraint "sync_tombstones_pkey" primary key (id)
);

alter table "public"."sync_tombstones"
  enable row level security;

alter table "public"."pricing_catalog_history"
  add column "canon_md5" text generated always as (md5((canon)::text)) stored not null;

alter sequence "public"."sync_tombstones_id_seq" owned by "public"."sync_tombstones"."id";

create or replace function private.accept_invite (
  p_invite uuid,
  p_token  text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_inv       staff_invites%rowtype;
  v_email     text;
  v_confirmed timestamptz;
  v_allowed   boolean;
begin
  if auth.uid() is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  select * into v_inv from staff_invites where id = p_invite for update;
  if not found or p_token is null
     or extensions.digest(p_token, 'sha256') <> v_inv.token_hash then
    raise exception 'invite_invalid' using hint = 'this invitation link is not valid';
  end if;
  if v_inv.accepted_at is not null then
    raise exception 'invite_used' using hint = 'this invitation was already accepted';
  end if;
  if v_inv.revoked_at is not null then
    raise exception 'invite_revoked' using hint = 'this invitation was withdrawn';
  end if;
  if v_inv.expires_at <= statement_timestamp() then
    raise exception 'invite_expired' using hint = 'ask for a new invitation';
  end if;
  select lower(email), email_confirmed_at into v_email, v_confirmed
    from auth.users where id = auth.uid();
  if v_email is distinct from v_inv.email then
    raise exception 'invite_wrong_account' using errcode = '42501',
      hint = 'sign in with the e-mail address the invitation was sent to';
  end if;
  if v_confirmed is null then
    raise exception 'email_not_confirmed' using hint = 'confirm your e-mail address first';
  end if;
  -- The inviter's authority is re-checked now: an invite from someone who has
  -- since lost Settings (or ownership) must not still work.
  if v_inv.role = 'owner' then
    v_allowed := exists (select 1 from staff_profiles where arena_id = v_inv.arena_id
                           and user_id = v_inv.invited_by and active and role = 'owner');
  else
    v_allowed := exists (select 1 from staff_profiles where arena_id = v_inv.arena_id
                           and user_id = v_inv.invited_by and active
                           and (role = 'owner' or 'settings' = any(perms))
                           and (not (v_inv.perms && array['money', 'reports'])
                                or role = 'owner' or perms && array['money', 'reports']));
  end if;
  if not v_allowed then
    raise exception 'invite_invalid'
      using hint = 'the person who invited you can no longer add members';
  end if;
  if exists (select 1 from staff_profiles where arena_id = v_inv.arena_id
              and user_id = auth.uid() and role = 'owner') then
    raise exception 'owner_profile' using hint = 'you are already an owner of this arena';
  end if;
  insert into staff_profiles (arena_id, user_id, name, role, perms, active)
    values (v_inv.arena_id, auth.uid(), v_inv.name, v_inv.role, v_inv.perms, true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, role = excluded.role, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  perform _assert_settings_holder(v_inv.arena_id);
  update staff_invites set accepted_at = statement_timestamp(), accepted_by = auth.uid()
   where id = v_inv.id;
  return jsonb_build_object(
    'arena_id', v_inv.arena_id,
    'arena_name', (select name from arenas where id = v_inv.arena_id),
    'role', v_inv.role);
end;
$function$;

create or replace function private.app_arena_ids()
  returns SETOF uuid
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  -- `and active` matches the client's PermissionGuard active gate and the
  -- role-aware helpers: a deactivated staff member loses all access server-side.
  select arena_id from staff_profiles where user_id = auth.uid() and active;
$function$;

create or replace function private.app_arena_ids_with (
  p_any text[]
)
  returns SETOF uuid
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select arena_id from staff_profiles
   where user_id = auth.uid() and active and (role = 'owner' or perms && p_any);
$function$;

create or replace function private.app_has_perm (
  p_arena uuid,
  p_perm  text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or p_perm = any(perms))
  );
$function$;

create or replace function private.app_is_owner (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or perms && array['money','reports'])
  );
$function$;

create or replace function private.arena_invites (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list invites';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'invite_id', i.id, 'email', i.email, 'name', i.name, 'role', i.role,
        'perms', to_jsonb(i.perms), 'created_at', i.created_at, 'expires_at', i.expires_at,
        'expired', i.expires_at <= statement_timestamp(),
        'invited_by_name', s.name) order by i.created_at desc)
      from staff_invites i
      left join staff_profiles s on s.arena_id = i.arena_id and s.user_id = i.invited_by
     where i.arena_id = p_arena and i.accepted_at is null and i.revoked_at is null
  ), '[]'::jsonb);
end;
$function$;

create or replace function private.arena_pricing (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read pricing';
  end if;
  return jsonb_build_object(
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', a.id, 'code', a.code, 'name', a.name,
          'uses_controllers', a.uses_controllers, 'uses_games', a.uses_games,
          'duration_model', a.duration_model, 'happy_hour_eligible', a.happy_hour_eligible,
          'sort_order', a.sort_order, 'active', a.active,
          'stations', (select count(*) from resource_activities ra
                         join resources r on r.id = ra.resource_id
                        where ra.activity_id = a.id and r.status <> 'disabled'))
        order by a.sort_order, lower(a.name))
        from activities a where a.arena_id = p_arena), '[]'::jsonb),
    'rates', coalesce((
      select jsonb_agg(jsonb_build_object('activity_code', v.activity_code, 'band', v.band,
          'controller_count', v.controller_count, 'unit_minutes', v.unit_minutes,
          'price_paise', v.price_paise)
        order by v.activity_code, v.band, v.controller_count nulls first)
        from sync_v_rates v where v.arena_id = p_arena), '[]'::jsonb),
    'hours', _pricing_snapshot(p_arena)->'hours');
end;
$function$;

create or replace function private.arena_sale (
  p_arena uuid,
  p_id    uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_bill jsonb;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read sales';
  end if;
  select b into v_bill from _sales(p_arena, null, null, p_id) b;
  if v_bill is null then raise exception 'not_found' using hint = 'bill'; end if;

  if v_bill->>'kind' = 'single' then
    v_bill := v_bill || jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player', null, 'station', r.name, 'activity', coalesce(a.name, ch.activity_code),
            'band', ch.band_code, 'controllers', ch.controller_count,
            'start', ch.segment_start, 'end', ch.segment_end,
            'played_minutes', ch.played_minutes, 'billed_minutes', ch.billed_minutes,
            'unit_minutes', ch.unit_minutes, 'unit_price_paise', ch.unit_price_paise,
            'amount_paise', ch.amount_paise)
          order by ch.segment_start, ch.segment_index)
          from session_charges ch
          left join resources r on r.id = ch.resource_id
          left join activities a on a.arena_id = ch.arena_id and a.code = ch.activity_code
         where ch.session_id = p_id), '[]'::jsonb),
      'extensions', coalesce((
        select jsonb_agg(jsonb_build_object('at', e.created_at, 'added_minutes', e.added_minutes,
            'added_amount_paise', e.added_amount_paise, 'reason', e.reason, 'by', sp.name)
          order by e.created_at)
          from session_extensions e
          left join staff_profiles sp on sp.arena_id = e.arena_id and sp.user_id = e.created_by
         where e.session_id = p_id), '[]'::jsonb));
  else
    v_bill := v_bill || jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player', ch.player_number, 'station', r.name, 'activity', coalesce(a.name, ch.activity_code),
            'band', ch.band_code, 'controllers', ch.controller_count,
            'start', ch.segment_start, 'end', ch.segment_end,
            'played_minutes', ch.played_minutes, 'billed_minutes', ch.billed_minutes,
            'unit_minutes', ch.unit_minutes, 'unit_price_paise', ch.unit_price_paise,
            'amount_paise', ch.amount_paise)
          order by ch.segment_start, ch.player_number, ch.charge_index)
          from group_charges ch
          left join resources r on r.id = ch.resource_id
          left join activities a on a.arena_id = ch.arena_id and a.code = ch.activity_code
         where ch.group_id = p_id), '[]'::jsonb),
      'extensions', coalesce((
        select jsonb_agg(jsonb_build_object('at', e.created_at, 'added_minutes', e.added_minutes,
            'added_amount_paise', e.added_amount_paise, 'reason', e.reason, 'by', sp.name)
          order by e.created_at)
          from group_extensions e
          left join staff_profiles sp on sp.arena_id = e.arena_id and sp.user_id = e.created_by
         where e.group_id = p_id), '[]'::jsonb));
  end if;

  return v_bill || jsonb_build_object(
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('at', l.created_at, 'action', l.action, 'by', sp.name,
          'reason', l.reason, 'before', l.before, 'after', l.after)
        order by l.created_at, l.id)
        from audit_log l
        left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
       where l.arena_id = p_arena and l.entity_id = p_id
         and l.entity_type = case when v_bill->>'kind' = 'group' then 'group_session' else 'session' end),
      '[]'::jsonb),
    'voided', (
      select jsonb_build_object('at', l.created_at, 'by', sp.name, 'reason', l.reason)
        from audit_log l
        left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
       where l.arena_id = p_arena and l.entity_id = p_id and l.action = 'void'
       order by l.created_at limit 1));
end;
$function$;

create or replace function private.arena_sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list sales';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '93 days' then
    raise exception 'invalid_range' using hint = 'from < to, at most 93 days';
  end if;
  return coalesce((
    select jsonb_agg(b order by (b->>'at')::timestamptz desc, b->>'id')
      from _sales(p_arena, p_from, p_to) b), '[]'::jsonb);
end;
$function$;

create or replace function private.arena_staff (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_since timestamptz := statement_timestamp() - interval '30 days';
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list staff';
  end if;
  return coalesce((
    with money as (
      select created_by, 's:' || session_id::text as bill, amount_paise
        from payments where arena_id = p_arena and created_at >= v_since
      union all
      select created_by, 'g:' || group_id::text, amount_paise
        from group_payments where arena_id = p_arena and created_at >= v_since
    ), per as (
      select created_by,
             count(distinct bill) filter (where amount_paise > 0) as bills,
             coalesce(sum(amount_paise), 0) as net,
             coalesce(-sum(amount_paise) filter (where amount_paise < 0), 0) as refunds
        from money group by created_by
    )
    select jsonb_agg(jsonb_build_object(
        'user_id', s.user_id, 'name', s.name, 'email', u.email, 'role', s.role,
        'perms', to_jsonb(s.perms), 'active', s.active,
        'invited', u.last_sign_in_at is null,
        'bills_30d', coalesce(p.bills, 0), 'takings_30d_paise', coalesce(p.net, 0),
        'refunds_30d_paise', coalesce(p.refunds, 0))
      order by s.role = 'owner' desc, lower(s.name))
      from staff_profiles s
      join auth.users u on u.id = s.user_id
      left join per p on p.created_by = s.user_id
     where s.arena_id = p_arena), '[]'::jsonb);
end;
$function$;

create or replace function private.can_use_arena_topic (
  p_topic text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select case
    when p_topic ~ '^arena:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (select 1 from staff_profiles
                  where user_id = auth.uid() and active and arena_id = substr(p_topic, 7)::uuid)
    else false
  end;
$function$;

create or replace function private.create_my_arena (
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_user      uuid := auth.uid();
  v_confirmed timestamptz;
  v_arena     text := btrim(coalesce(p_arena_name, ''));
  v_owner     text := btrim(coalesce(p_owner_name, ''));
begin
  if v_user is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  select email_confirmed_at into v_confirmed from auth.users where id = v_user;
  if not found then
    raise exception 'no_account' using hint = 'sign up again';
  end if;
  if v_confirmed is null then
    raise exception 'account_not_confirmed'
      using hint = 'enter the code we e-mailed you to confirm the address';
  end if;
  if v_arena = '' or length(v_arena) > 80 then
    raise exception 'invalid_name' using hint = 'the arena name must be 1 to 80 characters';
  end if;
  if v_owner = '' or length(v_owner) > 80 then
    raise exception 'invalid_name' using hint = 'your name must be 1 to 80 characters';
  end if;
  -- Serialise this login's calls until commit, then check what it already owns.
  perform pg_advisory_xact_lock(hashtextextended('create_my_arena:' || v_user::text, 0));
  if exists (select 1 from staff_profiles where user_id = v_user and role = 'owner') then
    raise exception 'arena_limit' using hint = 'this login already owns an arena';
  end if;
  return _create_arena_with_owner(v_user, v_arena, v_owner);
end;
$function$;

create or replace function private.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_name    text := btrim(coalesce(p_name, ''));
  v_owner   boolean;
  v_perms   text[];
  v_token   text;
  v_id      uuid;
  v_expires timestamptz := statement_timestamp() + interval '7 days';
begin
  if auth.uid() is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  if p_role is null or p_role not in ('staff', 'owner') then
    raise exception 'invalid_role' using hint = 'role must be staff or owner';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email' using hint = 'enter a valid e-mail address';
  end if;
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid_name' using hint = 'the name must be 1 to 80 characters';
  end if;
  v_owner := exists (select 1 from staff_profiles where arena_id = p_arena
                       and user_id = auth.uid() and active and role = 'owner');
  if p_role = 'owner' then
    if not v_owner then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can invite an owner';
    end if;
    v_perms := _known_perms();
  else
    perform _need(p_arena, 'settings');
    perform _assert_known_perms(p_perms);
    v_perms := coalesce(p_perms, '{}');
    if v_perms && array['money', 'reports'] and not private.app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports';
    end if;
  end if;
  if exists (select 1 from auth.users where id = auth.uid() and lower(email) = v_email) then
    raise exception 'forbidden' using errcode = '42501', hint = 'you cannot invite yourself';
  end if;
  if not v_owner and exists (select 1 from staff_invites where arena_id = p_arena
       and email = v_email and role = 'owner' and accepted_at is null and revoked_at is null) then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'an owner invited this address; only an owner can replace that invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp()
   where arena_id = p_arena and email = v_email and accepted_at is null and revoked_at is null;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into staff_invites (arena_id, email, name, role, perms, token_hash, invited_by, expires_at)
    values (p_arena, v_email, v_name, p_role, v_perms,
            extensions.digest(v_token, 'sha256'), auth.uid(), v_expires)
    returning id into v_id;
  return jsonb_build_object('invite_id', v_id, 'token', v_token, 'expires_at', v_expires);
end;
$function$;

create or replace function private.my_arenas()
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'arena_id', s.arena_id, 'arena_name', a.name, 'name', s.name, 'role', s.role,
      'perms', to_jsonb(s.perms), 'active', s.active) order by a.name), '[]'::jsonb)
    from staff_profiles s join arenas a on a.id = s.arena_id
   where s.user_id = auth.uid();
$function$;

create or replace function private.revoke_invite (
  p_arena  uuid,
  p_invite uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_role text;
begin
  perform _need(p_arena, 'settings');
  select role into v_role from staff_invites
   where id = p_invite and arena_id = p_arena and accepted_at is null and revoked_at is null
     for update;
  if not found then
    raise exception 'not_found' using hint = 'invite';
  end if;
  if v_role = 'owner' and not exists (select 1 from staff_profiles where arena_id = p_arena
       and user_id = auth.uid() and active and role = 'owner') then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can withdraw an owner invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp() where id = p_invite;
end;
$function$;

create or replace function private.sync_fetch_entity (
  p_arena uuid,
  p_refs  jsonb
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_ref  jsonb;
  v_id   uuid;
  v_rows jsonb;
  v_out  jsonb := '[]'::jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  for v_ref in select value from jsonb_array_elements(coalesce(p_refs, '[]'::jsonb)) loop
    v_id := nullif(v_ref->>'id', '')::uuid;
    -- controller_moves point at their session/group via session_ref
    -- ('s:<session id>' or 'g:<group id>'), not a uuid column.
    v_rows := case v_ref->>'type'
      when 'session' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','sessions','r',to_jsonb(s)) x from sessions s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','session_segments','r',to_jsonb(s)) from session_segments s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','session_extensions','r',to_jsonb(s)) from session_extensions s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','session_charges','r',to_jsonb(s)) from session_charges s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','payments','r',to_jsonb(s)) from payments s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.session_ref = 's:' || v_id::text
        ) q)
      when 'group' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','group_sessions','r',to_jsonb(s)) x from group_sessions s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','group_assignments','r',to_jsonb(s)) from group_assignments s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_extensions','r',to_jsonb(s)) from group_extensions s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_charges','r',to_jsonb(s)) from group_charges s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_payments','r',to_jsonb(s)) from group_payments s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.session_ref = 'g:' || v_id::text
        ) q)
      when 'controller' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','controllers','r',to_jsonb(s)) x from controllers s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.controller_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.controller_id = v_id and s.ended_at is null
        ) q)
      when 'customer' then (
        select coalesce(jsonb_agg(jsonb_build_object('t','customers','r',to_jsonb(s))), '[]'::jsonb)
          from customers s where s.arena_id = p_arena and s.id = v_id)
      when 'booking' then (
        select coalesce(jsonb_agg(jsonb_build_object('t','bookings','r',to_jsonb(s))), '[]'::jsonb)
          from sync_v_bookings s where s.arena_id = p_arena and s.id = v_id)
      else '[]'::jsonb
    end;
    v_out := v_out || jsonb_build_array(jsonb_build_object('ref', v_ref, 'rows', v_rows));
  end loop;
  return v_out;
end;
$function$;

create or replace function private.sync_pull (
  p_arena  uuid,
  p_cursor text    default '0'::text,
  p_limit  integer default 2000
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_union text;
  v_out   jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 then p_limit := 2000; end if;

  select string_agg(format(
      'select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s '
      'where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)',
      name, rel), ' union all ')
    into v_union from _sync_sources();

  -- Upper bound is the snapshot's xmin, so a row from a transaction still open
  -- now is never skipped by a later cursor. Pages are cut on a sync_xid
  -- boundary: a transaction's changes never span two pages, and the first
  -- transaction is always included even if it alone exceeds p_limit.
  execute
    'with snap as (select pg_snapshot_xmin(pg_current_snapshot()) as hi), '
    'ch as (' || v_union ||
    ' union all select ''_tombstone'', s.sync_xid, '
    '  jsonb_build_object(''table'', s.table_name, ''row'', s.row_key) '
    '  from sync_tombstones s '
    '  where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)), '
    'g as (select x, count(*) as c from ch group by x), '
    'cum as (select x, c, sum(c) over (order by x) as run from g), '
    'cut as (select coalesce((select min(x) from cum where run - c > 0 and run > $3), '
    '                        (select hi from snap)) as upper) '
    'select jsonb_build_object('
    '  ''cursor'', (select upper from cut)::text, '
    '  ''has_more'', (select upper from cut) < (select hi from snap), '
    '  ''server_time'', clock_timestamp(), '
    '  ''changes'', coalesce((select jsonb_agg(jsonb_build_object(''t'', t, ''r'', r) order by x) '
    '                         from ch where x < (select upper from cut)), ''[]''::jsonb))'
    into v_out
    using p_arena, p_cursor::xid8, p_limit;
  return v_out;
end;
$function$;

create or replace function private.sync_push (
  p_arena  uuid,
  p_ops    jsonb,
  p_device text  default null::text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_op jsonb; v_id uuid; v_kind text; v_prev sync_ops; v_res jsonb;
  v_out jsonb := '[]'::jsonb;
  v_state text; v_msg text; v_hint text; v_code text;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
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
      -- Transient (serialization failure, deadlock, lock not available, query
      -- cancelled): not recorded, so the device resends this op and the rest later.
      if v_state in ('40001', '40P01', '55P03', '57014') then
        v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
          'status', 'retry', 'error', v_state));
        exit;
      end if;
      -- Stable error code for the device: a plain `raise exception '<code>'`
      -- (P0001) passes its message through; known SQLSTATEs are mapped.
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
$function$;

create or replace function public._active_card (
  p_arena uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v uuid;
begin
  select id into v from rate_cards where arena_id = p_arena and active
    order by effective_from desc limit 1;
  if not found then
    insert into rate_cards(arena_id, name) values (p_arena, 'Current') returning id into v;
  end if;
  return v;
end;
$function$;

create or replace function public._activity_id (
  p_arena uuid,
  p_code  text
)
  returns uuid
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v uuid;
begin
  select id into v from activities where arena_id = p_arena and code = p_code;
  if not found then raise exception 'activity_missing' using hint = coalesce(p_code, 'null'); end if;
  return v;
end;
$function$;

create or replace function public._assert_known_perms (
  p_perms text[]
)
  returns void
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
begin
  if exists (select 1 from unnest(coalesce(p_perms, '{}')) x where x <> all(_known_perms())) then
    raise exception 'invalid_permission'
      using hint = 'permissions must be among ' || array_to_string(_known_perms(), ', ');
  end if;
end;
$function$;

create or replace function public._assert_same_arena()
  returns trigger
  language plpgsql
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._assert_settings_holder (
  p_arena uuid
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not exists (select 1 from staff_profiles where arena_id = p_arena and active
                   and (role = 'owner' or 'settings' = any(perms))) then
    raise exception 'last_settings_holder'
      using hint = 'someone must keep access to Settings';
  end if;
end;
$function$;

create or replace function public._assert_snapshot (
  p_arena uuid,
  s       jsonb
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare c jsonb := _pricing_canon(s);
begin
  if s is null or jsonb_typeof(s) <> 'object' then
    raise exception 'pricing_snapshot_mismatch' using hint = 'no price list was sent';
  end if;
  if c = _pricing_canon(_pricing_snapshot(p_arena)) then return; end if;
  if exists (select 1 from pricing_catalog_history
              where arena_id = p_arena and canon_md5 = md5(c::text) and canon = c
                and retired_at >= statement_timestamp() - _pricing_grace()) then
    return;
  end if;
  raise exception 'pricing_snapshot_mismatch'
    using hint = 'the price list on this device is not the arena''s; sync and start again';
end;
$function$;

create or replace function public._band_id (
  p_arena uuid,
  p_code  text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v uuid;
begin
  select id into v from rate_bands where arena_id = p_arena and code = p_code;
  if not found then
    insert into rate_bands(arena_id, code, name) values (p_arena, p_code, initcap(p_code))
      returning id into v;
  end if;
  return v;
end;
$function$;

create or replace function public._booking_free (
  p_arena    uuid,
  p_id       uuid,
  p_resource uuid,
  p_start    timestamp with time zone,
  p_end      timestamp with time zone
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  if p_resource is null then return; end if;
  perform 1 from resources where id = p_resource and arena_id = p_arena for update;
  if exists (select 1 from bookings
              where arena_id = p_arena and resource_id = p_resource and status = 'booked'
                and id <> p_id and scheduled_start < p_end and scheduled_end > p_start) then
    raise exception 'booking_conflict';
  end if;
end;
$function$;

create or replace function public._create_arena_with_owner (
  p_user       uuid,
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_arena uuid;
begin
  insert into arenas(name) values (coalesce(nullif(btrim(p_arena_name), ''), 'Arena'))
    returning id into v_arena;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, p_user, coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      array['start','bill','discount','members','stations','money','reports','settings'], true);
  return v_arena;
end;
$function$;

create or replace function public._floor_options (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  v_methods text[];
  v_presets int[];
  v_warn    numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('payment_methods', 'start_presets', 'warn_minutes')) then
    raise exception 'invalid_floor_options'
      using hint = 'an object of payment_methods, start_presets and warn_minutes';
  end if;

  if jsonb_typeof(p->'payment_methods') is distinct from 'array' then
    raise exception 'invalid_floor_options' using hint = 'payment_methods';
  end if;
  select array_agg(distinct m order by m) into v_methods
    from jsonb_array_elements_text(p->'payment_methods') m;
  if v_methods is null or not (v_methods <@ array['cash', 'upi', 'card', 'other']) then
    raise exception 'invalid_floor_options'
      using hint = 'payment_methods: one or more of cash, upi, card, other';
  end if;

  if jsonb_typeof(p->'start_presets') is distinct from 'array'
     or exists (select 1 from jsonb_array_elements(p->'start_presets') e
                 where jsonb_typeof(e) <> 'number' or (e::text)::numeric % 1 <> 0) then
    raise exception 'invalid_floor_options' using hint = 'start_presets: whole minutes';
  end if;
  select array_agg(distinct (e::text)::int order by (e::text)::int) into v_presets
    from jsonb_array_elements(p->'start_presets') e;
  if v_presets is null or cardinality(v_presets) > 8
     or exists (select 1 from unnest(v_presets) x where x < 5 or x > 720) then
    raise exception 'invalid_floor_options'
      using hint = 'start_presets: 1–8 durations of 5–720 minutes';
  end if;

  if jsonb_typeof(p->'warn_minutes') is distinct from 'number' then
    raise exception 'invalid_floor_options' using hint = 'warn_minutes';
  end if;
  v_warn := (p->>'warn_minutes')::numeric;
  if v_warn % 1 <> 0 or v_warn < 1 or v_warn > 30 then
    raise exception 'invalid_floor_options' using hint = 'warn_minutes: 1–30';
  end if;

  return jsonb_build_object('payment_methods', to_jsonb(v_methods),
    'start_presets', to_jsonb(v_presets), 'warn_minutes', v_warn::int);
end;
$function$;

create or replace function public._free_pads_at (
  p_arena    uuid,
  p_resource uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::int from controllers c
   where c.arena_id = p_arena and c.current_resource_id = p_resource and c.status = 'usable'
     and not exists (select 1 from controller_allocations a
                      where a.controller_id = c.id and a.ended_at is null);
$function$;

create or replace function public._game_max_players (
  p_game uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select coalesce((select max_local_players from games where id = p_game), 1);
$function$;

create or replace function public._game_playable (
  p_game     uuid,
  p_resource uuid
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  if p_game is null then return; end if;
  select status into v_status from game_resources where game_id = p_game and resource_id = p_resource;
  if not found or v_status <> 'playable' then
    raise exception 'not_playable' using hint = coalesce(v_status, 'not_installed');
  end if;
end;
$function$;

create or replace function public._group_active (
  p_arena uuid,
  p_group uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  select status into v_status from group_sessions where id = p_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
end;
$function$;

create or replace function public._group_assignable (
  p_arena          uuid,
  p_group          uuid,
  p_resource       uuid,
  p_activity       text,
  p_game           uuid,
  p_cc             integer,
  p_player         integer,
  p_exclude_player integer,
  p_borrowed       integer
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
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
  -- Sharing a station with this group's other players: controller activities only, same activity and game.
  if not _uses_controllers(p_arena, p_activity) then raise exception 'resource_busy'; end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id = p_group
                and not (p_exclude_player is not null and player_number = p_exclude_player)
                and (activity_code is distinct from p_activity or game_id is distinct from p_game)) then
    raise exception 'game_conflict';
  end if;
  if p_game is not null then
    -- Distinct players on the station after placing p_player (+1 unless already there).
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
$function$;

create or replace function public._group_lock (
  p_arena       uuid,
  p_assignments jsonb,
  p_extra       uuid[] default '{}'::uuid[]
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
  -- Stations before pads, each in id order (same order as the single-session ops).
  perform _lock_resources(p_arena, v_res || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  -- A pad that moved between the read and the lock sits at a station we do not hold: retry.
  if not (_pad_origins(p_arena, v_borrow) <@ (v_res || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;
end;
$function$;

create or replace function public._group_place (
  p_arena          uuid,
  p_group          uuid,
  a                jsonb,
  p_at             timestamp with time zone,
  p_idx            integer,
  p_exclude_player integer
)
  returns integer
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._inventory_tracked (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (select 1 from controllers where arena_id = p_arena and status <> 'retired');
$function$;

create or replace function public._jsonb_uuids (
  p jsonb
)
  returns uuid[]
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select coalesce(array_agg(value::text::uuid), '{}')
    from jsonb_array_elements_text(coalesce(p, '[]'::jsonb)) value;
$function$;

create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings'];
$function$;

create or replace function public._lock_pads (
  p_arena uuid,
  p_ids   uuid[]
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform 1 from controllers
    where arena_id = p_arena and id = any(p_ids)
    order by id for update;
end;
$function$;

create or replace function public._lock_resources (
  p_arena uuid,
  p_ids   uuid[]
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform 1 from resources
    where arena_id = p_arena and id = any(p_ids)
    order by id for update;
end;
$function$;

create or replace function public._mode_ok (
  p_arena    uuid,
  p_resource uuid,
  p_activity text
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_mode text;
begin
  select current_mode into v_mode from resources where id = p_resource and arena_id = p_arena;
  if v_mode is not null and v_mode <> p_activity then
    raise exception 'mode_locked' using hint = v_mode;
  end if;
end;
$function$;

create or replace function public._need (
  p_arena uuid,
  p_perm  text
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_has_perm(p_arena, p_perm) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs ' || p_perm;
  end if;
end;
$function$;

create or replace function public._pad_allocate (
  p_arena      uuid,
  p_allocs     jsonb,
  p_scope      text,
  p_session    uuid,
  p_group      uuid,
  p_segment    uuid,
  p_assignment uuid,
  p_player     integer,
  p_label      text,
  p_resource   uuid,
  p_activity   text,
  p_game       uuid,
  p_started    timestamp with time zone
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._pad_borrow (
  p_arena       uuid,
  p_moves       jsonb,
  p_resource    uuid,
  p_session_ref text,
  p_at          timestamp with time zone
)
  returns integer
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._pad_ids (
  p jsonb
)
  returns uuid[]
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select coalesce(array_agg((e->>'controller_id')::uuid), '{}')
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) e;
$function$;

create or replace function public._pad_origins (
  p_arena uuid,
  p_ids   uuid[]
)
  returns uuid[]
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select coalesce(array_agg(distinct current_resource_id), '{}')
    from controllers where arena_id = p_arena and id = any(p_ids);
$function$;

create or replace function public._payment_status (
  p_billed bigint,
  p_paid   bigint
)
  returns text
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select case
    when p_billed is null then (case when p_paid > 0 then 'partial' else 'unpaid' end)
    when p_paid >= p_billed then 'paid'
    when p_paid > 0 then 'partial'
    else 'unpaid' end;
$function$;

create or replace function public._pr_ceil_step (
  v    bigint,
  step integer
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select case when step <= 1 then v else ((v + step - 1) / step) * step end;
$function$;

create or replace function public._pr_charge_key (
  p_act    text,
  p_res    uuid,
  p_cc     integer,
  p_band   text,
  p_start  timestamp with time zone,
  p_end    timestamp with time zone,
  p_played bigint,
  p_billed bigint,
  p_um     integer,
  p_price  bigint,
  p_amount bigint
)
  returns text
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select concat_ws('|', p_act, coalesce(p_res::text, '-'), coalesce(p_cc::text, '-'), p_band,
    (extract(epoch from p_start) * 1000000)::bigint, (extract(epoch from p_end) * 1000000)::bigint,
    p_played, p_billed, p_um, p_price, p_amount);
$function$;

create or replace function public._pr_div (
  n bigint,
  d bigint
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select (2 * n + d) / (2 * d);
$function$;

create or replace function public._pr_group_bill (
  p_group    uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  g group_sessions; v_snap jsonb; pol jsonb; r uuid; part jsonb; q jsonb; v_act text;
  v_sub bigint := 0; v_keys text[] := '{}';
begin
  select * into g from group_sessions where id = p_group;
  v_snap := g.pricing_snapshot;
  pol := _pr_policy(v_snap);
  if g.billing_mode = 'shared_controller_pool' then
    -- The purchased controllers, once, over the whole group window.
    select activity_code into v_act from group_assignments
     where group_id = p_group and controller_count is not null
     order by player_number, idx limit 1;
    if g.purchased_controller_count > 0 and v_act is not null and p_open_end > g.started_at then
      q := _pr_quote(v_snap, v_act, g.purchased_controller_count, g.started_at, p_open_end);
      if q is not null then
        v_sub := v_sub + (q->>'subtotal')::bigint;
        v_keys := v_keys || _pr_keys(q, v_act, null, g.purchased_controller_count);
      end if;
    end if;
  end if;
  for r in select distinct resource_id from group_assignments where group_id = p_group loop
    part := _pr_sweep(v_snap, p_group, r, p_open_end, g.billing_mode = 'shared_controller_pool');
    v_sub := v_sub + (part->>'subtotal')::bigint;
    v_keys := v_keys || array(select jsonb_array_elements_text(part->'keys'));
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')));
end;
$function$;

create or replace function public._pr_happy (
  s jsonb,
  d date
)
  returns tstzrange
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
declare
  w jsonb := s->'hours'->'happy'->(extract(isodow from d)::int::text);
  -- IST midnight of d as an instant: d 00:00 UTC minus 5h30 (fixed offset, no DST).
  midnight timestamptz := (d::timestamp at time zone 'UTC') - interval '330 minutes';
begin
  if coalesce(s->'holidays', '[]'::jsonb) ? d::text
     or coalesce(s->'closed_days', '[]'::jsonb) ? d::text then
    return null;
  end if;
  if w is null or jsonb_typeof(w) <> 'object' then return null; end if;
  return tstzrange(midnight + make_interval(mins => (w->>'start')::int),
                   midnight + make_interval(mins => (w->>'end')::int), '[)');
end;
$function$;

create or replace function public._pr_ist_date (
  t timestamp with time zone
)
  returns date
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select ((t at time zone 'UTC') + interval '330 minutes')::date;
$function$;

create or replace function public._pr_keys (
  q     jsonb,
  p_act text,
  p_res uuid,
  p_cc  integer
)
  returns text[]
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select coalesce(array_agg(_pr_charge_key(p_act, p_res, p_cc, l->>'band',
      (l->>'start')::timestamptz, (l->>'end')::timestamptz, (l->>'played_seconds')::bigint / 60,
      (l->>'billed_minutes')::bigint, (l->>'unit_minutes')::int, (l->>'unit_price')::bigint,
      (l->>'amount')::bigint)), '{}')
    from jsonb_array_elements(q->'lines') l;
$function$;

create or replace function public._pr_money (
  v    bigint,
  step integer,
  dir  text
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select case when step <= 1 then v
              when dir = 'up' then _pr_ceil_step(v, step)
              else _pr_round_step(v, step) end;
$function$;

create or replace function public._pr_policy (
  s jsonb
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select '{"billing_unit":"per_minute","block_rounding":"up","grace_minutes":0,
    "minimum_charge_minutes":0,"early_exit":"actual","rounding_scope":"session",
    "late_arrival":"actual","vr_unit_rounding":"up","money_rounding_paise":100,
    "money_rounding_dir":"nearest","payment_timing":"either","allow_extend_past_close":false,
    "cleaning_gap_minutes":0,"group_billing_mode":"per_system"}'::jsonb
    || coalesce(s->'policy', '{}'::jsonb);
$function$;

create or replace function public._pr_quote (
  s       jsonb,
  p_act   text,
  p_cc    integer,
  p_start timestamp with time zone,
  p_end   timestamp with time zone
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
declare
  pol jsonb := _pr_policy(s);
  v_act jsonb;
  v_total bigint; v_min bigint; v_bend timestamptz;
  v_pts timestamptz[]; v_d date; v_hw tstzrange; v_mid timestamptz; v_band text;
  bs timestamptz[] := '{}'; be timestamptz[] := '{}'; bb text[] := '{}';
  n int := 0; i int;
  v_rate jsonb; v_price bigint; v_um int; v_us bigint; v_sec bigint; v_played bigint;
  v_num bigint; v_den bigint; v_billed bigint; v_units bigint; v_block int;
  v_sum_num bigint := 0; v_common bigint; v_mixed boolean := false; v_seg_sum bigint := 0;
  v_amount bigint; v_sub bigint;
  v_lines jsonb := '[]'::jsonb;
begin
  if p_end < p_start then return null; end if;
  select a into v_act from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a
   where a->>'code' = p_act limit 1;
  if v_act is null then return null; end if;

  v_total := _pr_secs(p_start, p_end);
  -- Grace: free when under the grace period.
  if v_total <= (pol->>'grace_minutes')::int * 60 then
    return jsonb_build_object('subtotal', 0, 'amount', 0, 'lines', '[]'::jsonb);
  end if;
  -- Minimum charge: bill at least this much by extending the billed interval.
  v_min := (pol->>'minimum_charge_minutes')::int * 60;
  v_bend := case when v_total < v_min then p_start + make_interval(secs => v_min) else p_end end;

  -- Band segments: split at every happy-hour boundary, label by midpoint, merge.
  if not coalesce((v_act->>'happy_eligible')::boolean, false) then
    bs := array[p_start]; be := array[v_bend]; bb := array['standard']; n := 1;
  else
    v_pts := array[p_start, v_bend];
    v_d := _pr_ist_date(p_start);
    while v_d <= _pr_ist_date(v_bend) loop
      v_hw := _pr_happy(s, v_d);
      if v_hw is not null then
        if lower(v_hw) > p_start and lower(v_hw) < v_bend then v_pts := v_pts || lower(v_hw); end if;
        if upper(v_hw) > p_start and upper(v_hw) < v_bend then v_pts := v_pts || upper(v_hw); end if;
      end if;
      v_d := v_d + 1;
    end loop;
    select array_agg(distinct x order by x) into v_pts from unnest(v_pts) x;
    for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
      continue when v_pts[i + 1] <= v_pts[i];
      v_mid := v_pts[i] + (v_pts[i + 1] - v_pts[i]) / 2;
      v_hw := _pr_happy(s, _pr_ist_date(v_mid));
      v_band := case when v_hw is not null and v_hw @> v_mid then 'happy' else 'standard' end;
      if n > 0 and bb[n] = v_band then
        be[n] := v_pts[i + 1];
      else
        n := n + 1; bs[n] := v_pts[i]; be[n] := v_pts[i + 1]; bb[n] := v_band;
      end if;
    end loop;
  end if;

  for i in 1 .. n loop
    v_rate := _pr_rate(s, p_act, bb[i], p_cc);
    if v_rate is null and bb[i] = 'happy' then
      v_rate := _pr_rate(s, p_act, 'standard', p_cc);   -- happy → standard fallback
    end if;
    if v_rate is null then return null; end if;
    v_price := (v_rate->>'price_paise')::bigint;
    v_um := (v_rate->>'unit_minutes')::int;
    v_us := v_um::bigint * 60;
    v_sec := _pr_secs(bs[i], be[i]);
    -- Played time counts only the real [p_start, p_end]; the billed piece may run past p_end.
    v_played := case when least(p_end, be[i]) > greatest(p_start, bs[i])
                     then _pr_secs(greatest(p_start, bs[i]), least(p_end, be[i])) else 0 end;
    v_units := 0;
    if v_act->>'duration_model' = 'unit' then
      case pol->>'vr_unit_rounding'
        when 'prorate' then
          v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
        when 'nearest' then
          v_units := _pr_div(v_sec, v_us);
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
        else -- up
          v_units := (v_sec + v_us - 1) / v_us;
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
      end case;
    elsif pol->>'billing_unit' = 'per_minute' then
      v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
    else
      v_block := case pol->>'billing_unit' when 'block_15' then 15 when 'block_30' then 30 else 60 end;
      v_billed := (v_sec + 59) / 60;   -- whole minutes first
      v_billed := case when pol->>'block_rounding' = 'up' then _pr_ceil_step(v_billed, v_block)
                       else _pr_round_step(v_billed, v_block) end;
      v_num := v_price * v_billed; v_den := v_um;
    end if;

    -- Rounding scope: keep the exact numerator over a common denominator so 'session' scope
    -- rounds once (below); 'segment' scope or mixed denominators sum the per-line paise.
    v_common := coalesce(v_common, v_den);
    if v_den <> v_common then v_mixed := true; end if;
    v_sum_num := v_sum_num + v_num;
    v_amount := _pr_div(v_num, v_den);
    v_seg_sum := v_seg_sum + v_amount;
    v_lines := v_lines || jsonb_build_object('start', bs[i], 'end', be[i], 'band', bb[i],
      'played_seconds', v_played, 'billed_minutes', v_billed, 'units', v_units,
      'unit_minutes', v_um, 'unit_price', v_price, 'amount', v_amount);
  end loop;

  v_sub := case when pol->>'rounding_scope' = 'segment' or v_mixed then v_seg_sum
                else _pr_div(v_sum_num, coalesce(v_common, 1)) end;
  return jsonb_build_object('subtotal', v_sub,
    'amount', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'lines', v_lines);
end;
$function$;

create or replace function public._pr_rate (
  s      jsonb,
  p_act  text,
  p_band text,
  p_cc   integer
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select r from jsonb_array_elements(coalesce(s->'rates', '[]'::jsonb)) with ordinality x(r, n)
   where r->>'activity_code' = p_act and r->>'band' = p_band
     and (r->>'controller_count')::int is not distinct from p_cc
   order by n limit 1;
$function$;

create or replace function public._pr_round_step (
  v    bigint,
  step integer
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select case when step <= 1 then v else ((v + step / 2) / step) * step end;
$function$;

create or replace function public._pr_secs (
  s timestamp with time zone,
  e timestamp with time zone
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select trunc(extract(epoch from e) - extract(epoch from s))::bigint;
$function$;

create or replace function public._pr_session_bill (
  p_session  uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; seg record; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}'; pol jsonb;
begin
  select pricing_snapshot into v_snap from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  for seg in select * from session_segments where session_id = p_session order by idx loop
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      coalesce(seg.ended_at, p_open_end));
    continue when q is null;     -- no rate: contributes nothing (device warns)
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_keys := v_keys || _pr_keys(q, seg.activity_code, seg.resource_id, seg.controller_count);
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')));
end;
$function$;

create or replace function public._pr_sweep (
  v_snap           jsonb,
  p_group          uuid,
  p_res            uuid,
  p_open_end       timestamp with time zone,
  p_no_controllers boolean
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  ws timestamptz[]; we timestamptz[]; wc int[]; wa text[];
  v_pts timestamptz[]; i int; j int; s timestamptz; e timestamptz;
  v_cc int; v_act text; v_n int; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}';
begin
  -- Windows in the device's list order (player, then index); empty ones dropped.
  select coalesce(array_agg(started_at order by player_number, idx), '{}'),
         coalesce(array_agg(coalesce(ended_at, p_open_end) order by player_number, idx), '{}'),
         coalesce(array_agg(controller_count order by player_number, idx), '{}'),
         coalesce(array_agg(activity_code order by player_number, idx), '{}')
    into ws, we, wc, wa
    from group_assignments
   where group_id = p_group and resource_id = p_res
     and (not p_no_controllers or controller_count is null)
     and coalesce(ended_at, p_open_end) > started_at;
  select array_agg(distinct x order by x) into v_pts
    from (select unnest(ws) as x union all select unnest(we)) t;
  for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
    s := v_pts[i]; e := v_pts[i + 1];
    continue when e <= s;
    v_n := 0; v_cc := 0; v_act := null;
    for j in 1 .. coalesce(array_length(ws, 1), 0) loop
      if ws[j] <= s and we[j] >= e then
        v_n := v_n + 1;
        v_cc := v_cc + coalesce(wc[j], 0);
        v_act := coalesce(v_act, wa[j]);
      end if;
    end loop;
    continue when v_n = 0;
    q := _pr_quote(v_snap, v_act, nullif(v_cc, 0), s, e);
    continue when q is null;     -- misconfigured rate: excluded, as on the device
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_keys := v_keys || _pr_keys(q, v_act, p_res, nullif(v_cc, 0));
  end loop;
  return jsonb_build_object('subtotal', v_sub, 'keys', to_jsonb(v_keys));
end;
$function$;

create or replace function public._price_mismatch (
  p_what   text,
  p_server bigint,
  p_device bigint
)
  returns void
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
begin
  raise exception 'price_mismatch'
    using hint = format('%s: server %s paise, device %s paise', p_what, p_server,
                        coalesce(p_device::text, 'none'));
end;
$function$;

create or replace function public._pricing_canon (
  s jsonb
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select jsonb_build_object(
    'rates', coalesce((select jsonb_agg(jsonb_build_object('a', r->>'activity_code',
        'b', r->>'band', 'c', (r->>'controller_count')::int, 'u', (r->>'unit_minutes')::int,
        'p', (r->>'price_paise')::bigint)
        order by r->>'activity_code', r->>'band', coalesce((r->>'controller_count')::int, -1),
                 (r->>'unit_minutes')::int, (r->>'price_paise')::bigint)
        from jsonb_array_elements(coalesce(s->'rates', '[]'::jsonb)) r), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', a->>'code',
        'model', a->>'duration_model', 'happy', (a->>'happy_eligible')::boolean)
        order by a->>'code', a->>'duration_model')
        from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a), '[]'::jsonb),
    'policy', _pr_policy(s),
    'hours', (select jsonb_object_agg(kind, (select jsonb_object_agg(d::text,
        case when jsonb_typeof(s->'hours'->kind->(d::text)) = 'object'
             then jsonb_build_object('start', (s->'hours'->kind->(d::text)->>'start')::int,
                                     'end', (s->'hours'->kind->(d::text)->>'end')::int)
             else 'null'::jsonb end) from generate_series(1, 7) d))
        from unnest(array['open', 'happy']) kind),
    'holidays', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'holidays', '[]'::jsonb)) x), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'closed_days', '[]'::jsonb)) x), '[]'::jsonb));
$function$;

create or replace function public._pricing_grace()
  returns interval
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select interval '72 hours';
$function$;

create or replace function public._pricing_snapshot (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
    'rate_card_name', 'Current',
    'rates', coalesce((select jsonb_agg(jsonb_build_object('activity_code', activity_code,
        'band', band, 'controller_count', controller_count, 'unit_minutes', unit_minutes,
        'price_paise', price_paise)) from sync_v_rates where arena_id = p_arena), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', code,
        'duration_model', duration_model, 'happy_eligible', happy_hour_eligible))
        from activities where arena_id = p_arena), '[]'::jsonb),
    'policy', coalesce((select jsonb_build_object('billing_unit', billing_unit,
        'block_rounding', block_rounding, 'grace_minutes', grace_minutes,
        'minimum_charge_minutes', minimum_charge_minutes, 'early_exit', early_exit,
        'rounding_scope', rounding_scope, 'late_arrival', late_arrival,
        'vr_unit_rounding', vr_unit_rounding, 'money_rounding_paise', money_rounding_paise,
        'money_rounding_dir', money_rounding_dir, 'payment_timing', payment_timing,
        'allow_extend_past_close', allow_extend_past_close,
        'cleaning_gap_minutes', cleaning_gap_minutes, 'group_billing_mode', group_billing_mode)
        from billing_policies where arena_id = p_arena and active order by created_at limit 1),
        _pr_policy('{}'::jsonb)),
    -- BusinessHours.current() when the owner never saved hours.
    'hours', coalesce((select json from settings where arena_id = p_arena and key = 'business_hours'),
      '{"open":{"1":null,"2":{"start":840,"end":1380},"3":{"start":840,"end":1380},
                "4":{"start":840,"end":1380},"5":{"start":840,"end":1380},
                "6":{"start":840,"end":1380},"7":{"start":840,"end":1380}},
        "happy":{"1":null,"2":{"start":840,"end":1020},"3":{"start":840,"end":1020},
                 "4":{"start":840,"end":1020},"5":{"start":840,"end":1020},"6":null,"7":null}}'::jsonb),
    'holidays', coalesce((select jsonb_agg(day::text) from holidays where arena_id = p_arena), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(day::text) from holidays
        where arena_id = p_arena and closed), '[]'::jsonb));
$function$;

create or replace function public._rupees (
  p bigint
)
  returns text
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select '₹' || to_char(p / 100.0, 'FM999999990.00');
$function$;

create or replace function public._sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone,
  p_id    uuid                     default null::uuid
)
  returns SETOF jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
      'kind', 'single', 'id', s.id, 'at', b.at,
      'started_at', s.started_at, 'ended_at', s.actual_ended_at, 'recorded_at', s.created_at,
      'status', s.status, 'payment_status', s.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = s.customer_id and o.arena_id = s.arena_id
                   and o.id <> s.id and o.status = 'completed' and o.started_at < s.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = s.customer_id and o.arena_id = s.arena_id
                      and o.status = 'completed' and o.started_at < s.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', seg.players, 'player_minutes', seg.player_minutes,
      'billed_paise', s.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', s.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by)
    from sessions s
    cross join lateral (select coalesce(s.actual_ended_at, s.updated_at) as at) b
    join customers c on c.id = s.customer_id
    left join staff_profiles sp on sp.arena_id = s.arena_id and sp.user_id = s.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.idx) as first
                                 from session_segments g join resources r on r.id = g.resource_id
                                where g.session_id = s.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.idx) as first
                                 from session_segments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.session_id = s.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.idx) as first
                                 from session_segments g join games gm on gm.id = g.game_id
                                where g.session_id = s.id group by gm.name) x), '[]'::jsonb) as games,
             coalesce((select max(g.controller_count) from session_segments g
                        where g.session_id = s.id), 1) as players,
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0 * coalesce(g.controller_count, 1)))::int
                         from session_segments g where g.session_id = s.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from payments
                                where session_id = s.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.kind = 'refund', 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.session_id = s.id), '[]'::jsonb) as ledger
        from payments p where p.session_id = s.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
   where s.arena_id = p_arena and s.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else s.id = p_id end)
  union all
  select jsonb_build_object(
      'kind', 'group', 'id', gs.id, 'at', b.at,
      'started_at', gs.started_at, 'ended_at', gs.actual_ended_at, 'recorded_at', gs.created_at,
      'status', gs.status, 'payment_status', gs.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                   and o.status = 'completed' and o.started_at < gs.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                      and o.id <> gs.id and o.status = 'completed' and o.started_at < gs.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', gs.player_count, 'player_minutes', seg.player_minutes,
      'billed_paise', gs.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', gs.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by)
    from group_sessions gs
    cross join lateral (select coalesce(gs.actual_ended_at, gs.updated_at) as at) b
    join customers c on c.id = gs.primary_customer_id
    left join staff_profiles sp on sp.arena_id = gs.arena_id and sp.user_id = gs.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join resources r on r.id = g.resource_id
                                where g.group_id = gs.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.group_id = gs.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join games gm on gm.id = g.game_id
                                where g.group_id = gs.id group by gm.name) x), '[]'::jsonb) as games,
             -- Each assignment is one player's stretch on one station.
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0))::int
                         from group_assignments g where g.group_id = gs.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from group_payments
                                where group_id = gs.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.is_refund, 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from group_payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.group_id = gs.id), '[]'::jsonb) as ledger
        from group_payments p where p.group_id = gs.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
   where gs.arena_id = p_arena and gs.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else gs.id = p_id end);
$function$;

create or replace function public._same_ids (
  a uuid[],
  b uuid[]
)
  returns boolean
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select coalesce((select array_agg(distinct x order by x) from unnest(a) x), '{}')
       = coalesce((select array_agg(distinct x order by x) from unnest(b) x), '{}');
$function$;

create or replace function public._seed_arena_catalog (
  v_arena uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._single_supply (
  p_arena         uuid,
  p_resource      uuid,
  p_activity      text,
  p_game          uuid,
  p_pad_count     integer,
  p_count         integer,
  p_prev_resource uuid    default null::uuid,
  p_prev_count    integer default null::integer
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._stale (
  p_current xid8,
  p_base    text
)
  returns boolean
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select p_base is not null and p_base <> '' and p_current::text <> p_base;
$function$;

create or replace function public._station_free_for_single (
  p_resource uuid
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if exists (select 1 from session_segments where resource_id = p_resource and ended_at is null)
     or exists (select 1 from group_assignments where resource_id = p_resource and ended_at is null) then
    raise exception 'resource_busy';
  end if;
end;
$function$;

create or replace function public._station_usable (
  p_arena    uuid,
  p_resource uuid
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  select status into v_status from resources where id = p_resource and arena_id = p_arena;
  if not found then raise exception 'resource_missing'; end if;
  if v_status <> 'available' then
    raise exception 'resource_unavailable' using hint = v_status;
  end if;
end;
$function$;

create or replace function public._sync_apply (
  p_arena uuid,
  p_kind  text,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_before jsonb; v_res jsonb;
begin
  -- A price-list change retires the previous catalog into
  -- pricing_catalog_history, so a session priced on it still validates.
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;

  -- Dispatch: one op kind -> one op_* function. Unknown kinds return null and
  -- sync_push rejects them.
  v_res := case p_kind
      when 'session.start'        then op_session_start(p_arena, p)
      when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
      when 'session.extend'       then op_session_extend(p_arena, p)
      when 'session.end'          then op_session_end(p_arena, p)
      when 'session.void'         then op_session_void(p_arena, p)
      when 'payment.record'       then op_payment(p_arena, p)
      when 'payment.correct'      then op_payment_correct(p_arena, p)
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
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      else null
    end;

  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$function$;

create or replace function public._sync_sources()
  returns table (
    name text,
    rel  text
  )
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  values
    ('arenas','sync_v_arenas'), ('staff_profiles','staff_profiles'),
    ('activities','activities'), ('resources','resources'),
    ('resource_activities','sync_v_resource_activities'), ('controllers','controllers'),
    ('customers','customers'), ('rates','sync_v_rates'),
    ('billing_policies','billing_policies'), ('holidays','holidays'),
    ('game_categories','game_categories'), ('games','games'),
    ('game_controls','game_controls'), ('game_resources','game_resources'),
    ('bookings','sync_v_bookings'), ('sessions','sessions'),
    ('session_segments','session_segments'), ('session_extensions','session_extensions'),
    ('session_charges','session_charges'), ('payments','payments'),
    ('group_sessions','group_sessions'), ('group_assignments','group_assignments'),
    ('group_extensions','group_extensions'), ('group_charges','group_charges'),
    ('group_payments','group_payments'), ('controller_allocations','controller_allocations'),
    ('controller_moves','controller_moves'), ('settings','settings')
$function$;

create or replace function public._untracked_busy (
  p_arena    uuid,
  p_resource uuid,
  p_except   uuid[] default '{}'::uuid[]
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public._usable_pads_at (
  p_arena    uuid,
  p_resource uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::int from controllers
   where arena_id = p_arena and current_resource_id = p_resource and status = 'usable';
$function$;

create or replace function public._uses_controllers (
  p_arena    uuid,
  p_activity text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select coalesce((select uses_controllers from activities
                    where arena_id = p_arena and code = p_activity), false);
$function$;

create or replace function public.accept_invite (
  p_invite uuid,
  p_token  text
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.accept_invite(p_invite, p_token);
$function$;

create or replace function public.app_is_owner (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.app_is_owner(p_arena);
$function$;

create or replace function public.arena_invites (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_invites(p_arena);
$function$;

create or replace function public.arena_pricing (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_pricing(p_arena);
$function$;

create or replace function public.arena_sale (
  p_arena uuid,
  p_id    uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_sale(p_arena, p_id);
$function$;

create or replace function public.arena_sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_sales(p_arena, p_from, p_to);
$function$;

create or replace function public.arena_staff (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_staff(p_arena);
$function$;

create or replace function public.assert_controller_free_for_allocation()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
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
$function$;

create or replace function public.assert_resource_free_for_assignment()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
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
    -- Open assignments of the same group may share the station.
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
$function$;

create or replace function public.assert_resource_free_for_segment()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
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
$function$;

create or replace function public.bootstrap_owner (
  p_email      text,
  p_arena_name text,
  p_owner_name text default null::text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_user uuid; v_confirmed timestamptz;
begin
  select id, email_confirmed_at into v_user, v_confirmed
    from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create the login first: Authentication → Users → Add user';
  end if;
  if v_confirmed is null then
    raise exception 'account_not_confirmed'
      using hint = 'tick "Auto Confirm User" when adding the user, or confirm it';
  end if;
  return _create_arena_with_owner(v_user, p_arena_name, p_owner_name);
end;
$function$;

create or replace function public.create_my_arena (
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language sql
  set search_path to ''
  AS $function$
  select private.create_my_arena(p_arena_name, p_owner_name);
$function$;

create or replace function public.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.invite_member(p_arena, p_email, p_name, p_role, p_perms);
$function$;

create or replace function public.my_arenas()
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.my_arenas();
$function$;

create or replace function public.op_activity_remove (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id       uuid := (p->>'id')::uuid;
  v_code     text;
  v_stations int;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from activities where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'activity';
  end if;
  select code into v_code from activities where id = v_id and arena_id = p_arena for update;
  if not found then return jsonb_build_object('removed', 'deleted'); end if;

  select count(*) into v_stations
    from resource_activities ra join resources r on r.id = ra.resource_id
   where ra.activity_id = v_id and r.status <> 'disabled';
  if v_stations > 0 then
    raise exception 'activity_has_stations' using hint = v_stations::text;
  end if;

  update resources set current_mode = null, updated_at = statement_timestamp()
   where arena_id = p_arena and current_mode = v_code;

  if exists (select 1 from session_segments where arena_id = p_arena and activity_code = v_code)
     or exists (select 1 from group_assignments where arena_id = p_arena and activity_code = v_code)
     or exists (select 1 from session_charges where arena_id = p_arena and activity_code = v_code)
     or exists (select 1 from group_charges where arena_id = p_arena and activity_code = v_code)
     or exists (select 1 from controller_allocations where arena_id = p_arena and activity_code = v_code)
     or exists (select 1 from bookings where arena_id = p_arena and activity_id = v_id) then
    update activities set active = false, updated_at = statement_timestamp() where id = v_id;
    return jsonb_build_object('removed', 'retired');
  end if;

  delete from activities where id = v_id;
  return jsonb_build_object('removed', 'deleted');
end;
$function$;

create or replace function public.op_activity_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_code text := upper(btrim(coalesce(p->>'code', '')));
  v_name text := btrim(coalesce(p->>'name', ''));
  v_pads boolean := coalesce((p->>'uses_controllers')::boolean, false);
  v_old  activities%rowtype;
begin
  perform _need(p_arena, 'settings');
  if v_code !~ '^[A-Z0-9_]{1,12}$' then
    raise exception 'invalid_code' using hint = 'A–Z, 0–9 or _, up to 12';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if exists (select 1 from activities where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'activity';
  end if;

  select * into v_old from activities where id = v_id and arena_id = p_arena for update;
  if found then
    if v_old.code <> v_code then
      raise exception 'code_locked' using hint = v_old.code;
    end if;
    if v_old.uses_controllers <> v_pads and (
         exists (select 1 from session_segments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)
      or exists (select 1 from group_assignments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)) then
      raise exception 'activity_busy' using hint = v_code;
    end if;
  end if;

  insert into activities(id, arena_id, code, name, uses_controllers, uses_games, duration_model,
      happy_hour_eligible, sort_order, active)
    values (v_id, p_arena, v_code, v_name, v_pads,
      coalesce((p->>'uses_games')::boolean, false),
      coalesce(p->>'duration_model', 'hourly'),
      coalesce((p->>'happy_hour_eligible')::boolean, true),
      coalesce((p->>'sort_order')::int, 0),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    name = excluded.name, uses_controllers = excluded.uses_controllers,
    uses_games = excluded.uses_games, duration_model = excluded.duration_model,
    happy_hour_eligible = excluded.happy_hour_eligible, sort_order = excluded.sort_order,
    active = excluded.active, updated_at = statement_timestamp()
  where activities.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_arena_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_name  text := btrim(p->>'name');
  v_area  text := nullif(btrim(p->>'area'), '');
  v_phone text := nullif(btrim(p->>'phone'), '');
begin
  perform _need(p_arena, 'settings');
  if p ? 'name' and (v_name is null or char_length(v_name) not between 1 and 80) then
    raise exception 'invalid_name' using hint = '1–80 characters';
  end if;
  if p ? 'area' and char_length(v_area) > 80 then
    raise exception 'invalid_area' using hint = 'up to 80 characters';
  end if;
  if p ? 'phone' and v_phone !~ '^[0-9+() -]{6,20}$' then
    raise exception 'invalid_phone' using hint = '6–20 digits, spaces, +, ( ) or -';
  end if;
  update arenas set
      name  = case when p ? 'name' then v_name else name end,
      area  = case when p ? 'area' then v_area else area end,
      phone = case when p ? 'phone' then v_phone else phone end,
      updated_at = statement_timestamp()
    where id = p_arena;
  if not found then raise exception 'not_found' using hint = 'arena'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_booking_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public.op_booking_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  perform _need(p_arena, 'start');
  if (p->>'status') not in ('cancelled', 'no_show') then
    raise exception 'invalid_status' using hint = coalesce(p->>'status', 'null');
  end if;
  select status into v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  -- Already in that state (a replay, or the other device did it): succeed without writing.
  if v_status = p->>'status' then return '{}'::jsonb; end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  update bookings set status = p->>'status', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_booking_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8; v_status text; v_res uuid := nullif(p->>'resource_id','')::uuid;
begin
  perform _need(p_arena, 'start');
  select sync_xid, status into v_xid, v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  -- base_version is the row's sync_xid as the device last pulled it; absent/empty skips the check.
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
$function$;

create or replace function public.op_controller_move (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_cid uuid := (p->>'controller_id')::uuid;
  v_kind text := p->>'kind';
  v_to uuid := nullif(p->>'to_resource_id','')::uuid;
  v_loc uuid; v_home uuid; v_loc2 uuid; v_home2 uuid;
begin
  if v_kind is null or v_kind not in ('loan','permanent','returnHome') then
    raise exception 'move_kind_invalid';
  end if;
  -- Carrying a pad (loan / return) is floor work: it needs start or settings
  -- (0016). Re-homing it (permanent) changes the inventory: settings.
  if v_kind in ('loan', 'returnHome')
     and not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'settings')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or settings';
  end if;
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
  -- Stations are locked before pads (the order every op uses), so the pad was
  -- read unlocked above. If it moved or was re-homed in between, the stations
  -- we hold are the wrong ones: retry rather than move it unlocked.
  select current_resource_id, home_resource_id into v_loc2, v_home2 from controllers where id = v_cid;
  if v_loc2 is distinct from v_loc or v_home2 is distinct from v_home then
    raise exception 'retry' using errcode = '40001';
  end if;
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
  -- adjusted: no move_id was sent, so the server minted the history row id; the device refetches.
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$function$;

create or replace function public.op_controller_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  update controllers set status = p->>'status', notes = p->>'notes', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'controller'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_controller_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_loc uuid;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from controllers where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'controller';
  end if;
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
$function$;

create or replace function public.op_customer_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_phone text := nullif(btrim(p->>'phone'), '');
  v_other uuid;
begin
  if not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  -- A phone already in use (two devices registering the same person offline) must not sink
  -- the sessions that reference this customer: keep the row phone-less and audit the clash.
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from v_now at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  if v_phone is not null then
    select id into v_other from customers where arena_id = p_arena and phone = v_phone;
  end if;
  insert into customers(id, arena_id, name, phone, notes, last_visit_at, is_guest, created_at, updated_at,
      birth_year)
    values ((p->>'id')::uuid, p_arena, p->>'name', case when v_other is null then v_phone end,
      p->>'notes', (p->>'last_visit_at')::timestamptz, coalesce((p->>'is_guest')::boolean, false),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now, (p->>'birth_year')::smallint);
  if v_other is not null then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
      values (p_arena, 'customer', (p->>'id')::uuid, 'duplicate_phone_on_sync',
        'phone already belongs to another customer', jsonb_build_object('phone', v_phone,
        'existing_customer_id', v_other), auth.uid(), v_now);
    return jsonb_build_object('adjusted', true, 'phone_taken_by', v_other);
  end if;
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_customer_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8;
begin
  if not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from statement_timestamp() at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  select sync_xid into v_xid from customers where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'customer'; end if;
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the customer was edited on another device';
  end if;
  begin
    update customers set name = p->>'name', phone = nullif(btrim(p->>'phone'), ''),
        notes = p->>'notes',
        -- Builds that do not send birth_year keep the stored one.
        birth_year = case when p ? 'birth_year' then (p->>'birth_year')::smallint else birth_year end,
        updated_at = statement_timestamp()
      where id = (p->>'id')::uuid;
  exception when unique_violation then
    raise exception 'phone_taken';
  end;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_game_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id      uuid := (p->>'id')::uuid;
  v_playing int;
  v_history text;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if exists (select 1 from games where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  -- The lock queues behind a start that is placing a session on it right now (its foreign-key
  -- check holds a key-share lock), so the checks below see that session once it commits.
  perform 1 from games where id = v_id and arena_id = p_arena for update;
  if not found then return jsonb_build_object('deleted', true); end if;

  select (select count(*) from session_segments
           where arena_id = p_arena and game_id = v_id and ended_at is null)
       + (select count(*) from group_assignments
           where arena_id = p_arena and game_id = v_id and ended_at is null)
    into v_playing;
  if v_playing > 0 then
    raise exception 'game_in_play' using hint = v_playing::text;
  end if;

  v_history := case
    when exists (select 1 from session_segments where arena_id = p_arena and game_id = v_id)
      then 'sessions'
    when exists (select 1 from group_assignments where arena_id = p_arena and game_id = v_id)
      then 'groups'
    when exists (select 1 from controller_allocations where arena_id = p_arena and game_id = v_id)
      then 'pads'
    when exists (select 1 from bookings where arena_id = p_arena and game_id = v_id)
      then 'bookings'
  end;
  if v_history is not null then
    raise exception 'game_has_history' using hint = v_history;
  end if;

  delete from games where id = v_id and arena_id = p_arena;
  return jsonb_build_object('deleted', true);
end;
$function$;

create or replace function public.op_game_replace_controls (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public.op_game_set_active (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_target boolean := (p->>'active')::boolean;
  v_active boolean;
begin
  perform _need(p_arena, 'settings');
  if v_target is null then raise exception 'invalid_payload' using hint = 'active'; end if;
  select active into v_active from games
   where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'game'; end if;
  if v_active is distinct from v_target then
    update games set active = v_target, updated_at = statement_timestamp()
      where id = (p->>'id')::uuid and arena_id = p_arena;
  end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_game_set_compat (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  insert into game_resources(arena_id, game_id, resource_id, status, notes)
    values (p_arena, (p->>'game_id')::uuid, (p->>'resource_id')::uuid, p->>'status', p->>'notes')
  on conflict (game_id, resource_id) do update
    set status = excluded.status,
        notes = case when p ? 'notes' then excluded.notes else game_resources.notes end,
        updated_at = statement_timestamp()
    where game_resources.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_game_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id     uuid := (p->>'id')::uuid;
  v_name   text := btrim(p->>'name');
  v_active boolean;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from games where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  if v_name is null or v_name = '' or char_length(v_name) > 80 then
    raise exception 'invalid_name' using hint = '1 to 80 characters';
  end if;

  select active into v_active from games where id = v_id and arena_id = p_arena for update;
  if found then
    if p ? 'base_active' and (p->>'base_active')::boolean is distinct from v_active
       and p ? 'active' and (p->>'active')::boolean is distinct from v_active then
      raise exception 'stale' using hint = 'the game was archived or restored on another device';
    end if;
  elsif exists (select 1 from sync_tombstones
                 where arena_id = p_arena and table_name = 'games' and row_key->>'id' = v_id::text) then
    raise exception 'not_found' using hint = 'game deleted';
  end if;

  -- Names are unique ignoring case; the lock makes two concurrent saves of "FIFA" and "fifa" queue.
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text || ':game:' || lower(v_name), 0));
  if exists (select 1 from games
              where arena_id = p_arena and id <> v_id and lower(name) = lower(v_name)) then
    raise exception 'duplicate' using hint = 'name';
  end if;

  insert into games(id, arena_id, name, aliases, category_id, platforms, player_mode,
      max_local_players, active, age_rating, media)
    values (v_id, p_arena, v_name,
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true),
      (p->>'age_rating')::smallint, p->>'media')
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = case when p ? 'active' then excluded.active else games.active end,
      age_rating = case when p ? 'age_rating' then excluded.age_rating else games.age_rating end,
      media = case when p ? 'media' then excluded.media else games.media end,
      updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_group_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
  -- Next index in this player's assignment history (a re-added player continues it).
  select coalesce(max(idx), -1) + 1 into v_idx from group_assignments
    where group_id = v_group and player_number = v_player;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx, null);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_group_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
  -- Every target station and borrowed-pad origin, then the pads, in uuid order.
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

  -- The frozen price list must be this arena's current one, and the group's
  -- billing mode must be the one that price list prescribes (0013).
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  if coalesce(nullif(p->>'billing_mode', ''), 'per_system')
     <> _pr_policy(p->'pricing_snapshot')->>'group_billing_mode' then
    raise exception 'pricing_snapshot_mismatch'
      using hint = 'billing_mode differs from the price list''s group billing mode';
  end if;
  return jsonb_build_object('group_id', v_group, 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_group_end (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_end timestamptz; v_ids uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
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
  -- Payments may already have been taken against the running bill.
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_group;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason; optional here so floor builds that do not send it still end the group).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'group_session', v_group, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored assignments
  -- and refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  v_bill := _pr_group_bill(v_group, v_ended);
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from group_charges where group_id = v_group) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_group_end_player (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public.op_group_extend (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_end timestamptz; v_added bigint;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  if v_end is distinct from v_old then
    raise exception 'stale' using hint = 'the group was extended on another device';
  end if;
  insert into group_extensions(id, arena_id, group_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_group, (p->>'added_minutes')::int, v_end,
      v_new, coalesce((p->>'added_amount_paise')::bigint, 0), p->>'reason', auth.uid(), v_now);
  update group_sessions set scheduled_end_at = v_new, updated_at = v_now where id = v_group;

  -- Server-side pricing (0013): the extension costs the difference between the
  -- group's subtotal at the new end and at the old end.
  v_added := (_pr_group_bill(v_group, v_new)->>'subtotal')::bigint
           - (_pr_group_bill(v_group, v_old)->>'subtotal')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_group_switch (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
  -- Also lock the station the player is leaving.
  perform _group_lock(p_arena, jsonb_build_array(a), array[v_open_res]);
  -- The player keeps their label across a switch (as on the device).
  a := a || jsonb_build_object('player_number', v_player, 'player_label', v_label);
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx + 1, v_player);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_group_void (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  -- A void changes the takings: it is never recorded without a reason.
  if v_reason is null then
    raise exception 'void_reason_required' using hint = 'say why the bill is voided';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  select status into v_status from group_sessions where id = v_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  -- greatest(): never end a row before it started, whatever the device clock said.
  update group_assignments set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = v_reason, updated_at = v_now
    where id = v_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'group_session', v_group, 'void', v_reason, auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_holiday_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  delete from holidays where arena_id = p_arena and day = (p->>'day')::date;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_holiday_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  insert into holidays(arena_id, day, name, closed)
    values (p_arena, (p->>'day')::date, p->>'name', coalesce((p->>'closed')::boolean, false))
  on conflict (arena_id, day) do update set name = excluded.name, closed = excluded.closed,
      updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_payment (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now    timestamptz := statement_timestamp();
  v_scope  text    := coalesce(p->>'scope', 'single');
  v_parent uuid    := (p->>'parent_id')::uuid;
  v_refund boolean := coalesce((p->>'is_refund')::boolean, false);
  v_amount bigint  := (p->>'amount_paise')::bigint;
  v_status text; v_pay text; v_billed bigint; v_paid bigint;
begin
  -- Permission refusals keep their own code, ahead of any balance check.
  perform _need(p_arena, 'bill');
  if v_refund then perform _need(p_arena, 'discount'); end if;

  -- Balance (0016). Lock the parent so two pushes for the same bill queue here
  -- and the second sees the first one's payment.
  if v_scope = 'group' then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from group_payments where group_id = v_parent;
    end if;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from payments where session_id = v_parent;
    end if;
  end if;

  -- A payment on a voided bill is refused as such, ahead of the balance check (which
  -- would otherwise call it an overpayment on a bill that was paid before the void).
  if v_status = 'voided' and not v_refund then
    raise exception 'voided' using hint = 'a voided bill takes no payments; a refund is allowed';
  end if;

  -- v_paid is null when the parent was not found; not_found is raised further down.
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

  -- Amount, sign, refund reason and method.
  if v_amount is null or v_amount = 0 then raise exception 'amount_zero'; end if;
  if v_refund then
    if coalesce(btrim(p->>'reason'), '') = '' then raise exception 'refund_reason_required'; end if;
    v_amount := -abs(v_amount);
  elsif v_amount < 0 then
    raise exception 'amount_negative';
  end if;
  if (p->>'method') not in ('cash','upi','card','other') then raise exception 'invalid_method'; end if;

  -- Record the payment and recompute the parent's payment status (a waived bill
  -- keeps 'waived').
  if v_scope = 'group' then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    if v_status = 'voided' and not v_refund then
      raise exception 'voided' using hint = 'a voided bill takes no payments; a refund is allowed';
    end if;
    insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
        reason, created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method', v_refund,
        p->>'note', p->>'reason', auth.uid(), v_now);
    if v_pay <> 'waived' and v_status <> 'voided' then
      select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update group_sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    if v_status = 'voided' and not v_refund then
      raise exception 'voided' using hint = 'a voided bill takes no payments; a refund is allowed';
    end if;
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method',
        case when v_refund then 'refund' else 'payment' end, p->>'note', p->>'reason',
        auth.uid(), v_now);
    if v_pay <> 'waived' and v_status <> 'voided' then
      select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_payment_correct (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now       timestamptz := statement_timestamp();
  v_group     boolean := coalesce(p->>'scope', 'single') = 'group';
  v_parent    uuid := (p->>'parent_id')::uuid;
  v_payment   uuid := (p->>'payment_id')::uuid;
  v_method    text := p->>'method';
  v_reason    text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_refund_id uuid := coalesce(nullif(p->>'refund_id', '')::uuid, gen_random_uuid());
  v_new_id    uuid := coalesce(nullif(p->>'new_payment_id', '')::uuid, gen_random_uuid());
  v_entity    text := case when coalesce(p->>'scope', 'single') = 'group' then 'group_session'
                           else 'session' end;
  v_old_method text; v_old_amount bigint; v_was_refund boolean;
  v_moved bigint; v_left bigint; v_amount bigint;
begin
  perform _need(p_arena, 'money');
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say what was recorded wrongly';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
    raise exception 'invalid_method';
  end if;

  -- Lock the bill (as op_payment does), so payments and corrections on it queue here.
  if v_group then
    perform 1 from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    select method, amount_paise, is_refund into v_old_method, v_old_amount, v_was_refund
      from group_payments where id = v_payment and group_id = v_parent and arena_id = p_arena;
  else
    perform 1 from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    select method, amount_paise, kind = 'refund' into v_old_method, v_old_amount, v_was_refund
      from payments where id = v_payment and session_id = v_parent and arena_id = p_arena;
  end if;
  if not found then raise exception 'not_found' using hint = 'payment'; end if;
  if v_was_refund then
    raise exception 'not_a_payment' using hint = 'only a payment can be moved to another method';
  end if;
  if v_method = v_old_method then
    raise exception 'same_method' using hint = 'that payment is already recorded as ' || v_old_method;
  end if;

  -- What earlier corrections already moved out of this payment.
  select coalesce(sum((after->>'amount_paise')::bigint), 0) into v_moved
    from audit_log
   where arena_id = p_arena and entity_type = v_entity and entity_id = v_parent
     and action = 'payment_correct' and before->>'payment_id' = v_payment::text;
  v_left := v_old_amount - v_moved;
  if v_left <= 0 then
    raise exception 'already_corrected' using hint = 'all of this payment was already moved';
  end if;
  v_amount := coalesce((p->>'amount_paise')::bigint, v_left);
  if v_amount <= 0 or v_amount > v_left then
    raise exception 'amount_invalid' using hint = 'at most ' || _rupees(v_left) || ' can be moved';
  end if;

  if v_group then
    insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
        reason, created_by, created_at)
      values
        (v_refund_id, p_arena, v_parent, -v_amount, v_old_method, true, 'Method correction',
          v_reason, auth.uid(), v_now),
        (v_new_id, p_arena, v_parent, v_amount, v_method, false, 'Method correction',
          v_reason, auth.uid(), v_now);
  else
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values
        (v_refund_id, p_arena, v_parent, -v_amount, v_old_method, 'refund', 'Method correction',
          v_reason, auth.uid(), v_now),
        (v_new_id, p_arena, v_parent, v_amount, v_method, 'payment', 'Method correction',
          v_reason, auth.uid(), v_now);
  end if;

  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, v_entity, v_parent, 'payment_correct', v_reason,
      jsonb_build_object('payment_id', v_payment, 'method', v_old_method,
        'amount_paise', v_old_amount),
      jsonb_build_object('method', v_method, 'amount_paise', v_amount,
        'refund_id', v_refund_id, 'payment_id', v_new_id),
      auth.uid(), v_now);
  return jsonb_build_object('moved_paise', v_amount, 'refund_id', v_refund_id,
    'payment_id', v_new_id);
end;
$function$;

create or replace function public.op_policy_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public.op_rate_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  delete from rates r using rate_bands b, activities a
   where r.arena_id = p_arena and r.rate_card_id = _active_card(p_arena)
     and b.id = r.band_id and b.code = p->>'band'
     and a.id = r.activity_id and a.code = p->>'activity_code'
     -- -1 stands for null so the any-count rate (controller_count null) matches itself.
     and coalesce(r.controller_count, -1) = coalesce(nullif(p->>'controller_count','')::int, -1);
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_rate_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_card uuid := _active_card(p_arena);
  v_act uuid := _activity_id(p_arena, p->>'activity_code');
  v_band uuid := _band_id(p_arena, p->>'band');
  v_cc int := nullif(p->>'controller_count','')::int;
  v_id uuid;
begin
  -- The declare initialisers (_active_card, _activity_id, _band_id) already ran; anything
  -- they inserted rolls back with the op if this refuses.
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
$function$;

create or replace function public.op_resource_set_mode (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public.op_resource_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id     uuid := (p->>'id')::uuid;
  v_status text := p->>'status';
begin
  perform _need(p_arena, 'settings');
  perform _lock_resources(p_arena, array[v_id]);
  if not exists (select 1 from resources where id = v_id and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  if v_status is distinct from 'available' then
    if exists (select 1 from session_segments
                where arena_id = p_arena and resource_id = v_id and ended_at is null) then
      raise exception 'resource_busy' using hint = 'open session';
    end if;
    if exists (select 1 from group_assignments
                where arena_id = p_arena and resource_id = v_id and ended_at is null) then
      raise exception 'resource_busy' using hint = 'group player';
    end if;
  end if;
  update resources set status = v_status, updated_at = statement_timestamp()
    where id = v_id and arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_resource_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_code text; v_old text;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never overwritten.
  if exists (select 1 from resources where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  perform _lock_resources(p_arena, array[v_id]);
  select status into v_old from resources where id = v_id and arena_id = p_arena;
  if found and p ? 'status' and (p->>'status') is distinct from v_old
     and (p->>'status') is distinct from 'available'
     and (exists (select 1 from session_segments
                   where arena_id = p_arena and resource_id = v_id and ended_at is null)
          or exists (select 1 from group_assignments
                      where arena_id = p_arena and resource_id = v_id and ended_at is null)) then
    raise exception 'resource_busy' using hint = 'in use';
  end if;
  insert into resources(id, arena_id, name, kind, status, sort_order)
    values (v_id, p_arena, p->>'name', p->>'kind', coalesce(p->>'status', 'available'),
      coalesce((p->>'sort_order')::int, 0))
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      status = case when p ? 'status' then excluded.status else resources.status end,
      sort_order = excluded.sort_order, updated_at = statement_timestamp()
    where resources.arena_id = p_arena;
  -- The station supports exactly the listed activities.
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
$function$;

create or replace function public.op_session_end (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_status text; v_end timestamptz; v_segs uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select coalesce(array_agg(id), '{}') into v_segs from session_segments where session_id = v_session;
  if not _same_ids(v_segs, _jsonb_uuids(p->'expected_segment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
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
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason; optional here so floor builds that do not send it still end the session).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'session', v_session, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored segments and
  -- refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended);
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from session_charges where session_id = v_session) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_session_extend (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_status text; v_end timestamptz;
  v_snap jsonb; v_start timestamptz; v_act text; v_cc int; q_old jsonb; q_new jsonb; v_added bigint;
begin
  perform _need(p_arena, 'start');
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  if v_end is distinct from v_old then
    raise exception 'stale' using hint = 'the session was extended on another device';
  end if;
  insert into session_extensions(id, arena_id, session_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_session, (p->>'added_minutes')::int, v_end,
      v_new, coalesce((p->>'added_amount_paise')::bigint, 0), p->>'reason', auth.uid(), v_now);
  update sessions set scheduled_end_at = v_new, updated_at = v_now where id = v_session;

  -- Server-side pricing (0013): the extension costs the difference between the
  -- bill at the new end and at the old end, on the session's frozen price list.
  select pricing_snapshot, started_at into v_snap, v_start from sessions where id = v_session;
  select activity_code, controller_count into v_act, v_cc from session_segments
   where session_id = v_session order by (ended_at is null) desc, idx desc limit 1;
  q_old := _pr_quote(v_snap, v_act, v_cc, v_start, v_old);
  q_new := _pr_quote(v_snap, v_act, v_cc, v_start, v_new);
  if q_old is null or q_new is null then
    raise exception 'no_rate' using hint = 'the session''s price list has no rate for this extension';
  end if;
  v_added := (q_new->>'amount')::bigint - (q_old->>'amount')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return jsonb_build_object('new_end_at', p->>'new_end_at');
end;
$function$;

create or replace function public.op_session_reconfigure (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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
$function$;

create or replace function public.op_session_start (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
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

  -- The price list the device froze into the session must be this arena's
  -- current one (0013); checked last so earlier errors keep their precedence.
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  return jsonb_build_object('session_id', v_session, 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_session_void (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  -- A void changes the takings: it is never recorded without a reason.
  if v_reason is null then
    raise exception 'void_reason_required' using hint = 'say why the bill is voided';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update session_segments set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update sessions set status = 'voided', void_reason = v_reason, updated_at = v_now
    where id = v_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'session', v_session, 'void', v_reason, auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_settings_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_json jsonb := p->'json';
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours', 'floor_options') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_staff_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  -- money / reports make a member "owner level" (app_is_owner, and the app's
  -- AppUser.isOwner). Only an owner-level member may hand them out or take them away.
  c_owner_perms constant text[] := array['money', 'reports'];
  v_user   uuid    := (p->>'user_id')::uuid;
  -- A field the op leaves out keeps its current value: a partial update must
  -- never wipe someone's permissions or silently reactivate them.
  v_perms  text[]  := case when p ? 'perms'
                        then array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb))) end;
  v_active boolean := (p->>'active')::boolean;
  v_role   text;
  v_old_perms  text[];
  v_old_active boolean;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  select role, perms, active into v_role, v_old_perms, v_old_active from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  v_perms := coalesce(v_perms, v_old_perms);
  v_active := coalesce(v_active, v_old_active);
  perform _assert_known_perms(v_perms);

  if v_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
    end if;
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    v_adj := not (v_perms @> _known_perms()) or not v_active;
    v_perms := _known_perms();
    v_active := true;
  else
    -- Nobody changes their own access: a Settings holder could otherwise grant
    -- themselves money/reports and become owner level.
    if v_user = auth.uid()
       and (not (v_perms @> v_old_perms and v_old_perms @> v_perms) or v_active <> v_old_active) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'you cannot change your own permissions';
    end if;
    -- Owner-level perms, and owner-level members, are managed by owners only.
    if not private.app_is_owner(p_arena)
       and (v_old_perms && c_owner_perms
            or ('money' = any(v_perms)) <> ('money' = any(v_old_perms))
            or ('reports' = any(v_perms)) <> ('reports' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports, or change an owner-level member';
    end if;
  end if;

  update staff_profiles set name = coalesce(nullif(btrim(p->>'name'), ''), name),
      perms = v_perms, active = v_active,
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then '{"adjusted": true}'::jsonb else '{}'::jsonb end;
end;
$function$;

create or replace function public.revoke_invite (
  p_arena  uuid,
  p_invite uuid
)
  returns void
  language sql
  set search_path to ''
  AS $function$
  select private.revoke_invite(p_arena, p_invite);
$function$;

create or replace function public.set_updated_at()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$function$;

create or replace function public.sync_fetch_entity (
  p_arena uuid,
  p_refs  jsonb
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.sync_fetch_entity(p_arena, p_refs);
$function$;

create or replace function public.sync_pull (
  p_arena  uuid,
  p_cursor text    default '0'::text,
  p_limit  integer default 2000
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.sync_pull(p_arena, p_cursor, p_limit);
$function$;

create or replace function public.sync_push (
  p_arena  uuid,
  p_ops    jsonb,
  p_device text  default null::text
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.sync_push(p_arena, p_ops, p_device);
$function$;

create or replace function public.sync_record_delete()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  insert into sync_tombstones(arena_id, table_name, row_key)
    values (old.arena_id, tg_table_name, to_jsonb(old));
  return old;
end;
$function$;

create or replace function public.sync_stamp()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
begin
  new.sync_xid := pg_current_xact_id();
  return new;
end;
$function$;

alter table "public"."activities"
  add constraint "activities_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."audit_log"
  add constraint "audit_log_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."audit_log"
  add constraint "audit_log_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."billing_policies"
  add constraint "billing_policies_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."bookings"
  add constraint "bookings_activity_id_fkey" foreign key (activity_id)
    references public.activities(id) on delete set null;

alter table "public"."bookings"
  add constraint "bookings_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."controller_allocations"
  add constraint "controller_allocations_arena_id_activity_code_fkey"
    foreign key (arena_id, activity_code) references public.activities(arena_id, code);

alter table "public"."controller_allocations"
  add constraint "controller_allocations_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."controller_allocations"
  add constraint "controller_allocations_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."controller_moves"
  add constraint "controller_moves_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."controller_moves"
  add constraint "controller_moves_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."controllers"
  add constraint "controllers_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."controller_allocations"
  add constraint "controller_allocations_controller_id_fkey" foreign key (controller_id)
    references public.controllers(id);

alter table "public"."controller_moves"
  add constraint "controller_moves_controller_id_fkey" foreign key (controller_id)
    references public.controllers(id);

alter table "public"."customers"
  add constraint "customers_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."bookings"
  add constraint "bookings_customer_id_fkey" foreign key (customer_id)
    references public.customers(id) on delete set null;

alter table "public"."game_categories"
  add constraint "game_categories_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."game_controls"
  add constraint "game_controls_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."game_resources"
  add constraint "game_resources_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."games"
  add constraint "games_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."games"
  add constraint "games_category_id_fkey" foreign key (category_id)
    references public.game_categories(id) on delete set null;

alter table "public"."bookings"
  add constraint "bookings_game_id_fkey" foreign key (game_id) references public.games(id) on delete
    set null;

alter table "public"."controller_allocations"
  add constraint "controller_allocations_game_id_fkey" foreign key (game_id)
    references public.games(id);

alter table "public"."game_controls"
  add constraint "game_controls_game_id_fkey" foreign key (game_id) references public.games(id)
    on delete cascade;

alter table "public"."game_resources"
  add constraint "game_resources_game_id_fkey" foreign key (game_id) references public.games(id)
    on delete cascade;

alter table "public"."group_assignments"
  add constraint "group_assignments_arena_id_activity_code_fkey"
    foreign key (arena_id, activity_code) references public.activities(arena_id, code);

alter table "public"."group_assignments"
  add constraint "group_assignments_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."group_assignments"
  add constraint "group_assignments_game_id_fkey" foreign key (game_id) references public.games(id);

alter table "public"."controller_allocations"
  add constraint "controller_allocations_assignment_id_fkey" foreign key (assignment_id)
    references public.group_assignments(id);

alter table "public"."group_charges"
  add constraint "group_charges_arena_id_activity_code_fkey" foreign key (arena_id, activity_code)
    references public.activities(arena_id, code);

alter table "public"."group_charges"
  add constraint "group_charges_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."group_charges"
  add constraint "group_charges_assignment_id_fkey" foreign key (assignment_id)
    references public.group_assignments(id);

alter table "public"."group_extensions"
  add constraint "group_extensions_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."group_extensions"
  add constraint "group_extensions_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."group_payments"
  add constraint "group_payments_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."group_payments"
  add constraint "group_payments_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."group_sessions"
  add constraint "group_sessions_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."group_sessions"
  add constraint "group_sessions_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."controller_allocations"
  add constraint "controller_allocations_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade;

alter table "public"."group_assignments"
  add constraint "group_assignments_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade;

alter table "public"."group_charges"
  add constraint "group_charges_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade;

alter table "public"."group_extensions"
  add constraint "group_extensions_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade;

alter table "public"."group_payments"
  add constraint "group_payments_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade;

alter table "public"."group_sessions"
  add constraint "group_sessions_primary_customer_id_fkey" foreign key (primary_customer_id)
    references public.customers(id);

alter table "public"."holidays"
  add constraint "holidays_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."payments"
  add constraint "payments_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."payments"
  add constraint "payments_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."pricing_catalog_history"
  add constraint "pricing_catalog_history_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."pricing_catalog_history"
  add constraint "pricing_catalog_history_pkey" primary key (arena_id, canon_md5);

alter table "public"."rate_bands"
  add constraint "rate_bands_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."rate_cards"
  add constraint "rate_cards_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."rates"
  add constraint "rates_activity_id_fkey" foreign key (activity_id) references public.activities(id)
    on delete cascade;

alter table "public"."rates"
  add constraint "rates_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."rates"
  add constraint "rates_band_id_fkey" foreign key (band_id) references public.rate_bands(id)
    on delete cascade;

alter table "public"."rates"
  add constraint "rates_rate_card_id_fkey" foreign key (rate_card_id)
    references public.rate_cards(id) on delete cascade;

alter table "public"."resource_activities"
  add constraint "resource_activities_activity_id_fkey" foreign key (activity_id)
    references public.activities(id) on delete cascade;

alter table "public"."resource_activities"
  add constraint "resource_activities_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."resources"
  add constraint "resources_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."bookings"
  add constraint "bookings_resource_id_fkey" foreign key (resource_id)
    references public.resources(id) on delete set null;

alter table "public"."controller_allocations"
  add constraint "controller_allocations_resource_id_fkey" foreign key (resource_id)
    references public.resources(id);

alter table "public"."controller_moves"
  add constraint "controller_moves_from_resource_id_fkey" foreign key (from_resource_id)
    references public.resources(id);

alter table "public"."controller_moves"
  add constraint "controller_moves_to_resource_id_fkey" foreign key (to_resource_id)
    references public.resources(id);

alter table "public"."controllers"
  add constraint "controllers_current_resource_id_fkey" foreign key (current_resource_id)
    references public.resources(id);

alter table "public"."controllers"
  add constraint "controllers_home_resource_id_fkey" foreign key (home_resource_id)
    references public.resources(id);

alter table "public"."game_resources"
  add constraint "game_resources_resource_id_fkey" foreign key (resource_id)
    references public.resources(id) on delete cascade;

alter table "public"."group_assignments"
  add constraint "group_assignments_resource_id_fkey" foreign key (resource_id)
    references public.resources(id);

alter table "public"."group_charges"
  add constraint "group_charges_resource_id_fkey" foreign key (resource_id)
    references public.resources(id);

alter table "public"."resource_activities"
  add constraint "resource_activities_resource_id_fkey" foreign key (resource_id)
    references public.resources(id) on delete cascade;

alter table "public"."session_charges"
  add constraint "session_charges_arena_id_activity_code_fkey" foreign key (arena_id, activity_code)
    references public.activities(arena_id, code);

alter table "public"."session_charges"
  add constraint "session_charges_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."session_charges"
  add constraint "session_charges_resource_id_fkey" foreign key (resource_id)
    references public.resources(id);

alter table "public"."session_extensions"
  add constraint "session_extensions_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."session_extensions"
  add constraint "session_extensions_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."session_segments"
  add constraint "session_segments_arena_id_activity_code_fkey"
    foreign key (arena_id, activity_code) references public.activities(arena_id, code);

alter table "public"."session_segments"
  add constraint "session_segments_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."session_segments"
  add constraint "session_segments_game_id_fkey" foreign key (game_id) references public.games(id);

alter table "public"."controller_allocations"
  add constraint "controller_allocations_segment_id_fkey" foreign key (segment_id)
    references public.session_segments(id);

alter table "public"."session_charges"
  add constraint "session_charges_segment_id_fkey" foreign key (segment_id)
    references public.session_segments(id);

alter table "public"."session_segments"
  add constraint "session_segments_resource_id_fkey" foreign key (resource_id)
    references public.resources(id);

alter table "public"."sessions"
  add constraint "sessions_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."sessions"
  add constraint "sessions_booking_id_fkey" foreign key (booking_id) references public.bookings(id)
    on delete set null;

alter table "public"."sessions"
  add constraint "sessions_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."sessions"
  add constraint "sessions_customer_id_fkey" foreign key (customer_id)
    references public.customers(id);

alter table "public"."controller_allocations"
  add constraint "controller_allocations_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade;

alter table "public"."payments"
  add constraint "payments_session_id_fkey" foreign key (session_id) references public.sessions(id)
    on delete cascade;

alter table "public"."session_charges"
  add constraint "session_charges_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade;

alter table "public"."session_extensions"
  add constraint "session_extensions_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade;

alter table "public"."session_segments"
  add constraint "session_segments_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade;

alter table "public"."settings"
  add constraint "settings_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_invites"
  add constraint "staff_invites_accepted_by_fkey" foreign key (accepted_by)
    references auth.users(id) on delete set null;

alter table "public"."staff_invites"
  add constraint "staff_invites_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_invites"
  add constraint "staff_invites_invited_by_fkey" foreign key (invited_by) references auth.users(id)
    on delete cascade;

alter table "public"."staff_profiles"
  add constraint "staff_profiles_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_profiles"
  add constraint "staff_profiles_user_id_fkey" foreign key (user_id) references auth.users(id)
    on delete cascade;

alter table "public"."sync_ops"
  add constraint "sync_ops_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

create view "public"."sync_v_arenas" with (security_invoker=true) AS  SELECT id,
    name,
    timezone,
    created_at,
    updated_at,
    sync_xid,
    id AS arena_id
   FROM public.arenas a;

create view "public"."sync_v_bookings" with (security_invoker=true) AS  SELECT bk.id,
    bk.arena_id,
    bk.customer_id,
    bk.resource_id,
    bk.activity_id,
    bk.game_id,
    bk.scheduled_start,
    bk.scheduled_end,
    bk.status,
    bk.players_required,
    bk.controller_requirement,
    bk.party_name,
    bk.phone,
    bk.notes,
    bk.reminder_status,
    bk.created_at,
    bk.updated_at,
    bk.sync_xid,
    ac.code AS activity_code
   FROM (public.bookings bk
     LEFT JOIN public.activities ac ON ((ac.id = bk.activity_id)));

create view "public"."sync_v_rates" with (security_invoker=true) AS  SELECT r.id,
    r.arena_id,
    r.rate_card_id,
    r.activity_id,
    r.band_id,
    r.controller_count,
    r.unit_minutes,
    r.price_paise,
    r.created_at,
    r.updated_at,
    r.sync_xid,
    ac.code AS activity_code,
    b.code AS band
   FROM (((public.rates r
     JOIN public.activities ac ON ((ac.id = r.activity_id)))
     JOIN public.rate_bands b ON ((b.id = r.band_id)))
     JOIN public.rate_cards c ON (((c.id = r.rate_card_id) AND c.active)));

create view "public"."sync_v_resource_activities" with (security_invoker=true) AS  SELECT ra.id,
    ra.arena_id,
    ra.resource_id,
    ra.activity_id,
    ra.created_at,
    ra.updated_at,
    ra.sync_xid,
    ac.code AS activity_code
   FROM (public.resource_activities ra
     JOIN public.activities ac ON ((ac.id = ra.activity_id)));

create index ix_activities_sync on public.activities using btree (arena_id, sync_xid);

create index ix_alloc_assignment on public.controller_allocations using btree (assignment_id);

create index ix_alloc_group on public.controller_allocations using btree (group_id);

create index ix_alloc_open_by_resource on public.controller_allocations using btree (resource_id)
  where (ended_at is null);

create index ix_alloc_request on public.controller_allocations using btree (arena_id, request_id)
  where (request_id is not null);

create index ix_alloc_session on public.controller_allocations using btree (session_id);

create index ix_arenas_sync on public.arenas using btree (sync_xid);

create index ix_assignments_group on public.group_assignments using btree (group_id, idx);

create index ix_assignments_resource on public.group_assignments
  using btree (resource_id, started_at);

create index ix_audit_entity on public.audit_log using btree (arena_id, entity_type, entity_id);

create index ix_audit_log_created_by on public.audit_log using btree (created_by);

create index ix_billing_policies_sync on public.billing_policies using btree (arena_id, sync_xid);

create index ix_bookings_activity_id on public.bookings using btree (activity_id);

create index ix_bookings_customer_id on public.bookings using btree (customer_id);

create index ix_bookings_game_id on public.bookings using btree (game_id);

create index ix_bookings_resource on public.bookings using btree (resource_id, scheduled_start);

create index ix_bookings_sync on public.bookings using btree (arena_id, sync_xid);

create index ix_charges_session on public.session_charges using btree (session_id);

create index ix_controller_allocations_activity on public.controller_allocations
  using btree (arena_id, activity_code);

create index ix_controller_allocations_created_by on public.controller_allocations
  using btree (created_by);

create index ix_controller_allocations_game_id on public.controller_allocations
  using btree (game_id);

create index ix_controller_allocations_segment_id on public.controller_allocations
  using btree (segment_id);

create index ix_controller_allocations_sync on public.controller_allocations
  using btree (arena_id, sync_xid);

create index ix_controller_moves_created_by on public.controller_moves using btree (created_by);

create index ix_controller_moves_from_resource_id on public.controller_moves
  using btree (from_resource_id);

create index ix_controller_moves_sync on public.controller_moves using btree (arena_id, sync_xid);

create index ix_controller_moves_to_resource_id on public.controller_moves
  using btree (to_resource_id);

create index ix_controllers_at_station on public.controllers
  using btree (current_resource_id, status);

create index ix_controllers_home_resource_id on public.controllers using btree (home_resource_id);

create index ix_controllers_sync on public.controllers using btree (arena_id, sync_xid);

create index ix_controls_game on public.game_controls using btree (game_id, sort_order);

create index ix_customers_directory on public.customers using btree (arena_id, name)
  where (is_guest = false);

create index ix_customers_name on public.customers using btree (arena_id, lower(name));

create index ix_customers_sync on public.customers using btree (arena_id, sync_xid);

create index ix_extensions_session on public.session_extensions using btree (session_id, created_at);

create index ix_game_categories_sync on public.game_categories using btree (arena_id, sync_xid);

create index ix_game_controls_sync on public.game_controls using btree (arena_id, sync_xid);

create index ix_game_resources_resource on public.game_resources using btree (resource_id, status);

create index ix_game_resources_sync on public.game_resources using btree (arena_id, sync_xid);

create index ix_games_active on public.games using btree (arena_id, active);

create index ix_games_category_id on public.games using btree (category_id);

create index ix_games_sync on public.games using btree (arena_id, sync_xid);

create index ix_group_assignments_activity on public.group_assignments
  using btree (arena_id, activity_code);

create index ix_group_assignments_game_id on public.group_assignments using btree (game_id);

create index ix_group_assignments_sync on public.group_assignments using btree (arena_id, sync_xid);

create index ix_group_charges_activity on public.group_charges using btree (arena_id, activity_code);

create index ix_group_charges_assignment_id on public.group_charges using btree (assignment_id);

create index ix_group_charges_group on public.group_charges using btree (group_id, charge_index);

create index ix_group_charges_resource_id on public.group_charges using btree (resource_id);

create index ix_group_charges_sync on public.group_charges using btree (arena_id, sync_xid);

create index ix_group_extensions_created_by on public.group_extensions using btree (created_by);

create index ix_group_extensions_group_id on public.group_extensions using btree (group_id);

create index ix_group_extensions_sync on public.group_extensions using btree (arena_id, sync_xid);

create index ix_group_payments_created_by on public.group_payments using btree (created_by);

create index ix_group_payments_group on public.group_payments using btree (group_id, created_at);

create index ix_group_payments_sync on public.group_payments using btree (arena_id, sync_xid);

create index ix_group_sessions_created_by on public.group_sessions using btree (created_by);

create index ix_group_sessions_primary_customer_id on public.group_sessions
  using btree (primary_customer_id);

create index ix_group_sessions_sync on public.group_sessions using btree (arena_id, sync_xid);

create index ix_groups_arena_status on public.group_sessions using btree (arena_id, status);

create index ix_holidays_sync on public.holidays using btree (arena_id, sync_xid);

create index ix_moves_controller on public.controller_moves using btree (controller_id, moved_at);

create index ix_payments_created_by on public.payments using btree (created_by);

create index ix_payments_session on public.payments using btree (session_id, created_at);

create index ix_payments_sync on public.payments using btree (arena_id, sync_xid);

create index ix_rate_bands_sync on public.rate_bands using btree (arena_id, sync_xid);

create index ix_rate_cards_sync on public.rate_cards using btree (arena_id, sync_xid);

create index ix_rates_activity_id on public.rates using btree (activity_id);

create index ix_rates_band_id on public.rates using btree (band_id);

create index ix_rates_sync on public.rates using btree (arena_id, sync_xid);

create index ix_resource_activities_activity_id on public.resource_activities
  using btree (activity_id);

create index ix_resource_activities_sync on public.resource_activities
  using btree (arena_id, sync_xid);

create index ix_resources_sync on public.resources using btree (arena_id, sync_xid);

create index ix_segments_resource_time on public.session_segments
  using btree (resource_id, started_at);

create index ix_segments_session on public.session_segments using btree (session_id, idx);

create index ix_session_charges_activity on public.session_charges
  using btree (arena_id, activity_code);

create index ix_session_charges_resource_id on public.session_charges using btree (resource_id);

create index ix_session_charges_segment_id on public.session_charges using btree (segment_id);

create index ix_session_charges_sync on public.session_charges using btree (arena_id, sync_xid);

create index ix_session_extensions_created_by on public.session_extensions using btree (created_by);

create index ix_session_extensions_sync on public.session_extensions
  using btree (arena_id, sync_xid);

create index ix_session_segments_activity on public.session_segments
  using btree (arena_id, activity_code);

create index ix_session_segments_game_id on public.session_segments using btree (game_id);

create index ix_session_segments_sync on public.session_segments using btree (arena_id, sync_xid);

create index ix_sessions_arena_status on public.sessions using btree (arena_id, status);

create index ix_sessions_booking_id on public.sessions using btree (booking_id);

create index ix_sessions_created_by on public.sessions using btree (created_by);

create index ix_sessions_customer_id on public.sessions using btree (customer_id);

create index ix_sessions_started on public.sessions using btree (arena_id, started_at);

create index ix_sessions_sync on public.sessions using btree (arena_id, sync_xid);

create index ix_settings_sync on public.settings using btree (arena_id, sync_xid);

create index ix_staff_profiles_sync on public.staff_profiles using btree (arena_id, sync_xid);

create index ix_staff_user on public.staff_profiles using btree (user_id);

create index ix_sync_ops_arena on public.sync_ops using btree (arena_id, created_at);

create index ix_tombstones_sync on public.sync_tombstones using btree (arena_id, sync_xid);

create index staff_invites_accepted_by_idx on public.staff_invites using btree (accepted_by);

create index staff_invites_invited_by_idx on public.staff_invites using btree (invited_by);

create unique index staff_invites_one_open on public.staff_invites using btree (arena_id, email)
  where ((accepted_at is null) AND (revoked_at is null));

create unique index ux_assignments_request on public.group_assignments
  using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_customer_phone on public.customers using btree (arena_id, phone)
  where (phone is not null);

create unique index ux_extensions_request on public.session_extensions
  using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_group_extensions_request on public.group_extensions
  using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_group_payments_request on public.group_payments
  using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_groups_request on public.group_sessions using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_one_open_allocation_per_controller on public.controller_allocations
  using btree (controller_id)
  where (ended_at is null);

create unique index ux_one_open_segment_per_resource on public.session_segments
  using btree (resource_id)
  where (ended_at is null);

create unique index ux_payments_request on public.payments using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_rate_per_combination on public.rates
  using btree (rate_card_id, activity_id, band_id, COALESCE(controller_count, '-1'::integer));

create unique index ux_segments_request on public.session_segments
  using btree (arena_id, request_id)
  where (request_id is not null);

create unique index ux_sessions_request on public.sessions using btree (arena_id, request_id)
  where (request_id is not null);

create trigger t_activities_sync
  before insert or update on public.activities
  for each row
  execute function public.sync_stamp();

create trigger t_activities_tomb
  after delete on public.activities
  for each row
  execute function public.sync_record_delete();

create trigger t_activities_updated
  before update on public.activities
  for each row
  execute function public.set_updated_at();

create trigger t_arenas_sync
  before insert or update on public.arenas
  for each row
  execute function public.sync_stamp();

create trigger t_arenas_updated
  before update on public.arenas
  for each row
  execute function public.set_updated_at();

create trigger t_billing_policies_sync
  before insert or update on public.billing_policies
  for each row
  execute function public.sync_stamp();

create trigger t_billing_policies_tomb
  after delete on public.billing_policies
  for each row
  execute function public.sync_record_delete();

create trigger t_billing_policies_updated
  before update on public.billing_policies
  for each row
  execute function public.set_updated_at();

create trigger t_bookings_sync
  before insert or update on public.bookings
  for each row
  execute function public.sync_stamp();

create trigger t_bookings_tomb
  after delete on public.bookings
  for each row
  execute function public.sync_record_delete();

create trigger t_bookings_updated
  before update on public.bookings
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.bookings
  for each row
  execute function
    public._assert_same_arena('customer_id', 'customers', 'game_id', 'games', 'resource_id',
    'resources', 'activity_id', 'activities');

create trigger t_controller_allocations_sync
  before insert or update on public.controller_allocations
  for each row
  execute function public.sync_stamp();

create trigger t_controller_allocations_tomb
  after delete on public.controller_allocations
  for each row
  execute function public.sync_record_delete();

create trigger t_controller_free
  before insert or update of controller_id, ended_at on public.controller_allocations
  for each row
  execute function public.assert_controller_free_for_allocation();

create trigger t_same_arena
  before insert or update on public.controller_allocations
  for each row
  execute function
    public._assert_same_arena('assignment_id', 'group_assignments', 'controller_id', 'controllers',
    'game_id',
    'games',
    'group_id',
    'group_sessions',
    'resource_id', 'resources', 'segment_id', 'session_segments', 'session_id', 'sessions');

create trigger t_controller_moves_sync
  before insert or update on public.controller_moves
  for each row
  execute function public.sync_stamp();

create trigger t_controller_moves_tomb
  after delete on public.controller_moves
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.controller_moves
  for each row
  execute function
    public._assert_same_arena('controller_id', 'controllers', 'from_resource_id', 'resources',
    'to_resource_id', 'resources');

create trigger t_controllers_sync
  before insert or update on public.controllers
  for each row
  execute function public.sync_stamp();

create trigger t_controllers_tomb
  after delete on public.controllers
  for each row
  execute function public.sync_record_delete();

create trigger t_controllers_updated
  before update on public.controllers
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.controllers
  for each row
  execute function
    public._assert_same_arena('current_resource_id', 'resources', 'home_resource_id', 'resources');

create trigger t_customers_sync
  before insert or update on public.customers
  for each row
  execute function public.sync_stamp();

create trigger t_customers_tomb
  after delete on public.customers
  for each row
  execute function public.sync_record_delete();

create trigger t_customers_updated
  before update on public.customers
  for each row
  execute function public.set_updated_at();

create trigger t_game_categories_sync
  before insert or update on public.game_categories
  for each row
  execute function public.sync_stamp();

create trigger t_game_categories_tomb
  after delete on public.game_categories
  for each row
  execute function public.sync_record_delete();

create trigger t_game_categories_updated
  before update on public.game_categories
  for each row
  execute function public.set_updated_at();

create trigger t_game_controls_sync
  before insert or update on public.game_controls
  for each row
  execute function public.sync_stamp();

create trigger t_game_controls_tomb
  after delete on public.game_controls
  for each row
  execute function public.sync_record_delete();

create trigger t_game_controls_updated
  before update on public.game_controls
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.game_controls
  for each row
  execute function public._assert_same_arena('game_id', 'games');

create trigger t_game_resources_sync
  before insert or update on public.game_resources
  for each row
  execute function public.sync_stamp();

create trigger t_game_resources_tomb
  after delete on public.game_resources
  for each row
  execute function public.sync_record_delete();

create trigger t_game_resources_updated
  before update on public.game_resources
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.game_resources
  for each row
  execute function public._assert_same_arena('game_id', 'games', 'resource_id', 'resources');

create trigger t_games_sync
  before insert or update on public.games
  for each row
  execute function public.sync_stamp();

create trigger t_games_tomb
  after delete on public.games
  for each row
  execute function public.sync_record_delete();

create trigger t_games_updated
  before update on public.games
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.games
  for each row
  execute function public._assert_same_arena('category_id', 'game_categories');

create trigger t_assignment_resource_free
  before insert or update of resource_id, ended_at on public.group_assignments
  for each row
  execute function public.assert_resource_free_for_assignment();

create trigger t_group_assignments_sync
  before insert or update on public.group_assignments
  for each row
  execute function public.sync_stamp();

create trigger t_group_assignments_tomb
  after delete on public.group_assignments
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.group_assignments
  for each row
  execute function
    public._assert_same_arena('game_id', 'games', 'group_id', 'group_sessions', 'resource_id',
    'resources');

create trigger t_group_charges_sync
  before insert or update on public.group_charges
  for each row
  execute function public.sync_stamp();

create trigger t_group_charges_tomb
  after delete on public.group_charges
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.group_charges
  for each row
  execute function
    public._assert_same_arena('assignment_id', 'group_assignments', 'group_id', 'group_sessions',
    'resource_id', 'resources');

create trigger t_group_extensions_sync
  before insert or update on public.group_extensions
  for each row
  execute function public.sync_stamp();

create trigger t_group_extensions_tomb
  after delete on public.group_extensions
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.group_extensions
  for each row
  execute function public._assert_same_arena('group_id', 'group_sessions');

create trigger t_group_payments_sync
  before insert or update on public.group_payments
  for each row
  execute function public.sync_stamp();

create trigger t_group_payments_tomb
  after delete on public.group_payments
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.group_payments
  for each row
  execute function public._assert_same_arena('group_id', 'group_sessions');

create trigger t_group_sessions_sync
  before insert or update on public.group_sessions
  for each row
  execute function public.sync_stamp();

create trigger t_group_sessions_tomb
  after delete on public.group_sessions
  for each row
  execute function public.sync_record_delete();

create trigger t_groups_updated
  before update on public.group_sessions
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.group_sessions
  for each row
  execute function public._assert_same_arena('primary_customer_id', 'customers');

create trigger t_holidays_sync
  before insert or update on public.holidays
  for each row
  execute function public.sync_stamp();

create trigger t_holidays_tomb
  after delete on public.holidays
  for each row
  execute function public.sync_record_delete();

create trigger t_holidays_updated
  before update on public.holidays
  for each row
  execute function public.set_updated_at();

create trigger t_payments_sync
  before insert or update on public.payments
  for each row
  execute function public.sync_stamp();

create trigger t_payments_tomb
  after delete on public.payments
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.payments
  for each row
  execute function public._assert_same_arena('session_id', 'sessions');

create trigger t_rate_bands_sync
  before insert or update on public.rate_bands
  for each row
  execute function public.sync_stamp();

create trigger t_rate_bands_tomb
  after delete on public.rate_bands
  for each row
  execute function public.sync_record_delete();

create trigger t_rate_bands_updated
  before update on public.rate_bands
  for each row
  execute function public.set_updated_at();

create trigger t_rate_cards_sync
  before insert or update on public.rate_cards
  for each row
  execute function public.sync_stamp();

create trigger t_rate_cards_tomb
  after delete on public.rate_cards
  for each row
  execute function public.sync_record_delete();

create trigger t_rate_cards_updated
  before update on public.rate_cards
  for each row
  execute function public.set_updated_at();

create trigger t_rates_sync
  before insert or update on public.rates
  for each row
  execute function public.sync_stamp();

create trigger t_rates_tomb
  after delete on public.rates
  for each row
  execute function public.sync_record_delete();

create trigger t_rates_updated
  before update on public.rates
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.rates
  for each row
  execute function
    public._assert_same_arena('activity_id', 'activities', 'band_id', 'rate_bands', 'rate_card_id',
    'rate_cards');

create trigger t_resource_activities_sync
  before insert or update on public.resource_activities
  for each row
  execute function public.sync_stamp();

create trigger t_resource_activities_tomb
  after delete on public.resource_activities
  for each row
  execute function public.sync_record_delete();

create trigger t_resource_activities_updated
  before update on public.resource_activities
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.resource_activities
  for each row
  execute function
    public._assert_same_arena('activity_id', 'activities', 'resource_id', 'resources');

create trigger t_resources_sync
  before insert or update on public.resources
  for each row
  execute function public.sync_stamp();

create trigger t_resources_tomb
  after delete on public.resources
  for each row
  execute function public.sync_record_delete();

create trigger t_resources_updated
  before update on public.resources
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.session_charges
  for each row
  execute function
    public._assert_same_arena('resource_id', 'resources', 'segment_id', 'session_segments',
    'session_id', 'sessions');

create trigger t_session_charges_sync
  before insert or update on public.session_charges
  for each row
  execute function public.sync_stamp();

create trigger t_session_charges_tomb
  after delete on public.session_charges
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.session_extensions
  for each row
  execute function public._assert_same_arena('session_id', 'sessions');

create trigger t_session_extensions_sync
  before insert or update on public.session_extensions
  for each row
  execute function public.sync_stamp();

create trigger t_session_extensions_tomb
  after delete on public.session_extensions
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.session_segments
  for each row
  execute function
    public._assert_same_arena('game_id', 'games', 'resource_id', 'resources', 'session_id',
    'sessions');

create trigger t_segment_resource_free
  before insert or update of resource_id, ended_at on public.session_segments
  for each row
  execute function public.assert_resource_free_for_segment();

create trigger t_session_segments_sync
  before insert or update on public.session_segments
  for each row
  execute function public.sync_stamp();

create trigger t_session_segments_tomb
  after delete on public.session_segments
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.sessions
  for each row
  execute function public._assert_same_arena('booking_id', 'bookings', 'customer_id', 'customers');

create trigger t_sessions_sync
  before insert or update on public.sessions
  for each row
  execute function public.sync_stamp();

create trigger t_sessions_tomb
  after delete on public.sessions
  for each row
  execute function public.sync_record_delete();

create trigger t_sessions_updated
  before update on public.sessions
  for each row
  execute function public.set_updated_at();

create trigger t_settings_sync
  before insert or update on public.settings
  for each row
  execute function public.sync_stamp();

create trigger t_settings_tomb
  after delete on public.settings
  for each row
  execute function public.sync_record_delete();

create trigger t_settings_updated
  before update on public.settings
  for each row
  execute function public.set_updated_at();

create trigger t_staff_profiles_sync
  before insert or update on public.staff_profiles
  for each row
  execute function public.sync_stamp();

create trigger t_staff_profiles_tomb
  after delete on public.staff_profiles
  for each row
  execute function public.sync_record_delete();

create trigger t_staff_updated
  before update on public.staff_profiles
  for each row
  execute function public.set_updated_at();

create policy "p_sel_activities" on "public"."activities"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_arenas" on "public"."arenas"
  for select
  to "authenticated"
  using ((id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_audit_log" on "public"."audit_log"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['money'::text, 'reports'::text]) as
    app_arena_ids_with)));

create policy "p_sel_billing_policies" on "public"."billing_policies"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_bookings" on "public"."bookings"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_controller_allocations" on "public"."controller_allocations"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_controller_moves" on "public"."controller_moves"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_controllers" on "public"."controllers"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_customers" on "public"."customers"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['start'::text, 'members'::text,
    'money'::text, 'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_game_categories" on "public"."game_categories"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_game_controls" on "public"."game_controls"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_game_resources" on "public"."game_resources"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_games" on "public"."games"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_assignments" on "public"."group_assignments"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_charges" on "public"."group_charges"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_group_extensions" on "public"."group_extensions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_payments" on "public"."group_payments"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_group_sessions" on "public"."group_sessions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_holidays" on "public"."holidays"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_payments" on "public"."payments"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_rate_bands" on "public"."rate_bands"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_rate_cards" on "public"."rate_cards"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_rates" on "public"."rates"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_resource_activities" on "public"."resource_activities"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_resources" on "public"."resources"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_session_charges" on "public"."session_charges"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_session_extensions" on "public"."session_extensions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_session_segments" on "public"."session_segments"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_sessions" on "public"."sessions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_settings" on "public"."settings"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_staff" on "public"."staff_profiles"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "arena_members_receive" on "realtime"."messages"
  for select
  to "authenticated"
  using
    (((extension = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND
    private.can_use_arena_topic(( select realtime.topic() as topic))));

create policy "arena_members_send" on "realtime"."messages"
  for insert
  to "authenticated"
  with
    check
    (((extension = 'broadcast'::text) AND private.can_use_arena_topic(( SELECT realtime.topic() AS
    topic))));

alter publication "supabase_realtime" add table "public"."activities";

alter publication "supabase_realtime" add table "public"."billing_policies";

alter publication "supabase_realtime" add table "public"."bookings";

alter publication "supabase_realtime" add table "public"."controller_allocations";

alter publication "supabase_realtime" add table "public"."controller_moves";

alter publication "supabase_realtime" add table "public"."controllers";

alter publication "supabase_realtime" add table "public"."customers";

alter publication "supabase_realtime" add table "public"."game_categories";

alter publication "supabase_realtime" add table "public"."game_controls";

alter publication "supabase_realtime" add table "public"."game_resources";

alter publication "supabase_realtime" add table "public"."games";

alter publication "supabase_realtime" add table "public"."group_assignments";

alter publication "supabase_realtime" add table "public"."group_charges";

alter publication "supabase_realtime" add table "public"."group_extensions";

alter publication "supabase_realtime" add table "public"."group_payments";

alter publication "supabase_realtime" add table "public"."group_sessions";

alter publication "supabase_realtime" add table "public"."holidays";

alter publication "supabase_realtime" add table "public"."payments";

alter publication "supabase_realtime" add table "public"."rate_bands";

alter publication "supabase_realtime" add table "public"."rate_cards";

alter publication "supabase_realtime" add table "public"."rates";

alter publication "supabase_realtime" add table "public"."resource_activities";

alter publication "supabase_realtime" add table "public"."resources";

alter publication "supabase_realtime" add table "public"."session_charges";

alter publication "supabase_realtime" add table "public"."session_extensions";

alter publication "supabase_realtime" add table "public"."session_segments";

alter publication "supabase_realtime" add table "public"."sessions";

alter publication "supabase_realtime" add table "public"."settings";

alter publication "supabase_realtime" add table "public"."staff_profiles";

comment on column "public"."activities"."active" is 'App-side flag for retiring an activity without deleting it. Not consulted server-side: the pricing snapshot includes inactive activities.';

comment on column "public"."activities"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."activities"."code" is 'Stable business code, unique per arena (e.g. PS5). Segments, assignments, rates and pricing snapshots reference activities by this code.';

comment on column "public"."activities"."duration_model" is 'How time is billed: hourly (by time, per billing_policies.billing_unit), unit (whole units of rates.unit_minutes, per billing_policies.vr_unit_rounding) or flat_hourly (priced like hourly by the server pricer).';

comment on column "public"."activities"."happy_hour_eligible" is 'When false the happy-hour band never applies; the whole session is priced at the standard band.';

comment on column "public"."activities"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."activities"."uses_controllers" is 'True when sessions of this activity hold physical controllers (pads), so controller counts, allocations and borrowing apply.';

comment on column "public"."activities"."uses_games" is 'True when a game is picked for sessions of this activity (app flag; not checked server-side).';

comment on column "public"."arenas"."area" is 'Locality shown with the arena name (e.g. Koramangala); null when not set. Written by arena.update.';

comment on column "public"."arenas"."phone" is 'Arena contact number, 6–20 of digits, spaces, +, ( ) and -; null when not set. Written by arena.update.';

comment on column "public"."arenas"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."arenas"."timezone" is 'IANA time zone name of the centre. Informational: server pricing uses a fixed Asia/Kolkata +05:30 offset and does not read this column.';

comment on column "public"."audit_log"."action" is 'What happened: void, waive, payment_correct or duplicate_phone_on_sync.';

comment on column "public"."audit_log"."after" is 'Relevant state after the action, if recorded (e.g. the clashing phone and existing customer id).';

comment on column "public"."audit_log"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."audit_log"."before" is 'Relevant state before the action, if recorded.';

comment on column "public"."audit_log"."created_by" is 'auth.users id of the staff member whose sync op caused the entry.';

comment on column "public"."audit_log"."entity_id" is 'Id of the row acted on (no FK; entity_type names its table).';

comment on column "public"."audit_log"."entity_type" is 'Kind of row acted on, e.g. session, group_session, customer.';

comment on column "public"."audit_log"."reason" is 'Human reason (the void or correction reason, the waive reason when given, or a system explanation).';

comment on column "public"."billing_policies"."active" is 'Only active rows are considered; the oldest active one (by created_at) is used.';

comment on column "public"."billing_policies"."allow_extend_past_close" is 'When false an extension stops at closing time (applied by the app''s session planner).';

comment on column "public"."billing_policies"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."billing_policies"."billing_unit" is 'per_minute (prorated by the second), or block_15 / block_30 / block_60 (billed minutes rounded to the block per block_rounding). Ignored for unit-model activities.';

comment on column "public"."billing_policies"."block_rounding" is 'How billed minutes are rounded to a block: up or nearest.';

comment on column "public"."billing_policies"."cleaning_gap_minutes" is 'Minutes a resource is held free after a session ends. Stored setting; not enforced server-side.';

comment on column "public"."billing_policies"."early_exit" is 'If a customer leaves early, bill the time actually played (actual) or the full booked duration (planned). Snapshotted with the policy; not applied by the server pricer.';

comment on column "public"."billing_policies"."grace_minutes" is 'Play of this many minutes or less is free (checked per priced interval).';

comment on column "public"."billing_policies"."group_billing_mode" is 'per_system (each system billed at its own controller count) or shared_controller_pool (the group''s purchased controller count priced once over the group window).';

comment on column "public"."billing_policies"."late_arrival" is 'Bill a late arrival from the actual or the planned start. Snapshotted with the policy; not applied by the server pricer.';

comment on column "public"."billing_policies"."minimum_charge_minutes" is 'Shortest billable time: shorter play is billed as if it lasted this many minutes.';

comment on column "public"."billing_policies"."money_rounding_dir" is 'Direction of the final cash rounding: nearest or up.';

comment on column "public"."billing_policies"."money_rounding_paise" is 'Final cash total is rounded to a multiple of this many paise (100 = 1 rupee); 1 or less means no rounding.';

comment on column "public"."billing_policies"."payment_timing" is 'When payment may be recorded: either, start or end. Snapshotted with the policy; not enforced server-side.';

comment on column "public"."billing_policies"."rounding_scope" is 'Where price math is rounded to whole paise: once on the session total (session) or separately for each segment (segment).';

comment on column "public"."billing_policies"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."billing_policies"."vr_unit_rounding" is 'For unit-model activities: round played time up to whole units, to the nearest unit, or prorate.';

comment on column "public"."bookings"."activity_id" is 'Reserved activity (uuid; ops resolve it from the activity code the device sends).';

comment on column "public"."bookings"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."bookings"."controller_requirement" is 'Number of controllers requested, if stated.';

comment on column "public"."bookings"."customer_id" is 'Registered customer, if any; a walk-in reservation may use party_name / phone instead.';

comment on column "public"."bookings"."party_name" is 'Name for a walk-in reservation with no customer record yet.';

comment on column "public"."bookings"."phone" is 'Contact phone for the reservation.';

comment on column "public"."bookings"."players_required" is 'Number of players expected, if stated.';

comment on column "public"."bookings"."reminder_status" is 'Device reminder state: scheduled, off (silenced), missed (lead time already passed when booked) or done (nothing pending). Set from the device at create; no op changes it afterwards.';

comment on column "public"."bookings"."resource_id" is 'Reserved station; null = no specific station (no overlap check).';

comment on column "public"."bookings"."scheduled_end" is 'Reserved window end (UTC); after scheduled_start.';

comment on column "public"."bookings"."scheduled_start" is 'Reserved window start (UTC).';

comment on column "public"."bookings"."status" is 'booked (open; editable), checked_in (a session started from it), cancelled or no_show.';

comment on column "public"."bookings"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor and the base_version for stale-edit checks.';

comment on column "public"."controller_allocations"."activity_code" is 'Activity business code of the play the pad was used for.';

comment on column "public"."controller_allocations"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."controller_allocations"."assignment_id" is 'Group assignment the pad belongs to (scope group); closed with it.';

comment on column "public"."controller_allocations"."created_by" is 'auth.users id of the staff member whose sync op allocated the pad.';

comment on column "public"."controller_allocations"."ended_at" is 'When the pad was released (UTC); null = still in use.';

comment on column "public"."controller_allocations"."group_id" is 'Group session holding the pad (scope group).';

comment on column "public"."controller_allocations"."player_label" is 'Group player''s display name at allocation time (scope group).';

comment on column "public"."controller_allocations"."player_number" is 'Group player number holding the pad (scope group).';

comment on column "public"."controller_allocations"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."controller_allocations"."resource_id" is 'Station where the pad is used; may differ from the pad''s home after a borrow.';

comment on column "public"."controller_allocations"."scope" is 'single (session_id + segment_id set) or group (group_id + assignment_id + player_number set).';

comment on column "public"."controller_allocations"."segment_id" is 'Session segment the pad belongs to (scope single); closed with it.';

comment on column "public"."controller_allocations"."session_id" is 'Single session holding the pad (scope single).';

comment on column "public"."controller_allocations"."started_at" is 'When the pad was handed out (UTC; the segment / assignment start).';

comment on column "public"."controller_allocations"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."controller_moves"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."controller_moves"."created_by" is 'auth.users id of the staff member whose sync op moved the pad.';

comment on column "public"."controller_moves"."from_resource_id" is 'Station the pad actually was at (not necessarily its home).';

comment on column "public"."controller_moves"."kind" is 'loan (pad owes a return to its home), permanent (to_resource_id becomes its new home) or returnHome (back to its home; loan cleared).';

comment on column "public"."controller_moves"."moved_at" is 'When the pad was carried (UTC), as reported by the device (or the server time if none was sent).';

comment on column "public"."controller_moves"."session_ref" is 'For a loan, the borrowing session as app text ''s:<session id>'' or ''g:<group id>'' (not an FK); null otherwise.';

comment on column "public"."controller_moves"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."controller_moves"."to_resource_id" is 'Station the pad was carried to.';

comment on column "public"."controllers"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."controllers"."current_resource_id" is 'Station where the pad physically is now; equals home_resource_id unless it has been moved.';

comment on column "public"."controllers"."home_resource_id" is 'Station the pad belongs to and is returned to. Changed only by a permanent move (re-homing, needs settings).';

comment on column "public"."controllers"."label" is 'The marking on the pad (e.g. HEX-1), which staff use to find it.';

comment on column "public"."controllers"."loan_return_to" is 'Set while the pad is on loan away from home: the home station id (uuid as text) it must go back to; null otherwise.';

comment on column "public"."controllers"."loan_session_ref" is 'Set while on loan: the session that owes the return, as s:<sessionId> or g:<groupId> (app reference string, not a foreign key).';

comment on column "public"."controllers"."notes" is 'Why the pad is in its current status (e.g. stick drift).';

comment on column "public"."controllers"."status" is 'One of usable, faulty, missing, retired, unavailable. Only usable pads count as free and can be borrowed or allocated. While the arena has any non-retired pad, count-only starts are checked against free pads at the station (_inventory_tracked).';

comment on column "public"."controllers"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."customers"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."customers"."birth_year" is 'Year of birth given at registration, for age checks (age ratings); null when not given. Written by customer.create / customer.update only when the key is sent; ops refuse a future year.';

comment on column "public"."customers"."is_guest" is 'True for a walk-in started without registering: one record per visit, kept out of the members directory.';

comment on column "public"."customers"."last_visit_at" is 'Start time of the customer''s latest session or group session (UTC); set by op_session_start / op_group_create.';

comment on column "public"."customers"."phone" is 'Contact number, trimmed; null when unknown. Unique per arena when set (ux_customer_phone).';

comment on column "public"."customers"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull. Also the base_version a device sends with customer.update.';

comment on column "public"."game_categories"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."game_categories"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."game_controls"."action" is 'What the player does (e.g. Shoot, Sprint).';

comment on column "public"."game_controls"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."game_controls"."buttons" is 'Controller button names that perform the action, in order (e.g. {CIRCLE}). Free text.';

comment on column "public"."game_controls"."image_url" is 'Optional URL of an illustration for the action.';

comment on column "public"."game_controls"."section" is 'Group heading within the guide (e.g. Attacking, Defending).';

comment on column "public"."game_controls"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."game_resources"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."game_resources"."notes" is 'Staff note explaining the status (e.g. why it is not playable).';

comment on column "public"."game_resources"."status" is 'One of playable, not_playable, not_installed, maintenance, temporarily_unavailable. Anything but playable (or a missing row) blocks the game on that resource.';

comment on column "public"."game_resources"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."games"."active" is 'False archives the title: hidden from new sessions and bookings on every device, kept for the sessions, bills and bookings that refer to it (game.set_active).';

comment on column "public"."games"."age_rating" is 'Minimum age the title is rated for (PEGI-style 3, 7, 12, 16 or 18); null when not set. Shown on the admin dashboard; the floor app does not read it yet.';

comment on column "public"."games"."aliases" is 'Alternative names used for search (e.g. FIFA for EA SPORTS FC 25).';

comment on column "public"."games"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."games"."category_id" is 'Optional game_categories row; set to null if the category is deleted.';

comment on column "public"."games"."last_played_at" is 'Start time (UTC) of the latest session segment or group placement on this game.';

comment on column "public"."games"."max_local_players" is 'Most players (controllers) one system may use at once on this title, 1-8. Starts, reconfigures and group placements above it are refused with players_exceeded.';

comment on column "public"."games"."media" is 'How the arena owns the title: digital or disc; null when not set. Shown on the admin dashboard; the floor app does not read it yet.';

comment on column "public"."games"."platforms" is 'Platform tags the title runs on (e.g. PS5, PSVR2). Free text; not validated.';

comment on column "public"."games"."player_mode" is 'One of single, local (local multiplayer), online (online multiplayer), both (local and online).';

comment on column "public"."games"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."group_assignments"."activity_code" is 'Activity business code (not uuid), tied to the arena''s catalog by the composite FK.';

comment on column "public"."group_assignments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_assignments"."controller_count" is 'Controllers this player uses (1 to 4); equals the number of allocated pads when pads are tracked. Null when not applicable.';

comment on column "public"."group_assignments"."ended_at" is 'When the player left this station (UTC); null = the open assignment.';

comment on column "public"."group_assignments"."idx" is '0-based position of this assignment in the player''s own history (each switch or re-add + 1).';

comment on column "public"."group_assignments"."player_label" is 'Display name for the player; carried over on a switch.';

comment on column "public"."group_assignments"."player_number" is 'Player''s number within the group (> 0); stable across switches.';

comment on column "public"."group_assignments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_assignments"."resource_id" is 'Station the player is on.';

comment on column "public"."group_assignments"."started_at" is 'When the player started on this station (UTC), as reported by the device.';

comment on column "public"."group_assignments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_charges"."amount_paise" is 'Line amount in integer paise before bill-level cash rounding; the group total is group_sessions.billed_amount_paise.';

comment on column "public"."group_charges"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_charges"."assignment_id" is 'Assignment billed by this line when exactly one player was on the station for it; null for shared or pooled lines.';

comment on column "public"."group_charges"."band_code" is 'Price band: standard or happy (happy hour).';

comment on column "public"."group_charges"."billed_minutes" is 'Minutes charged after billing-unit / block rounding (or units x unit_minutes for unit-priced activities).';

comment on column "public"."group_charges"."charge_index" is '0-based ordinal of this line within the group''s bill.';

comment on column "public"."group_charges"."controller_count" is 'Controller count the rate was looked up for (combined per station, or the purchased count for the pooled line).';

comment on column "public"."group_charges"."played_minutes" is 'Whole minutes actually played inside this interval.';

comment on column "public"."group_charges"."player_number" is 'That player''s number when the line belongs to one player; otherwise null.';

comment on column "public"."group_charges"."resource_id" is 'Station billed; null for the pooled-controller line.';

comment on column "public"."group_charges"."segment_end" is 'End of the billed interval (UTC); can extend past the actual end when the minimum charge applies.';

comment on column "public"."group_charges"."segment_start" is 'Start of the billed interval (UTC).';

comment on column "public"."group_charges"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_charges"."unit_minutes" is 'Length in minutes of the rate''s pricing unit that unit_price_paise buys.';

comment on column "public"."group_charges"."unit_price_paise" is 'Rate price per unit_minutes, in integer paise, from the group''s pricing_snapshot.';

comment on column "public"."group_extensions"."added_amount_paise" is 'Extra cost in integer paise: server group subtotal at new_end_at minus subtotal at old_end_at; a mismatch refuses the op.';

comment on column "public"."group_extensions"."added_minutes" is 'Minutes added, as sent by the device (> 0).';

comment on column "public"."group_extensions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_extensions"."created_by" is 'auth.users id of the staff member whose sync op extended the group.';

comment on column "public"."group_extensions"."new_end_at" is 'Group scheduled_end_at after this extension (UTC).';

comment on column "public"."group_extensions"."old_end_at" is 'Group scheduled_end_at before this extension (UTC); must match the server''s value or the op is refused as stale.';

comment on column "public"."group_extensions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_extensions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_payments"."amount_paise" is 'Signed integer paise: positive for a payment, negative for a refund, never zero.';

comment on column "public"."group_payments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_payments"."created_by" is 'auth.users id of the staff member whose sync op recorded the payment.';

comment on column "public"."group_payments"."is_refund" is 'True for a refund; must agree with the sign of amount_paise (payments.kind is the single-session equivalent).';

comment on column "public"."group_payments"."method" is 'cash, upi, card or other.';

comment on column "public"."group_payments"."note" is 'Free-text staff note.';

comment on column "public"."group_payments"."reason" is 'Why the refund was given; required when is_refund.';

comment on column "public"."group_payments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_payments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_sessions"."actual_ended_at" is 'When the group actually ended (UTC); null while active.';

comment on column "public"."group_sessions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_sessions"."billed_amount_paise" is 'Final bill in integer paise after cash rounding; null until ended. Must equal the server''s re-pricing exactly.';

comment on column "public"."group_sessions"."billing_mode" is 'per_system (each station billed at its own controller count) or shared_controller_pool (purchased controllers billed once over the window); must equal the snapshot policy''s group_billing_mode.';

comment on column "public"."group_sessions"."created_by" is 'auth.users id of the staff member whose sync op created the group.';

comment on column "public"."group_sessions"."payment_status" is 'unpaid, partial, paid or waived; recomputed from group_payments against billed_amount_paise. waived is sticky.';

comment on column "public"."group_sessions"."player_count" is 'Number of players in the party (> 0), as declared at create.';

comment on column "public"."group_sessions"."policy_snapshot" is 'The billing policy part of pricing_snapshot (pricing_snapshot->''policy''), stored separately at create.';

comment on column "public"."group_sessions"."pricing_snapshot" is 'Immutable copy of the arena''s price list frozen at create; must match the current catalog or one retired within 72 h (_assert_snapshot). Every bill and extension is priced from it.';

comment on column "public"."group_sessions"."primary_customer_id" is 'Lead customer of the group; op_group_create records the visit on this customer.';

comment on column "public"."group_sessions"."purchased_controller_count" is
  'Controllers bought for the whole window in shared_controller_pool mode (staff''s declaration); 0 otherwise.';

comment on column "public"."group_sessions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_sessions"."scheduled_end_at" is 'Planned end of the shared countdown (UTC); moved by group_extensions.';

comment on column "public"."group_sessions"."started_at" is 'Group start (UTC), as reported by the device.';

comment on column "public"."group_sessions"."status" is 'active, completed (ended and billed by op_group_end) or voided (owner void; row kept).';

comment on column "public"."group_sessions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_sessions"."void_reason" is 'Reason given by the owner when voiding; also written to audit_log.';

comment on column "public"."holidays"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."holidays"."closed" is 'True when the arena is closed that day (listed in the snapshot''s closed_days); false = open, but without happy hour.';

comment on column "public"."holidays"."day" is 'Business calendar day in Asia/Kolkata (IST); unique per arena.';

comment on column "public"."holidays"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."payments"."amount_paise" is 'Signed integer paise: positive for a payment, negative for a refund, never zero.';

comment on column "public"."payments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."payments"."created_by" is 'auth.users id of the staff member whose sync op recorded the payment.';

comment on column "public"."payments"."kind" is 'payment or refund; must agree with the sign of amount_paise.';

comment on column "public"."payments"."method" is 'cash, upi, card or other.';

comment on column "public"."payments"."note" is 'Free-text staff note.';

comment on column "public"."payments"."reason" is 'Why the refund was given; required when kind = refund.';

comment on column "public"."payments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."payments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."pricing_catalog_history"."arena_id" is 'Owning arena (tenant). No client access: RLS is enabled with no policy and grants are revoked.';

comment on column "public"."pricing_catalog_history"."canon" is 'The retired price list in _pricing_canon form (rates, activities, policy, hours, holidays, closed_days), compared for equality with a device snapshot.';

comment on column "public"."pricing_catalog_history"."canon_md5" is 'md5 of canon::text (generated). Part of the primary key; lookups match it and then compare canon itself.';

comment on column "public"."pricing_catalog_history"."retired_at" is 'When the list was last replaced (statement time); entries older than _pricing_grace() are no longer accepted.';

comment on column "public"."rate_bands"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."rate_bands"."code" is 'Band code, unique per arena; the pricer selects standard or happy. Any other code is stored but never chosen.';

comment on column "public"."rate_bands"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp). The table is not in the sync_pull feed; devices see band codes through sync_v_rates.';

comment on column "public"."rate_cards"."active" is 'Only rates on active cards are synced (sync_v_rates) and priced (_pricing_snapshot).';

comment on column "public"."rate_cards"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."rate_cards"."effective_from" is 'When the card takes effect (UTC); the newest active card is the one rate.upsert / rate.delete edit.';

comment on column "public"."rate_cards"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp). The table is not in the sync_pull feed; devices see cards only through sync_v_rates.';

comment on column "public"."rates"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."rates"."band_id" is 'Time band the price applies in (rate_bands, e.g. standard or happy). A happy-hour period with no happy rate falls back to the standard rate.';

comment on column "public"."rates"."controller_count" is 'Number of controllers the price is for (e.g. PS5 with 1-4 pads); null = the price does not depend on controllers. Matched exactly, null to null.';

comment on column "public"."rates"."price_paise" is 'Price in integer paise (1/100 rupee) per unit_minutes; >= 0.';

comment on column "public"."rates"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull (via sync_v_rates).';

comment on column "public"."rates"."unit_minutes" is 'Length in minutes of the unit that price_paise buys (> 0). For unit-model activities (e.g. VR) it is the sold unit; otherwise price is prorated per this many minutes.';

comment on column "public"."resource_activities"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."resource_activities"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."resources"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."resources"."current_mode" is 'Activity code the resource is locked to (e.g. a PS5/VR station in VR mode); null = not mode-locked. Starts for another activity are refused (_mode_ok); changed by resource.set_mode only while nothing is open on it.';

comment on column "public"."resources"."kind" is 'One of station, table, room.';

comment on column "public"."resources"."name" is 'Display name, unique within the arena (e.g. HEX, Pool Table 1).';

comment on column "public"."resources"."status" is 'One of available, maintenance, temporarily_unavailable, disabled. Set by resource.upsert / resource.set_status.';

comment on column "public"."resources"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."session_charges"."amount_paise" is 'Line amount in integer paise before bill-level cash rounding; the session total is sessions.billed_amount_paise.';

comment on column "public"."session_charges"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."session_charges"."band_code" is 'Price band: standard or happy (happy hour).';

comment on column "public"."session_charges"."billed_minutes" is 'Minutes charged after billing-unit / block rounding (or units x unit_minutes for unit-priced activities).';

comment on column "public"."session_charges"."controller_count" is 'Controller count the rate was looked up for (copied from the segment).';

comment on column "public"."session_charges"."played_minutes" is 'Whole minutes actually played inside this interval.';

comment on column "public"."session_charges"."resource_id" is 'Station of that segment.';

comment on column "public"."session_charges"."segment_end" is 'End of the billed band interval (UTC); can extend past the actual end when the minimum charge applies.';

comment on column "public"."session_charges"."segment_id" is 'Segment this line was priced from.';

comment on column "public"."session_charges"."segment_index" is '0-based ordinal of this charge line within the session''s bill (one segment can yield several lines); not session_segments.idx.';

comment on column "public"."session_charges"."segment_start" is 'Start of the billed band interval (UTC).';

comment on column "public"."session_charges"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."session_charges"."unit_minutes" is 'Length in minutes of the rate''s pricing unit that unit_price_paise buys.';

comment on column "public"."session_charges"."unit_price_paise" is 'Rate price per unit_minutes, in integer paise, from the session''s pricing_snapshot.';

comment on column "public"."session_extensions"."added_amount_paise" is 'Extra cost in integer paise: server quote at new_end_at minus quote at old_end_at on the session''s pricing_snapshot; a mismatch refuses the op.';

comment on column "public"."session_extensions"."added_minutes" is 'Minutes added, as sent by the device (> 0).';

comment on column "public"."session_extensions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."session_extensions"."created_by" is 'auth.users id of the staff member whose sync op extended the session.';

comment on column "public"."session_extensions"."new_end_at" is 'Session scheduled_end_at after this extension (UTC).';

comment on column "public"."session_extensions"."old_end_at" is 'Session scheduled_end_at before this extension (UTC); must match the server''s value or the op is refused as stale.';

comment on column "public"."session_extensions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."session_extensions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."session_segments"."activity_code" is 'Activity business code (not uuid), tied to the arena''s catalog by the composite FK; selects the rate from the session''s pricing_snapshot.';

comment on column "public"."session_segments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."session_segments"."controller_count" is 'Controllers in use on the station (1 to 4, the port capacity); selects the controller-count rate. Null when not applicable.';

comment on column "public"."session_segments"."ended_at" is 'Segment end (UTC); null = the open segment.';

comment on column "public"."session_segments"."idx" is '0-based position of the segment within its session (start = 0, each reconfigure + 1); unique per session.';

comment on column "public"."session_segments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."session_segments"."resource_id" is 'Station (resource) played on during this segment.';

comment on column "public"."session_segments"."started_at" is 'Segment start (UTC), as reported by the device.';

comment on column "public"."session_segments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."sessions"."actual_ended_at" is 'When play actually ended (UTC); null while active. Billing uses actual time.';

comment on column "public"."sessions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."sessions"."billed_amount_paise" is 'Final bill in integer paise after cash rounding; null until ended. op_session_end refuses it unless it equals the server''s own re-pricing exactly.';

comment on column "public"."sessions"."booking_id" is 'Booking checked in by this session (op_session_start sets the booking to checked_in), if any.';

comment on column "public"."sessions"."created_by" is 'auth.users id of the staff member whose sync op started the session.';

comment on column "public"."sessions"."payment_status" is 'unpaid, partial, paid or waived; recomputed from payments against billed_amount_paise by op_session_end / op_payment. waived is sticky.';

comment on column "public"."sessions"."policy_snapshot" is 'The billing policy part of pricing_snapshot (pricing_snapshot->''policy''), stored separately at start.';

comment on column "public"."sessions"."pricing_snapshot" is 'Immutable copy of the arena''s price list (rates, activities, policy, holidays) frozen at start. Must match the arena''s current catalog or one retired within 72 h (_assert_snapshot); every bill and extension is priced from it.';

comment on column "public"."sessions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."sessions"."scheduled_end_at" is 'Planned end of the countdown (UTC); moved forward by each session_extensions row.';

comment on column "public"."sessions"."started_at" is 'Device-reported start instant (UTC); the server trusts session times and validates only their order.';

comment on column "public"."sessions"."status" is 'active (running), completed (ended and billed by op_session_end) or voided (owner void; row kept).';

comment on column "public"."sessions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."sessions"."void_reason" is 'Reason given by the owner when voiding; also written to audit_log.';

comment on column "public"."settings"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."settings"."json" is 'Setting value. business_hours: {"open": {...}, "happy": {...}}, each keyed by ISO weekday "1" (Monday) to "7", value {"start": m, "end": m} in minutes after IST midnight, or null when closed / no happy hour. floor_options: {"payment_methods": [...], "start_presets": [minutes...], "warn_minutes": n}.';

comment on column "public"."settings"."key" is 'Setting name, unique per arena. Writable: business_hours, floor_options.';

comment on column "public"."settings"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."staff_invites"."email" is 'Invited address, trimmed and lower case. accept_invite requires the caller''s confirmed auth e-mail to equal it.';

comment on column "public"."staff_invites"."invited_by" is 'Who invited. accept_invite re-checks that they still hold the authority the invite needs.';

comment on column "public"."staff_invites"."token_hash" is 'SHA-256 of the one-time token sent in the invitation link. The token itself is never stored.';

comment on column "public"."staff_profiles"."active" is 'False revokes all access server-side: app_arena_ids and the permission helpers only consider active rows.';

comment on column "public"."staff_profiles"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."staff_profiles"."perms" is 'Permission codes from _known_perms(): start, bill, discount, members, stations, money, reports, settings. Holding money or reports makes the member owner level (app_is_owner).';

comment on column "public"."staff_profiles"."role" is '''owner'' or ''staff''. An owner implicitly holds every permission (app_has_perm); op_staff_update keeps an owner''s perms complete and the row active.';

comment on column "public"."staff_profiles"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."staff_profiles"."user_id" is 'The Supabase Auth login (auth.users.id) this profile belongs to.';

comment on column "public"."sync_ops"."arena_id" is 'Arena the op was pushed to.';

comment on column "public"."sync_ops"."created_at" is 'Server receipt time of the op; audit evidence independent of device clocks.';

comment on column "public"."sync_ops"."device_id" is 'Device identifier passed to sync_push, if any.';

comment on column "public"."sync_ops"."error_code" is 'Stable refusal code when rejected (the op''s raised message, e.g. stale or price_mismatch, or a mapped class such as forbidden / duplicate / invalid).';

comment on column "public"."sync_ops"."error_message" is 'Refusal detail when rejected (exception hint, else message).';

comment on column "public"."sync_ops"."kind" is 'Op kind dispatched by _sync_apply, e.g. session.start, payment.record; ? if missing.';

comment on column "public"."sync_ops"."op_id" is 'Device-generated op id (outbox key); primary key, so an op is applied at most once. Reuse under another arena raises op_id_reused.';

comment on column "public"."sync_ops"."result" is 'The op function''s jsonb result when applied; replayed verbatim on a re-push.';

comment on column "public"."sync_ops"."status" is 'applied or rejected. Retryable failures are never recorded.';

comment on column "public"."sync_ops"."user_id" is 'auth.uid() of the signed-in member who pushed the op (no FK).';

comment on column "public"."sync_tombstones"."arena_id" is 'Arena of the deleted row (no FK, so tombstones outlive the arena row).';

comment on column "public"."sync_tombstones"."deleted_at" is 'Server time of the delete.';

comment on column "public"."sync_tombstones"."id" is 'Insertion-order surrogate key (sequence sync_tombstones_id_seq); the feed orders by sync_xid, not id.';

comment on column "public"."sync_tombstones"."row_key" is 'The whole deleted row as jsonb (to_jsonb(old)); the device picks the key it stores that table''s rows under.';

comment on column "public"."sync_tombstones"."sync_xid" is 'Id of the deleting transaction; places the tombstone in the sync_pull change-feed window.';

comment on column "public"."sync_tombstones"."table_name" is 'Name of the table the row was deleted from (trigger tg_table_name).';

comment on extension "btree_gist" is 'support for indexing common datatypes in GiST';

comment on function "private"."accept_invite"(uuid, text) is 'The invited, confirmed login (auth e-mail = invited address) presents the one-time token and joins the invite''s arena with its role and permissions. Single use; refuses wrong, used, withdrawn or expired invites, the wrong account, and invites whose inviter lost the authority.';

comment on function "private"."app_arena_ids"() is 'Arena ids where the signed-in user has an active staff profile; the membership test used by RLS policies and the sync RPCs.';

comment on function "private"."app_arena_ids_with"(text[]) is 'Arena ids where the signed-in user is an active owner or holds any of the given permissions; the membership test of the RLS policies on money, customer and audit tables.';

comment on function "private"."app_has_perm"(uuid, text) is 'True when the signed-in user is an active member of the arena and is an owner or holds the given permission.';

comment on function "private"."app_is_owner"(uuid) is 'True when the signed-in user is owner level in the arena: an active profile with role owner, or holding the money or reports permission.';

comment on function "private"."arena_invites"(uuid) is 'Owner level: the arena''s open invitations (not accepted or withdrawn), newest first, without their token hashes.';

comment on function "private"."arena_pricing"(uuid) is 'Client API (owner level): the arena''s station types with station counts, active rates and business/happy hours, for the admin dashboard''s Pricing screen.';

comment on function "private"."arena_sale"(uuid, uuid) is 'Client API (owner level): one closed bill with its charge lines, extensions, payments ledger, audit history and void record, for the admin dashboard''s Sales detail.';

comment on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp
  with time zone) is 'Client API (owner level): the arena''s closed bills (sessions and groups, completed or voided) that closed in [from, to), newest first, for the admin dashboard''s Sales screen. At most 93 days.';

comment on function "private"."arena_staff"(uuid) is 'Client API (owner level): the arena''s staff with login e-mail, never-signed-in flag and 30-day bills, net takings and refunds they recorded, for the admin dashboard''s Staff screen.';

comment on function "private"."can_use_arena_topic"(text) is 'True when the topic is arena:<uuid> and the caller is an active member of that arena. Used by the realtime.messages policies (private channels).';

comment on function "private"."create_my_arena"(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

comment on function "private"."invite_member"(uuid, text, text, text, text[]) is
  'Create a one-time invitation to the arena (staff: caller holds Settings, money/reports only from owner level; owner: caller is an owner). Returns {invite_id, token, expires_at}; only the token''s SHA-256 is stored. Never reads or changes the invited address''s login.';

comment on function "private"."my_arenas"() is 'Client API: the signed-in user''s staff profiles across arenas (including inactive ones) as a jsonb array of {arena_id, arena_name, name, role, perms, active}.';

comment on function "private"."revoke_invite"(uuid, uuid) is 'Withdraw an open invitation of the arena (caller holds Settings; owner invites need an owner). Its link stops working.';

comment on function "private"."sync_fetch_entity"(uuid, jsonb) is 'Client API (sync): for each {type, id} ref, return the server''s current rows for that whole entity (session, group, controller, customer or booking) so a device can replace its copy after a refused op.';

comment on function "private"."sync_pull"(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

comment on function "private"."sync_push"(uuid, jsonb, text) is 'Client API (sync): apply a batch of device ops in order, each at most once per op_id (recorded in sync_ops), and return each op''s status: applied, rejected (with error code) or retry.';

comment on function "public"."_active_card"(uuid) is 'Returns the arena''s active rate card id, creating a card named Current when none is active.';

comment on function "public"."_activity_id"(uuid, text) is 'Resolves an activity code to its id within an arena, raising activity_missing when absent.';

comment on function "public"."_assert_known_perms"(text[]) is 'Internal: raise invalid_permission if the array contains a code outside _known_perms(); null or empty is accepted.';

comment on function "public"."_assert_same_arena"() is 'Trigger (t_same_arena): for each (column, table) pair given as trigger arguments, refuse a reference to a row of another arena with cross_arena_reference.';

comment on function "public"."_assert_settings_holder"(uuid) is 'Internal: raise last_settings_holder unless at least one active profile in the arena is an owner or holds the settings permission.';

comment on function "public"."_assert_snapshot"(uuid, jsonb) is 'Pricing: raises pricing_snapshot_mismatch unless a device snapshot equals the arena''s live or recently retired price list.';

comment on function "public"."_band_id"(uuid, text) is 'Resolves a rate band code to its id within an arena, creating the band when absent.';

comment on function "public"."_booking_free"(uuid, uuid, uuid, timestamp with time zone, timestamp
  with time zone) is 'Locks a station and raises booking_conflict if another open booking overlaps the given window.';

comment on function "public"."_create_arena_with_owner"(uuid, text, text) is
  'Internal: create an empty arena (no catalog: the owner adds station types, prices, stations, games and controllers on the dashboard) and make the given login its owner with every permission. Shared by bootstrap_owner and create_my_arena; callers validate the login first.';

comment on function "public"."_floor_options"(jsonb) is 'Validates and normalises the floor_options setting (payment methods offered, session start presets, end-of-session warning minutes); raises invalid_floor_options.';

comment on function "public"."_free_pads_at"(uuid, uuid) is 'Counts usable, unallocated controllers currently at a station.';

comment on function "public"."_game_max_players"(uuid) is 'Returns a game''s max local players, defaulting to 1.';

comment on function "public"."_game_playable"(uuid, uuid) is 'Raises not_playable unless the game is installed and playable on the station (no-op without a game).';

comment on function "public"."_group_active"(uuid, uuid) is 'Locks a group session row and raises not_found or not_active unless it is active.';

comment on function
  "public"."_group_assignable"(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer) is
  'Raises unless a group player can be placed on the station with the requested activity, game and controllers.';

comment on function "public"."_group_lock"(uuid, jsonb, uuid[]) is 'Locks all stations, then all pads, involved in a group op in a fixed order; raises retry if a borrowed pad moved meanwhile.';

comment on function "public"."_group_place"(uuid, uuid, jsonb, timestamp
  with time zone, integer, integer) is 'Validates and inserts one group assignment, borrowing and allocating its pads; returns the count of skipped pad moves.';

comment on function "public"."_inventory_tracked"(uuid) is 'True when the arena has at least one non-retired controller.';

comment on function "public"."_jsonb_uuids"(jsonb) is 'Internal: convert a jsonb array of uuid strings to uuid[] (empty array for null).';

comment on function "public"."_known_perms"() is 'The eight permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings.';

comment on function "public"."_lock_pads"(uuid, uuid[]) is 'Locks the given controller rows in id order (always after the stations).';

comment on function "public"."_lock_resources"(uuid, uuid[]) is 'Locks the given station (resource) rows in id order (always before the pads).';

comment on function "public"."_mode_ok"(uuid, uuid, text) is 'Raises mode_locked when the station is locked to a different activity mode.';

comment on function "public"."_need"(uuid, text) is 'Internal guard for op_* functions: raise forbidden (42501) unless the signed-in user holds the permission in the arena.';

comment on function
  "public"."_pad_allocate"(uuid, jsonb, text, uuid, uuid, uuid, uuid, integer, text, uuid, text,
  uuid, timestamp with time zone) is 'Validates and inserts controller allocations for a session segment or group assignment.';

comment on function "public"."_pad_borrow"(uuid, jsonb, uuid, text, timestamp
  with time zone) is 'Moves pads to a station for a session or group, recording loans and returns home; returns how many were already there.';

comment on function "public"."_pad_ids"(jsonb) is 'Extracts controller_id values from a jsonb array as uuid[].';

comment on function "public"."_pad_origins"(uuid, uuid[]) is 'Distinct current stations of the given controllers.';

comment on function "public"."_payment_status"(bigint, bigint) is 'Internal: paid / partial / unpaid from billed and paid amounts in paise; a null billed amount gives partial or unpaid.';

comment on function "public"."_pr_ceil_step"(bigint, integer) is 'Pricing: smallest multiple of step that is >= v (v unchanged when step <= 1); port of Dart ceilToStep.';

comment on function "public"."_pr_charge_key"(text, uuid, integer, text, timestamp
  with time zone,
  timestamp with time zone, bigint, bigint, integer, bigint, bigint) is 'Pricing: text key of a charge row''s money-relevant fields, used to compare device and server charge rows as multisets.';

comment on function "public"."_pr_div"(bigint, bigint) is 'Pricing: integer division n / d rounded half up; port of Dart roundDivHalfUp.';

comment on function "public"."_pr_group_bill"(uuid, timestamp
  with time zone) is 'Pricing: server-side bill of a group session (per-system sweeps or a shared controller pool); port of GroupBilling.bill.';

comment on function "public"."_pr_happy"(jsonb, date) is 'Pricing: happy-hour range of one IST day under a snapshot, null on holidays, closed days or no window; port of BusinessCalendar.happyWindow.';

comment on function "public"."_pr_ist_date"(timestamp with time zone) is 'Pricing: IST (fixed +05:30) business date of a UTC instant; port of Dart IstDate.fromUtc.';

comment on function "public"."_pr_keys"(jsonb, text, uuid, integer) is 'Pricing: _pr_charge_key of every line of a quote.';

comment on function "public"."_pr_money"(bigint, integer, text) is 'Pricing: cash-rounds a paise amount to step, up or to nearest; port of Dart applyMoneyRounding.';

comment on function "public"."_pr_policy"(jsonb) is 'Pricing: billing policy of a snapshot merged over the Dart BillingPolicy.defaults.';

comment on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
  with time zone) is 'Pricing: quotes one interval for one activity and controller count on a snapshot (lines, subtotal, cash-rounded amount); port of PricingService.quote.';

comment on function "public"."_pr_rate"(jsonb, text, text, integer) is 'Pricing: first rate in a snapshot matching activity, band and controller count exactly; port of PricingSnapshot.rateFor.';

comment on function "public"."_pr_round_step"(bigint, integer) is 'Pricing: nearest multiple of step to v, ties up (v unchanged when step <= 1); port of Dart roundToStep.';

comment on function "public"."_pr_secs"(timestamp with time zone, timestamp
  with time zone) is 'Pricing: whole seconds between two instants, truncated (Dart Duration.inSeconds).';

comment on function "public"."_pr_session_bill"(uuid, timestamp
  with time zone) is 'Pricing: server-side bill of a single session over all its segments on its frozen snapshot; port of SegmentBilling.bill.';

comment on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp
  with time zone, boolean) is 'Pricing: sweeps one station''s group assignments into constant-controller stretches and quotes each; port of GroupBilling sweepResource.';

comment on function "public"."_price_mismatch"(text, bigint, bigint) is 'Raises price_mismatch with a hint comparing the server and device amounts in paise.';

comment on function "public"."_pricing_canon"(jsonb) is 'Pricing: canonical form of a snapshot (sorted, defaults filled, card name dropped) for equality checks.';

comment on function "public"."_pricing_grace"() is 'Pricing: window (72 hours) during which a retired price list is still accepted at session or group start.';

comment on function "public"."_pricing_snapshot"(uuid) is 'Pricing: the arena''s current price list built from its catalog, in the device''s PricingSnapshot JSON shape.';

comment on function "public"."_rupees"(bigint) is 'Internal: format an amount in integer paise as a rupee string (e.g. 30000 -> ₹300.00) for user-facing error hints.';

comment on function "public"."_sales"(uuid, timestamp with time zone, timestamp
  with time zone, uuid) is 'Closed bills (completed or voided sessions and groups) of an arena as jsonb summaries with their payments ledger, by close time range or by id. Server-only body of arena_sales / arena_sale.';

comment on function "public"."_same_ids"(uuid[], uuid[]) is 'Internal: true when both uuid arrays contain the same distinct ids, ignoring order and duplicates (null is treated as empty).';

comment on function "public"."_seed_arena_catalog"(uuid) is 'Test fixture only (pgTAP): fill a test arena with the 404 Arena catalog (activities, stations, rates, billing policy, games, controllers, game compatibility). Real arenas start empty. Not idempotent.';

comment on function
  "public"."_single_supply"(uuid, uuid, text, uuid, integer, integer, uuid, integer) is
  'Raises unless the station mode and the requested controllers (pads or a count) are valid for a single session.';

comment on function "public"."_stale"(xid8, text) is 'Internal: true when a non-empty client base_version differs from the row''s current sync_xid (the row changed since the device last saw it).';

comment on function "public"."_station_free_for_single"(uuid) is 'Raises resource_busy when the station has an open session segment or group assignment.';

comment on function "public"."_station_usable"(uuid, uuid) is 'Raises resource_missing or resource_unavailable unless the station exists and is available.';

comment on function "public"."_sync_apply"(uuid, text, jsonb) is 'Internal (sync_push): dispatch one op kind to its op_* function and return its result (null for an unknown kind); archives the previous price list when a pricing op changes it.';

comment on function "public"."_sync_sources"() is 'Internal (sync_pull): list of (table name, source relation) pairs that make up the sync change feed.';

comment on function "public"."_untracked_busy"(uuid, uuid, uuid[]) is 'True when open play at the station uses controllers without any allocated pads.';

comment on function "public"."_usable_pads_at"(uuid, uuid) is 'Counts usable controllers currently at a station, whether allocated or not.';

comment on function "public"."_uses_controllers"(uuid, text) is 'True when the activity uses controllers; false when unknown.';

comment on function "public"."accept_invite"(uuid, text) is 'Client API: the invited, confirmed login presents its one-time token and joins the arena. Returns {arena_id, arena_name, role}.';

comment on function "public"."app_is_owner"(uuid) is 'True when the signed-in user is owner level in the arena: an active profile with role owner, or holding the money or reports permission.';

comment on function "public"."arena_invites"(uuid) is 'Client API (owner level): the arena''s open invitations, newest first.';

comment on function "public"."arena_pricing"(uuid) is 'Client API (owner level): the arena''s station types with station counts, active rates and business/happy hours, for the admin dashboard''s Pricing screen.';

comment on function "public"."arena_sale"(uuid, uuid) is 'Client API (owner level): one closed bill with its charge lines, extensions, payments ledger and void record, for the admin dashboard''s Sales detail.';

comment on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp
  with time zone) is 'Client API (owner level): the arena''s closed bills (sessions and groups, completed or voided) that closed in [from, to), newest first, for the admin dashboard''s Sales screen. At most 93 days.';

comment on function "public"."arena_staff"(uuid) is 'Client API (owner level): the arena''s staff with login e-mail, never-signed-in flag and 30-day bills, net takings and refunds they recorded, for the admin dashboard''s Staff screen.';

comment on function "public"."assert_controller_free_for_allocation"() is 'Trigger (controller_allocations): refuse an open allocation for a controller that already has one (controller_taken), serialised by locking the controller row.';

comment on function "public"."assert_resource_free_for_assignment"() is 'Trigger (group_assignments): refuse an open assignment on a station that has an open session segment or an open assignment of another group (resource_busy).';

comment on function "public"."assert_resource_free_for_segment"() is 'Trigger (session_segments): refuse an open segment on a station that already has an open segment or an open group assignment (resource_busy), serialised by locking the station row.';

comment on function "public"."bootstrap_owner"(text, text, text) is 'Operator-only (SQL editor): create a new arena with the default catalog and make an existing, confirmed login its owner. Returns the arena id; each call creates a new arena.';

comment on function "public"."create_my_arena"(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

comment on function "public"."invite_member"(uuid, text, text, text, text[]) is
  'Client API (Settings holder; owner invites need an owner): create a one-time invitation to the arena. Returns {invite_id, token, expires_at}.';

comment on function "public"."my_arenas"() is 'Client API: the signed-in user''s staff profiles across arenas (including inactive ones) as a jsonb array of {arena_id, arena_name, name, role, perms, active}.';

comment on function "public"."op_activity_remove"(uuid, jsonb) is 'Sync op activity.remove: deletes a never-used station type with its prices, or retires a used one so past bills keep it.';

comment on function "public"."op_activity_upsert"(uuid, jsonb) is 'Sync op activity.upsert: creates or edits a station type (activity); its code is fixed once created.';

comment on function "public"."op_arena_update"(uuid, jsonb) is 'Sync op arena.update: edits the arena''s name, area and phone (only the keys sent).';

comment on function "public"."op_booking_create"(uuid, jsonb) is 'Sync op booking.create: creates a booked reservation, refusing an overlap with another open booking on the same station.';

comment on function "public"."op_booking_set_status"(uuid, jsonb) is 'Sync op booking.set_status: cancels an open booking or marks it a no-show; a repeat of the same status is a no-op.';

comment on function "public"."op_booking_update"(uuid, jsonb) is 'Sync op booking.update: edits an open booking, refusing a stale base_version or an overlap with another booking on the station.';

comment on function "public"."op_controller_move"(uuid, jsonb) is 'Sync op controller.move: loans, returns home or permanently re-homes a pad, locking both stations before the pad.';

comment on function "public"."op_controller_set_status"(uuid, jsonb) is 'Sync op controller.set_status: sets a pad''s status and notes.';

comment on function "public"."op_controller_upsert"(uuid, jsonb) is 'Sync op controller.upsert: creates or edits a pad, refusing to relocate one that is in use.';

comment on function "public"."op_customer_create"(uuid, jsonb) is 'Sync op customer.create: registers a customer, keeping the row without its phone when that phone already belongs to someone else.';

comment on function "public"."op_customer_update"(uuid, jsonb) is 'Sync op customer.update: edits a customer, refusing a stale base_version or a phone already in use.';

comment on function "public"."op_game_delete"(uuid, jsonb) is 'Sync op game.delete: permanently deletes a game no session, group, pad allocation or booking ever used (with its station statuses and control guide); refuses one in play (game_in_play) or with history (game_has_history: archive it instead).';

comment on function "public"."op_game_replace_controls"(uuid, jsonb) is 'Sync op game.replace_controls: replaces the full list of control-guide rows for one game.';

comment on function "public"."op_game_set_active"(uuid, jsonb) is 'Sync op game.set_active: archives (false) or restores (true) a game; sessions already playing it continue and history keeps it.';

comment on function "public"."op_game_set_compat"(uuid, jsonb) is 'Sync op game.set_compat: upserts the compatibility status of a game on a station (what _game_playable checks).';

comment on function "public"."op_game_upsert"(uuid, jsonb) is 'Sync op game.upsert: creates or edits a catalog game (name trimmed and unique ignoring case); refuses an edit over a newer archive/restore (stale) and never re-creates a deleted game.';

comment on function "public"."op_group_add"(uuid, jsonb) is 'Sync op group.add: adds one player assignment to an active group after re-validating the station and pads.';

comment on function "public"."op_group_create"(uuid, jsonb) is 'Sync op group.create: starts a group session and places every player, then verifies the frozen price list and billing mode.';

comment on function "public"."op_group_end"(uuid, jsonb) is 'Sync op group.end: closes an active group, stores its charges and bill, and refuses unless the server re-prices it to exactly the same money.';

comment on function "public"."op_group_end_player"(uuid, jsonb) is 'Sync op group.end_player: ends one player''s open assignment and releases their pads.';

comment on function "public"."op_group_extend"(uuid, jsonb) is 'Sync op group.extend: moves a group''s scheduled end and verifies the extension price server-side.';

comment on function "public"."op_group_switch"(uuid, jsonb) is 'Sync op group.switch: closes a player''s open assignment and places them on a new station or game.';

comment on function "public"."op_group_void"(uuid, jsonb) is 'Sync op group.void: voids a group session (owner level only, reason required), closing open assignments and pads and auditing who, when and why.';

comment on function "public"."op_holiday_delete"(uuid, jsonb) is 'Sync op holiday.delete: removes the holiday on a given day (idempotent).';

comment on function "public"."op_holiday_upsert"(uuid, jsonb) is 'Sync op holiday.upsert: adds or edits the holiday on a given day.';

comment on function "public"."op_payment"(uuid, jsonb) is 'Sync op payment.record: records a payment or refund on a session or group, refusing overpayment of a final bill or a refund beyond what was paid.';

comment on function "public"."op_payment_correct"(uuid, jsonb) is 'Sync op payment.correct: moves all or part of a recorded payment to another method (money permission, reason required) as an append-only refund + payment pair, audited; the bill''s net never changes.';

comment on function "public"."op_policy_save"(uuid, jsonb) is 'Sync op policy.save: overwrites the arena''s active billing policy (creating a default one if missing).';

comment on function "public"."op_rate_delete"(uuid, jsonb) is 'Sync op rate.delete: deletes the active card''s rate for a band, activity and controller count (idempotent).';

comment on function "public"."op_rate_upsert"(uuid, jsonb) is 'Sync op rate.upsert: inserts or updates the active card''s rate for a band, activity and controller count.';

comment on function "public"."op_resource_set_mode"(uuid, jsonb) is 'Sync op resource.set_mode: sets or clears a station''s activity mode lock while it is idle.';

comment on function "public"."op_resource_set_status"(uuid, jsonb) is 'Sync op resource.set_status: puts a station in or out of service or removes it; refuses anything but available while a session or group player is on it (resource_busy).';

comment on function "public"."op_resource_upsert"(uuid, jsonb) is 'Sync op resource.upsert: adds or edits a station and the types it offers; an edit without a status keeps it, and a status change away from available is refused while the station is in use (resource_busy).';

comment on function "public"."op_session_void"(uuid, jsonb) is 'Sync op session.void: voids a single session (owner level only, reason required), closing open segments and pads and auditing who, when and why.';

comment on function "public"."revoke_invite"(uuid, uuid) is 'Client API (Settings holder; owner invites need an owner): withdraw an open invitation.';

comment on function "public"."set_updated_at"() is 'Trigger (before update): set updated_at to now() unless the update already set it explicitly.';

comment on function "public"."sync_fetch_entity"(uuid, jsonb) is 'Client API (sync): for each {type, id} ref, return the server''s current rows for that whole entity (session, group, controller, customer or booking) so a device can replace its copy after a refused op.';

comment on function "public"."sync_pull"(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

comment on function "public"."sync_push"(uuid, jsonb, text) is 'Client API (sync): apply a batch of device ops in order, each at most once per op_id (recorded in sync_ops), and return each op''s status: applied, rejected (with error code) or retry.';

comment on function "public"."sync_record_delete"() is 'Trigger (after delete on synced tables): write the deleted row to sync_tombstones so sync_pull can propagate the delete to devices.';

comment on function "public"."sync_stamp"() is 'Trigger (before insert or update on synced tables): set sync_xid to the current transaction id, the row''s change-feed position and version.';

comment on schema "private" is 'SECURITY DEFINER bodies of the client API and the RLS helpers; not exposed over the Data API.';

comment on table "public"."activities" is 'Activity types an arena sells (e.g. PS5, VR, POOL, LOUNGE), identified by a per-arena business code; part of the pricing snapshot.';

comment on table "public"."arenas" is 'One gaming centre (tenant). Every arena-scoped row references it via arena_id; created by bootstrap_owner() or create_my_arena().';

comment on table "public"."audit_log" is 'Append-only audit trail of voids, waives, payment-method corrections and sync-time data adjustments, per arena. Not part of the sync change feed.';

comment on table "public"."billing_policies" is 'Configurable billing rules for an arena. The oldest active row is the live policy and is captured into every session''s pricing snapshot.';

comment on table "public"."bookings" is 'A reservation of a station and activity for a future time window, checked in when its session starts.';

comment on table "public"."controller_allocations" is 'Append-only per-pad timeline: which physical controller was used by which session segment or group player, where, and when. An open row (ended_at null) means the pad is in a player''s hands.';

comment on table "public"."controller_moves" is 'Append-only history of physical pad carries between stations (loan, permanent re-home, return home).';

comment on table "public"."controllers" is 'Physical controllers (pads): label, home station, current location, condition and any outstanding loan.';

comment on table "public"."customers" is 'Customers of an arena: registered members and per-visit walk-in guest records. Referenced by sessions, groups and bookings.';

comment on table "public"."game_categories" is 'Genre categories used to group an arena''s games; names are unique per arena.';

comment on table "public"."game_controls" is 'Control-guide entries for a game: an action, the buttons that perform it and an optional explanation. Replaced wholesale per game by game.replace_controls.';

comment on table "public"."game_resources" is 'Compatibility matrix: whether a game can be played on a given resource. Only status playable allows a session on that game there.';

comment on table "public"."games" is 'Game titles in an arena''s library, with search aliases, platforms, player limits and an active flag.';

comment on table "public"."group_assignments" is 'Placement of one group player on one station, activity, game and controller count for a stretch of time; the open row is where the player is now.';

comment on table "public"."group_charges" is 'Itemised bill lines of an ended group session, verified against the server''s own re-pricing of the group.';

comment on table "public"."group_extensions" is 'Append-only record of each extension of a group session''s scheduled end, with the extra cost the server verified.';

comment on table "public"."group_payments" is 'Append-only payments and refunds against a group session; their sum is what was collected.';

comment on table "public"."group_sessions" is 'A group session: one shared countdown and one bill over several players, whose station placements are group_assignments.';

comment on table "public"."holidays" is 'Holiday and closure days per arena. Every listed day has no happy hour; closed days are also shut. Part of the pricing snapshot.';

comment on table "public"."payments" is 'Append-only payments and refunds against a single session; their sum is what was collected.';

comment on table "public"."pricing_catalog_history" is 'Price lists retired by a pricing change, kept so a device that went offline holding the old list can still start sessions within the grace window. Server-only.';

comment on table "public"."rate_bands" is 'Pricing time bands per arena, identified by code. The server pricer uses the codes standard and happy.';

comment on table "public"."rate_cards" is 'Named price lists grouping rates. Rates on active cards form the arena''s live price list; ops edit the newest active card.';

comment on table "public"."rates" is 'Prices on a rate card: for an activity, band and optional controller count, price_paise per unit_minutes. Part of the pricing snapshot.';

comment on table "public"."resource_activities" is 'Link table: the activities a resource supports. Replaced wholesale per resource by resource.upsert.';

comment on table "public"."resources" is 'Bookable places on the floor (gaming stations, pool tables, rooms). Sessions, group assignments, bookings and controllers point at them.';

comment on table "public"."session_charges" is 'Itemised bill lines of an ended single session: one row per price band piece of each segment, verified against the server''s own re-pricing.';

comment on table "public"."session_extensions" is 'Append-only record of each extension of a single session''s scheduled end, with the extra cost the server verified.';

comment on table "public"."session_segments" is 'One stretch of a single session on one station, activity, game and controller count. The open segment (ended_at null) is where the session is now; at most one open segment or group assignment per station.';

comment on table "public"."sessions" is 'A single-player session: the parent of its segments, extensions, charges and payments. Holds the frozen price list and, once ended, the bill.';

comment on table "public"."settings" is 'Per-arena key/value settings synced to devices. Writable through settings.save: business_hours and floor_options.';

comment on table "public"."staff_invites" is 'Invitations to join an arena (staff or co-owner). Membership is created only when the invited, confirmed login presents the one-time token (accept_invite). Server-only; owners list open invites via arena_invites().';

comment on table "public"."staff_profiles" is 'Membership of an auth user in an arena: display name, role and permission codes. Active rows grant read access (app_arena_ids) and op_* permissions.';

comment on table "public"."sync_ops" is 'Server-only idempotency ledger for sync_push: one row per device op id with its outcome, replayed on retry. No client grants; RLS on with no policies (deny all).';

comment on table "public"."sync_tombstones" is 'Server-only record of deleted rows from synced tables, served by sync_pull so devices delete them too. No client grants; RLS on with no policies (deny all).';

comment on view "public"."sync_v_arenas" is 'Change-feed source for arenas: the arena row plus arena_id = id so sync_pull can filter it like every other table. Server-only (read by sync_pull).';

comment on view "public"."sync_v_bookings" is 'Change-feed source for bookings: every booking column plus the activity''s business code (activity_code, null when no activity). Server-only (read by sync_pull / sync_fetch_entity).';

comment on view "public"."sync_v_rates" is 'Rates on active rate cards, with activity_code and band code. Change-feed source for rates and the rates section of the server pricing snapshot. Server-only.';

comment on view "public"."sync_v_resource_activities" is 'Change-feed source for resource_activities: each link plus the activity''s business code. Server-only (read by sync_pull).';

revoke all on function "private"."accept_invite"(uuid, text) from public;

grant execute
  on function "private"."accept_invite"(uuid, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."app_arena_ids"() from public;

grant execute on function "private"."app_arena_ids"() to "authenticated", "postgres", "service_role";

revoke all on function "private"."app_arena_ids_with"(text[]) from public;

grant execute
  on function "private"."app_arena_ids_with"(text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."app_has_perm"(uuid, text) from public;

grant execute
  on function "private"."app_has_perm"(uuid, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."app_is_owner"(uuid) from public;

grant execute
  on function "private"."app_is_owner"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_invites"(uuid) from public;

grant execute
  on function "private"."arena_invites"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_pricing"(uuid) from public;

grant execute
  on function "private"."arena_pricing"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_sale"(uuid, uuid) from public;

grant execute
  on function "private"."arena_sale"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  from public;

grant execute
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_staff"(uuid) from public;

grant execute
  on function "private"."arena_staff"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."can_use_arena_topic"(text) from public;

grant execute
  on function "private"."can_use_arena_topic"(text)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."create_my_arena"(text, text) from public;

grant execute
  on function "private"."create_my_arena"(text, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."invite_member"(uuid, text, text, text, text[]) from public;

grant execute
  on function "private"."invite_member"(uuid, text, text, text, text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."my_arenas"() from public;

grant execute on function "private"."my_arenas"() to "authenticated", "postgres", "service_role";

revoke all on function "private"."revoke_invite"(uuid, uuid) from public;

grant execute
  on function "private"."revoke_invite"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."sync_fetch_entity"(uuid, jsonb) from public;

grant execute
  on function "private"."sync_fetch_entity"(uuid, jsonb)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."sync_pull"(uuid, text, integer) from public;

grant execute
  on function "private"."sync_pull"(uuid, text, integer)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."sync_push"(uuid, jsonb, text) from public;

grant execute
  on function "private"."sync_push"(uuid, jsonb, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."_active_card"(uuid) from public;

grant execute on function "public"."_active_card"(uuid) to "postgres", "service_role";

revoke all on function "public"."_activity_id"(uuid, text) from public;

grant execute on function "public"."_activity_id"(uuid, text) to "postgres", "service_role";

revoke all on function "public"."_assert_known_perms"(text[]) from public;

grant execute on function "public"."_assert_known_perms"(text[]) to "postgres", "service_role";

revoke all on function "public"."_assert_same_arena"() from public;

grant execute on function "public"."_assert_same_arena"() to "postgres", "service_role";

revoke all on function "public"."_assert_settings_holder"(uuid) from public;

grant execute on function "public"."_assert_settings_holder"(uuid) to "postgres", "service_role";

revoke all on function "public"."_assert_snapshot"(uuid, jsonb) from public;

grant execute on function "public"."_assert_snapshot"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."_band_id"(uuid, text) from public;

grant execute on function "public"."_band_id"(uuid, text) to "postgres", "service_role";

revoke all
  on function "public"."_booking_free"(uuid, uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  from public;

grant execute
  on function "public"."_booking_free"(uuid, uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_create_arena_with_owner"(uuid, text, text) from public;

grant execute
  on function "public"."_create_arena_with_owner"(uuid, text, text)
  to "postgres", "service_role";

revoke all on function "public"."_floor_options"(jsonb) from public;

grant execute on function "public"."_floor_options"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_free_pads_at"(uuid, uuid) from public;

grant execute on function "public"."_free_pads_at"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_game_max_players"(uuid) from public;

grant execute on function "public"."_game_max_players"(uuid) to "postgres", "service_role";

revoke all on function "public"."_game_playable"(uuid, uuid) from public;

grant execute on function "public"."_game_playable"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_group_active"(uuid, uuid) from public;

grant execute on function "public"."_group_active"(uuid, uuid) to "postgres", "service_role";

revoke all
  on function
    "public"."_group_assignable"(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer)
  from public;

grant execute
  on function
    "public"."_group_assignable"(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer)
  to "postgres", "service_role";

revoke all on function "public"."_group_lock"(uuid, jsonb, uuid[]) from public;

grant execute on function "public"."_group_lock"(uuid, jsonb, uuid[]) to "postgres", "service_role";

revoke all
  on function "public"."_group_place"(uuid, uuid, jsonb, timestamp with time zone, integer, integer)
  from public;

grant execute
  on function "public"."_group_place"(uuid, uuid, jsonb, timestamp with time zone, integer, integer)
  to "postgres", "service_role";

revoke all on function "public"."_inventory_tracked"(uuid) from public;

grant execute on function "public"."_inventory_tracked"(uuid) to "postgres", "service_role";

revoke all on function "public"."_jsonb_uuids"(jsonb) from public;

grant execute on function "public"."_jsonb_uuids"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_known_perms"() from public;

grant execute on function "public"."_known_perms"() to "postgres", "service_role";

revoke all on function "public"."_lock_pads"(uuid, uuid[]) from public;

grant execute on function "public"."_lock_pads"(uuid, uuid[]) to "postgres", "service_role";

revoke all on function "public"."_lock_resources"(uuid, uuid[]) from public;

grant execute on function "public"."_lock_resources"(uuid, uuid[]) to "postgres", "service_role";

revoke all on function "public"."_mode_ok"(uuid, uuid, text) from public;

grant execute on function "public"."_mode_ok"(uuid, uuid, text) to "postgres", "service_role";

revoke all on function "public"."_need"(uuid, text) from public;

grant execute on function "public"."_need"(uuid, text) to "postgres", "service_role";

revoke all
  on function
    "public"."_pad_allocate"(uuid, jsonb, text, uuid, uuid, uuid, uuid, integer, text, uuid, text,
    uuid, timestamp with time zone)
  from public;

grant execute
  on function
    "public"."_pad_allocate"(uuid, jsonb, text, uuid, uuid, uuid, uuid, integer, text, uuid, text,
    uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_pad_borrow"(uuid, jsonb, uuid, text, timestamp with time zone)
  from public;

grant execute
  on function "public"."_pad_borrow"(uuid, jsonb, uuid, text, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pad_ids"(jsonb) from public;

grant execute on function "public"."_pad_ids"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_pad_origins"(uuid, uuid[]) from public;

grant execute on function "public"."_pad_origins"(uuid, uuid[]) to "postgres", "service_role";

revoke all on function "public"."_payment_status"(bigint, bigint) from public;

grant execute on function "public"."_payment_status"(bigint, bigint) to "postgres", "service_role";

revoke all on function "public"."_pr_ceil_step"(bigint, integer) from public;

grant execute on function "public"."_pr_ceil_step"(bigint, integer) to "postgres", "service_role";

revoke all
  on function "public"."_pr_charge_key"(text, uuid, integer, text, timestamp
    with time zone, timestamp with time zone, bigint, bigint, integer, bigint, bigint)
  from public;

grant execute
  on function "public"."_pr_charge_key"(text, uuid, integer, text, timestamp
    with time zone, timestamp with time zone, bigint, bigint, integer, bigint, bigint)
  to "postgres", "service_role";

revoke all on function "public"."_pr_div"(bigint, bigint) from public;

grant execute on function "public"."_pr_div"(bigint, bigint) to "postgres", "service_role";

revoke all on function "public"."_pr_group_bill"(uuid, timestamp with time zone) from public;

grant execute
  on function "public"."_pr_group_bill"(uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_happy"(jsonb, date) from public;

grant execute on function "public"."_pr_happy"(jsonb, date) to "postgres", "service_role";

revoke all on function "public"."_pr_ist_date"(timestamp with time zone) from public;

grant execute
  on function "public"."_pr_ist_date"(timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_keys"(jsonb, text, uuid, integer) from public;

grant execute
  on function "public"."_pr_keys"(jsonb, text, uuid, integer)
  to "postgres", "service_role";

revoke all on function "public"."_pr_money"(bigint, integer, text) from public;

grant execute on function "public"."_pr_money"(bigint, integer, text) to "postgres", "service_role";

revoke all on function "public"."_pr_policy"(jsonb) from public;

grant execute on function "public"."_pr_policy"(jsonb) to "postgres", "service_role";

revoke all
  on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
    with time zone)
  from public;

grant execute
  on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
    with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_rate"(jsonb, text, text, integer) from public;

grant execute
  on function "public"."_pr_rate"(jsonb, text, text, integer)
  to "postgres", "service_role";

revoke all on function "public"."_pr_round_step"(bigint, integer) from public;

grant execute on function "public"."_pr_round_step"(bigint, integer) to "postgres", "service_role";

revoke all
  on function "public"."_pr_secs"(timestamp with time zone, timestamp with time zone)
  from public;

grant execute
  on function "public"."_pr_secs"(timestamp with time zone, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_session_bill"(uuid, timestamp with time zone) from public;

grant execute
  on function "public"."_pr_session_bill"(uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean)
  from public;

grant execute
  on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean)
  to "postgres", "service_role";

revoke all on function "public"."_price_mismatch"(text, bigint, bigint) from public;

grant execute
  on function "public"."_price_mismatch"(text, bigint, bigint)
  to "postgres", "service_role";

revoke all on function "public"."_pricing_canon"(jsonb) from public;

grant execute on function "public"."_pricing_canon"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_pricing_grace"() from public;

grant execute on function "public"."_pricing_grace"() to "postgres", "service_role";

revoke all on function "public"."_pricing_snapshot"(uuid) from public;

grant execute on function "public"."_pricing_snapshot"(uuid) to "postgres", "service_role";

revoke all on function "public"."_rupees"(bigint) from public;

grant execute on function "public"."_rupees"(bigint) to "postgres", "service_role";

revoke all
  on function "public"."_sales"(uuid, timestamp with time zone, timestamp with time zone, uuid)
  from public;

grant execute
  on function "public"."_sales"(uuid, timestamp with time zone, timestamp with time zone, uuid)
  to "postgres", "service_role";

revoke all on function "public"."_same_ids"(uuid[], uuid[]) from public;

grant execute on function "public"."_same_ids"(uuid[], uuid[]) to "postgres", "service_role";

revoke all on function "public"."_seed_arena_catalog"(uuid) from public;

grant execute on function "public"."_seed_arena_catalog"(uuid) to "postgres", "service_role";

revoke all
  on function "public"."_single_supply"(uuid, uuid, text, uuid, integer, integer, uuid, integer)
  from public;

grant execute
  on function "public"."_single_supply"(uuid, uuid, text, uuid, integer, integer, uuid, integer)
  to "postgres", "service_role";

revoke all on function "public"."_stale"(xid8, text) from public;

grant execute on function "public"."_stale"(xid8, text) to "postgres", "service_role";

revoke all on function "public"."_station_free_for_single"(uuid) from public;

grant execute on function "public"."_station_free_for_single"(uuid) to "postgres", "service_role";

revoke all on function "public"."_station_usable"(uuid, uuid) from public;

grant execute on function "public"."_station_usable"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_sync_apply"(uuid, text, jsonb) from public;

grant execute on function "public"."_sync_apply"(uuid, text, jsonb) to "postgres", "service_role";

revoke all on function "public"."_sync_sources"() from public;

grant execute on function "public"."_sync_sources"() to "postgres", "service_role";

revoke all on function "public"."_untracked_busy"(uuid, uuid, uuid[]) from public;

grant execute
  on function "public"."_untracked_busy"(uuid, uuid, uuid[])
  to "postgres", "service_role";

revoke all on function "public"."_usable_pads_at"(uuid, uuid) from public;

grant execute on function "public"."_usable_pads_at"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_uses_controllers"(uuid, text) from public;

grant execute on function "public"."_uses_controllers"(uuid, text) to "postgres", "service_role";

revoke all on function "public"."accept_invite"(uuid, text) from public;

grant execute
  on function "public"."accept_invite"(uuid, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."app_is_owner"(uuid) from public;

grant execute
  on function "public"."app_is_owner"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_invites"(uuid) from public;

grant execute
  on function "public"."arena_invites"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_pricing"(uuid) from public;

grant execute
  on function "public"."arena_pricing"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_sale"(uuid, uuid) from public;

grant execute
  on function "public"."arena_sale"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  from public;

grant execute
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_staff"(uuid) from public;

grant execute
  on function "public"."arena_staff"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."assert_controller_free_for_allocation"() from public;

grant execute
  on function "public"."assert_controller_free_for_allocation"()
  to "postgres", "service_role";

revoke all on function "public"."assert_resource_free_for_assignment"() from public;

grant execute
  on function "public"."assert_resource_free_for_assignment"()
  to "postgres", "service_role";

revoke all on function "public"."assert_resource_free_for_segment"() from public;

grant execute
  on function "public"."assert_resource_free_for_segment"()
  to "postgres", "service_role";

revoke all on function "public"."bootstrap_owner"(text, text, text) from public;

grant execute on function "public"."bootstrap_owner"(text, text, text) to "postgres", "service_role";

revoke all on function "public"."create_my_arena"(text, text) from public;

grant execute
  on function "public"."create_my_arena"(text, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."invite_member"(uuid, text, text, text, text[]) from public;

grant execute
  on function "public"."invite_member"(uuid, text, text, text, text[])
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."my_arenas"() from public;

grant execute on function "public"."my_arenas"() to "authenticated", "postgres", "service_role";

revoke all on function "public"."op_activity_remove"(uuid, jsonb) from public;

grant execute on function "public"."op_activity_remove"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_activity_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_activity_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_arena_update"(uuid, jsonb) from public;

grant execute on function "public"."op_arena_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_booking_create"(uuid, jsonb) from public;

grant execute on function "public"."op_booking_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_booking_set_status"(uuid, jsonb) from public;

grant execute
  on function "public"."op_booking_set_status"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_booking_update"(uuid, jsonb) from public;

grant execute on function "public"."op_booking_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_controller_move"(uuid, jsonb) from public;

grant execute on function "public"."op_controller_move"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_controller_set_status"(uuid, jsonb) from public;

grant execute
  on function "public"."op_controller_set_status"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_controller_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_controller_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_customer_create"(uuid, jsonb) from public;

grant execute on function "public"."op_customer_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_customer_update"(uuid, jsonb) from public;

grant execute on function "public"."op_customer_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_delete"(uuid, jsonb) from public;

grant execute on function "public"."op_game_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_replace_controls"(uuid, jsonb) from public;

grant execute
  on function "public"."op_game_replace_controls"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_game_set_active"(uuid, jsonb) from public;

grant execute on function "public"."op_game_set_active"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_set_compat"(uuid, jsonb) from public;

grant execute on function "public"."op_game_set_compat"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_game_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_add"(uuid, jsonb) from public;

grant execute on function "public"."op_group_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_create"(uuid, jsonb) from public;

grant execute on function "public"."op_group_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_end"(uuid, jsonb) from public;

grant execute on function "public"."op_group_end"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_end_player"(uuid, jsonb) from public;

grant execute on function "public"."op_group_end_player"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_extend"(uuid, jsonb) from public;

grant execute on function "public"."op_group_extend"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_switch"(uuid, jsonb) from public;

grant execute on function "public"."op_group_switch"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_void"(uuid, jsonb) from public;

grant execute on function "public"."op_group_void"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_holiday_delete"(uuid, jsonb) from public;

grant execute on function "public"."op_holiday_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_holiday_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_holiday_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_payment"(uuid, jsonb) from public;

grant execute on function "public"."op_payment"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_payment_correct"(uuid, jsonb) from public;

grant execute on function "public"."op_payment_correct"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_policy_save"(uuid, jsonb) from public;

grant execute on function "public"."op_policy_save"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rate_delete"(uuid, jsonb) from public;

grant execute on function "public"."op_rate_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rate_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_rate_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_resource_set_mode"(uuid, jsonb) from public;

grant execute on function "public"."op_resource_set_mode"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_resource_set_status"(uuid, jsonb) from public;

grant execute
  on function "public"."op_resource_set_status"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_resource_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_resource_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_end"(uuid, jsonb) from public;

grant execute on function "public"."op_session_end"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_extend"(uuid, jsonb) from public;

grant execute on function "public"."op_session_extend"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_reconfigure"(uuid, jsonb) from public;

grant execute
  on function "public"."op_session_reconfigure"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_session_start"(uuid, jsonb) from public;

grant execute on function "public"."op_session_start"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_void"(uuid, jsonb) from public;

grant execute on function "public"."op_session_void"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_settings_save"(uuid, jsonb) from public;

grant execute on function "public"."op_settings_save"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_staff_update"(uuid, jsonb) from public;

grant execute on function "public"."op_staff_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."revoke_invite"(uuid, uuid) from public;

grant execute
  on function "public"."revoke_invite"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."set_updated_at"() from public;

grant execute on function "public"."set_updated_at"() to "postgres", "service_role";

revoke all on function "public"."sync_fetch_entity"(uuid, jsonb) from public;

grant execute
  on function "public"."sync_fetch_entity"(uuid, jsonb)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."sync_pull"(uuid, text, integer) from public;

grant execute
  on function "public"."sync_pull"(uuid, text, integer)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."sync_push"(uuid, jsonb, text) from public;

grant execute
  on function "public"."sync_push"(uuid, jsonb, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."sync_record_delete"() from public;

grant execute on function "public"."sync_record_delete"() to "postgres", "service_role";

revoke all on function "public"."sync_stamp"() from public;

grant execute on function "public"."sync_stamp"() to "postgres", "service_role";

grant usage on schema "private" to "authenticated";

grant create, usage on schema "private" to "postgres";

grant usage on schema "private" to "service_role";

grant select, update, usage
  on sequence "public"."sync_tombstones_id_seq"
  to "postgres", "service_role";

grant select on table "public"."activities" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."activities"
  to "postgres", "service_role";

grant select on table "public"."arenas" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."arenas"
  to "postgres", "service_role";

grant select on table "public"."audit_log" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."audit_log"
  to "postgres", "service_role";

grant select on table "public"."billing_policies" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."billing_policies"
  to "postgres", "service_role";

grant select on table "public"."bookings" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."bookings"
  to "postgres", "service_role";

grant select on table "public"."controller_allocations" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."controller_allocations"
  to "postgres", "service_role";

grant select on table "public"."controller_moves" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."controller_moves"
  to "postgres", "service_role";

grant select on table "public"."controllers" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."controllers"
  to "postgres", "service_role";

grant select on table "public"."customers" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."customers"
  to "postgres", "service_role";

grant select on table "public"."game_categories" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."game_categories"
  to "postgres", "service_role";

grant select on table "public"."game_controls" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."game_controls"
  to "postgres", "service_role";

grant select on table "public"."game_resources" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."game_resources"
  to "postgres", "service_role";

grant select on table "public"."games" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."games"
  to "postgres", "service_role";

grant select on table "public"."group_assignments" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_assignments"
  to "postgres", "service_role";

grant select on table "public"."group_charges" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_charges"
  to "postgres", "service_role";

grant select on table "public"."group_extensions" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_extensions"
  to "postgres", "service_role";

grant select on table "public"."group_payments" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_payments"
  to "postgres", "service_role";

grant select on table "public"."group_sessions" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_sessions"
  to "postgres", "service_role";

grant select on table "public"."holidays" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."holidays"
  to "postgres", "service_role";

grant select on table "public"."payments" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."payments"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."pricing_catalog_history"
  to "postgres", "service_role";

grant select on table "public"."rate_bands" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rate_bands"
  to "postgres", "service_role";

grant select on table "public"."rate_cards" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rate_cards"
  to "postgres", "service_role";

grant select on table "public"."rates" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."rates"
  to "postgres", "service_role";

grant select on table "public"."resource_activities" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."resource_activities"
  to "postgres", "service_role";

grant select on table "public"."resources" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."resources"
  to "postgres", "service_role";

grant select on table "public"."session_charges" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."session_charges"
  to "postgres", "service_role";

grant select on table "public"."session_extensions" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."session_extensions"
  to "postgres", "service_role";

grant select on table "public"."session_segments" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."session_segments"
  to "postgres", "service_role";

grant select on table "public"."sessions" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sessions"
  to "postgres", "service_role";

grant select on table "public"."settings" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."settings"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_invites"
  to "postgres", "service_role";

grant select on table "public"."staff_profiles" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_profiles"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_ops"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_tombstones"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_arenas"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_bookings"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_rates"
  to "postgres", "service_role";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_resource_activities"
  to "postgres", "service_role";

alter default privileges for role "postgres" in schema "private" revoke all on FUNCTIONS from public;

alter default privileges for role "postgres" in schema "private" grant execute
  on FUNCTIONS to "service_role";
