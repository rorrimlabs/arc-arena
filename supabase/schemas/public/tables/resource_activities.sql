-- resource_activities — which activities each resource offers (many-to-many link)
--
-- One row per (resource, activity) pair, e.g. RIFT offers PS5 and VR. Written by
-- op_resource_upsert (resource.upsert), which makes the links match the listed
-- activity codes exactly (deletes the rest, inserts the missing ones); seeded by
-- _seed_arena_catalog. Both ends must belong to the row's arena (t_same_arena).
-- Synced through sync_v_resource_activities, which adds the activity code.
create table "public"."resource_activities" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "resource_id" uuid                     not null,
  "activity_id" uuid                     not null,
  "created_at"  timestamp with time zone not null default now(),
  "updated_at"  timestamp with time zone not null default now(),
  "sync_xid"    xid8                     not null default pg_current_xact_id(),
  constraint "resource_activities_activity_id_fkey" foreign key (activity_id)
    references public.activities(id) on delete cascade,
  constraint "resource_activities_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "resource_activities_pkey" primary key (id),
  -- A resource lists an activity at most once (resource.upsert relies on it for
  -- on conflict do nothing).
  constraint "resource_activities_resource_id_activity_id_key" unique (resource_id, activity_id),
  constraint "resource_activities_resource_id_fkey" foreign key (resource_id)
    references public.resources(id) on delete cascade
);

comment on table public.resource_activities is 'Link table: the activities a resource supports. Replaced wholesale per resource by resource.upsert.';

comment on column public.resource_activities.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.resource_activities.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."resource_activities"
  enable row level security;

create index ix_resource_activities_sync on public.resource_activities
  using btree (arena_id, sync_xid);

-- Foreign-key index (joins and cascading deletes).
create index ix_resource_activities_activity_id on public.resource_activities using btree (activity_id);

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

-- The activity and the resource must belong to the row's arena
-- (raises cross_arena_reference).
create trigger t_same_arena
  before insert or update on public.resource_activities
  for each row
  execute function
    public._assert_same_arena('activity_id', 'activities', 'resource_id', 'resources');

create policy "p_sel_resource_activities" on "public"."resource_activities"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."resource_activities"
  to "postgres", "service_role";

revoke all on table "public"."resource_activities" from "anon";

revoke all on table "public"."resource_activities" from "authenticated";

grant select on table "public"."resource_activities" to "authenticated";