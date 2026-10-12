-- bookings — a reservation of a station / activity for a future time window
--
-- Created by op_booking_create and edited by op_booking_update (only while
-- booked; stale edits refused by comparing sync_xid); op_booking_set_status marks
-- cancelled / no_show; op_session_start with booking_id moves it to checked_in.
-- Two booked reservations may not overlap on the same station (_booking_free,
-- under a station row lock; raises booking_conflict). Synced to devices through
-- view sync_v_bookings, which adds the activity code.
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
  constraint "bookings_activity_id_fkey" foreign key (activity_id) references public.activities(id)
    on delete set null,
  constraint "bookings_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "bookings_check" check ((scheduled_end > scheduled_start)),
  constraint "bookings_pkey" primary key (id),
  constraint "bookings_reminder_status_check"
    check
    ((reminder_status = ANY (ARRAY['scheduled'::text, 'off'::text, 'missed'::text, 'done'::text]))),
  constraint "bookings_status_check"
    check
    ((status = ANY (ARRAY['booked'::text, 'checked_in'::text, 'cancelled'::text,
    'no_show'::text]))),
  constraint "bookings_customer_id_fkey" foreign key (customer_id) references public.customers(id)
    on delete set null,
  constraint "bookings_game_id_fkey" foreign key (game_id) references public.games(id) on delete
    set null,
  constraint "bookings_resource_id_fkey" foreign key (resource_id) references public.resources(id)
    on delete set null
);

comment on table public.bookings is 'A reservation of a station and activity for a future time window, checked in when its session starts.';

comment on column public.bookings.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.bookings.customer_id is 'Registered customer, if any; a walk-in reservation may use party_name / phone instead.';

comment on column public.bookings.resource_id is 'Reserved station; null = no specific station (no overlap check).';

comment on column public.bookings.activity_id is 'Reserved activity (uuid; ops resolve it from the activity code the device sends).';

comment on column public.bookings.scheduled_start is 'Reserved window start (UTC).';

comment on column public.bookings.scheduled_end is 'Reserved window end (UTC); after scheduled_start.';

comment on column public.bookings.status is 'booked (open; editable), checked_in (a session started from it), cancelled or no_show.';

comment on column public.bookings.players_required is 'Number of players expected, if stated.';

comment on column public.bookings.controller_requirement is 'Number of controllers requested, if stated.';

comment on column public.bookings.party_name is 'Name for a walk-in reservation with no customer record yet.';

comment on column public.bookings.phone is 'Contact phone for the reservation.';

comment on column public.bookings.reminder_status is 'Device reminder state: scheduled, off (silenced), missed (lead time already passed when booked) or done (nothing pending). Set from the device at create; no op changes it afterwards.';

comment on column public.bookings.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor and the base_version for stale-edit checks.';

alter table "public"."bookings"
  enable row level security;

create index ix_bookings_resource on public.bookings using btree (resource_id, scheduled_start);

create index ix_bookings_sync on public.bookings using btree (arena_id, sync_xid);

-- Foreign-key index (joins and cascading deletes).
create index ix_bookings_activity_id on public.bookings using btree (activity_id);

create index ix_bookings_customer_id on public.bookings using btree (customer_id);

create index ix_bookings_game_id on public.bookings using btree (game_id);

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
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

-- Referenced customer, game, station and activity must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.bookings
  for each row
  execute function
    public._assert_same_arena('customer_id', 'customers', 'game_id', 'games', 'resource_id',
    'resources', 'activity_id', 'activities');

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_bookings" on "public"."bookings"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."bookings"
  to "postgres", "service_role";

revoke all on table "public"."bookings" from "anon";

revoke all on table "public"."bookings" from "authenticated";

grant select on table "public"."bookings" to "authenticated";