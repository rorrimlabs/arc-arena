-- accessory_kinds — what sort of thing an accessory is (Controller, VR headset, Steering wheel …)
--
-- Owner-defined per arena; nothing is seeded. An accessory (a controllers row)
-- points at one through kind_id. counts_as_controller says whether accessories
-- of the kind are game pads: only those are allocated to players, counted for
-- controller-count pricing and borrowed by session starts. An accessory with no
-- kind is a pad (rows from before kinds existed). Written by
-- op_accessory_kind_upsert / op_accessory_kind_remove (settings).
create table "public"."accessory_kinds" (
  "id"                   uuid                     not null default gen_random_uuid(),
  "arena_id"             uuid                     not null,
  "name"                 text                     not null,
  "counts_as_controller" boolean                  not null default false,
  "sort_order"           integer                  not null default 0,
  "active"               boolean                  not null default true,
  "created_at"           timestamp with time zone not null default now(),
  "updated_at"           timestamp with time zone not null default now(),
  "sync_xid"             xid8                     not null default pg_current_xact_id(),
  constraint "accessory_kinds_pkey" primary key (id),
  constraint "accessory_kinds_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "accessory_kinds_name_check" check ((char_length(name) >= 1 and char_length(name) <= 40))
);

comment on table public.accessory_kinds is 'Owner-defined kinds of station accessory (Controller, VR headset, Steering wheel …); counts_as_controller marks game pads.';

comment on column public.accessory_kinds.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.accessory_kinds.name is 'Display name, 1–40 characters, unique per arena ignoring case.';

comment on column public.accessory_kinds.counts_as_controller is 'True when accessories of this kind are game pads: allocated to players, counted for controller-count pricing and borrowed by session starts. Other kinds are only tracked physically.';

comment on column public.accessory_kinds.active is 'False once retired (a kind some accessory still uses is retired, not deleted).';

comment on column public.accessory_kinds.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."accessory_kinds"
  enable row level security;

-- Names are unique per arena ignoring case and surrounding spaces.
create unique index ux_accessory_kinds_name on public.accessory_kinds
  using btree (arena_id, lower(name));

create index ix_accessory_kinds_sync on public.accessory_kinds using btree (arena_id, sync_xid);

create trigger t_accessory_kinds_sync
  before insert or update on public.accessory_kinds
  for each row
  execute function public.sync_stamp();

create trigger t_accessory_kinds_tomb
  after delete on public.accessory_kinds
  for each row
  execute function public.sync_record_delete();

create trigger t_accessory_kinds_updated
  before update on public.accessory_kinds
  for each row
  execute function public.set_updated_at();

create policy "p_sel_accessory_kinds" on "public"."accessory_kinds"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."accessory_kinds"
  to "postgres", "service_role";

revoke all on table "public"."accessory_kinds" from "anon";

revoke all on table "public"."accessory_kinds" from "authenticated";

grant select on table "public"."accessory_kinds" to "authenticated";
