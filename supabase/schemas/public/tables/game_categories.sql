-- game_categories — genre groupings for the game library (Football, Racing …)
--
-- Purely presentational grouping of games, ordered by sort_order. Seeded by
-- _seed_arena_catalog; no op_* writes this table. games.category_id points here
-- and is set to null if a category is deleted.
create table "public"."game_categories" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "name"       text                     not null,
  "sort_order" integer                  not null default 0,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "sync_xid"   xid8                     not null default pg_current_xact_id(),
  constraint "game_categories_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "game_categories_arena_id_name_key" unique (arena_id, name),
  constraint "game_categories_pkey" primary key (id)
);

comment on table public.game_categories is 'Genre categories used to group an arena''s games; names are unique per arena.';

comment on column public.game_categories.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.game_categories.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."game_categories"
  enable row level security;

create index ix_game_categories_sync on public.game_categories using btree (arena_id, sync_xid);

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

create policy "p_sel_game_categories" on "public"."game_categories"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."game_categories"
  to "postgres", "service_role";

revoke all on table "public"."game_categories" from "anon";

revoke all on table "public"."game_categories" from "authenticated";

grant select on table "public"."game_categories" to "authenticated";