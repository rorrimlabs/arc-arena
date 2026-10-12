-- activities — what can be played (PS5, VR, Pool, Lounge …) and how it is billed
--
-- The catalog of activity types per arena, keyed for the app by a stable business
-- code: segments, assignments, rates and the pricing snapshot reference activities
-- by code, not uuid. Seeded by _seed_arena_catalog; no op_* writes this table.
-- Its billing flags (duration_model, happy_hour_eligible) are part of the
-- pricing snapshot, so they must match the device's for a session to start.
-- resource_activities says which resources offer which activity.
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
  -- The business code is how every other table and the pricing snapshot refer
  -- to an activity, so it must be unique per arena.
  constraint "activities_arena_id_code_key" unique (arena_id, code),
  constraint "activities_duration_model_check"
    check ((duration_model = ANY (ARRAY['hourly'::text, 'unit'::text, 'flat_hourly'::text]))),
  constraint "activities_pkey" primary key (id),
  constraint "activities_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade
);

comment on table public.activities is 'Activity types an arena sells (e.g. PS5, VR, POOL, LOUNGE), identified by a per-arena business code; part of the pricing snapshot.';

comment on column public.activities.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.activities.code is 'Stable business code, unique per arena (e.g. PS5). Segments, assignments, rates and pricing snapshots reference activities by this code.';

comment on column public.activities.uses_controllers is 'True when sessions of this activity hold physical controllers (pads), so controller counts, allocations and borrowing apply.';

comment on column public.activities.uses_games is 'True when a game is picked for sessions of this activity (app flag; not checked server-side).';

comment on column public.activities.duration_model is 'How time is billed: hourly (by time, per billing_policies.billing_unit), unit (whole units of rates.unit_minutes, per billing_policies.vr_unit_rounding) or flat_hourly (priced like hourly by the server pricer).';

comment on column public.activities.happy_hour_eligible is 'When false the happy-hour band never applies; the whole session is priced at the standard band.';

comment on column public.activities.active is 'App-side flag for retiring an activity without deleting it. Not consulted server-side: the pricing snapshot includes inactive activities.';

comment on column public.activities.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."activities"
  enable row level security;

create index ix_activities_sync on public.activities using btree (arena_id, sync_xid);

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

create policy "p_sel_activities" on "public"."activities"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."activities"
  to "postgres", "service_role";

revoke all on table "public"."activities" from "anon";

revoke all on table "public"."activities" from "authenticated";

grant select on table "public"."activities" to "authenticated";