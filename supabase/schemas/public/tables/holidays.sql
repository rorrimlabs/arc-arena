-- holidays — special calendar days: no happy hour, optionally closed
--
-- One row per Asia/Kolkata calendar day. On any listed day the happy-hour band is
-- off (_pr_happy); closed = true also marks the arena shut that day. Written by
-- op_holiday_upsert / op_holiday_delete (holiday.upsert / holiday.delete). Part
-- of the pricing snapshot, so a change retires the previous price list into
-- pricing_catalog_history.
create table "public"."holidays" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "day"        date                     not null,
  "name"       text                     not null,
  "closed"     boolean                  not null default false,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  -- One entry per day; holiday.upsert / holiday.delete address rows by day.
  constraint "holidays_arena_id_day_key" unique (arena_id, day),
  constraint "holidays_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "holidays_pkey" primary key (id)
);

comment on table public.holidays is 'Holiday and closure days per arena. Every listed day has no happy hour; closed days are also shut. Part of the pricing snapshot.';

comment on column public.holidays.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.holidays.day is 'Business calendar day in Asia/Kolkata (IST); unique per arena.';

comment on column public.holidays.closed is 'True when the arena is closed that day (listed in the snapshot''s closed_days); false = open, but without happy hour.';

comment on column public.holidays.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."holidays"
  enable row level security;

create index ix_holidays_sync on public.holidays using btree (arena_id, sync_xid);

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

create policy "p_sel_holidays" on "public"."holidays"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."holidays"
  to "postgres", "service_role";

revoke all on table "public"."holidays" from "anon";

revoke all on table "public"."holidays" from "authenticated";

grant select on table "public"."holidays" to "authenticated";