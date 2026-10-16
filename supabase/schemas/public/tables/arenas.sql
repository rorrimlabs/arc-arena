-- arenas — one gaming centre (the tenant)
--
-- Every other table hangs off an arena via arena_id (on delete cascade). Created
-- only through _create_arena_with_owner: by bootstrap_owner() (operator, SQL
-- editor) or create_my_arena() (app sign-up, one per login). Both also seed the
-- starter catalog (_seed_arena_catalog) and the first owner's staff_profiles
-- row. Members read their arena through RLS. op_arena_update (arena.update) edits name, area and
-- phone.
-- Synced to devices through the sync_v_arenas view (adds arena_id = id).
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

comment on table public.arenas is 'One gaming centre (tenant). Every arena-scoped row references it via arena_id; created by bootstrap_owner() or create_my_arena().';

comment on column public.arenas.area is 'Locality shown with the arena name (e.g. Koramangala); null when not set. Written by arena.update.';

comment on column public.arenas.phone is 'Arena contact number, 6–20 of digits, spaces, +, ( ) and -; null when not set. Written by arena.update.';

comment on column public.arenas.timezone is 'IANA time zone name of the centre. Informational: server pricing uses a fixed Asia/Kolkata +05:30 offset and does not read this column.';

comment on column public.arenas.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."arenas"
  enable row level security;

-- Global (not arena-prefixed) because the arena is the row itself.
create index ix_arenas_sync on public.arenas using btree (sync_xid);

create trigger t_arenas_sync
  before insert or update on public.arenas
  for each row
  execute function public.sync_stamp();

create trigger t_arenas_updated
  before update on public.arenas
  for each row
  execute function public.set_updated_at();

-- Keyed by id (an arena has no arena_id column): visible to its active members.
create policy "p_sel_arenas" on "public"."arenas"
  for select
  to authenticated
  using ((id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."arenas"
  to "postgres", "service_role";

revoke all on table "public"."arenas" from "anon";

revoke all on table "public"."arenas" from "authenticated";

grant select on table "public"."arenas" to "authenticated";