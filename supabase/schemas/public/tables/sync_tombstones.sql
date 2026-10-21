-- sync_tombstones — server-only change-feed entries for deleted rows
--
-- One row per deleted row of a synced table, inserted by the AFTER DELETE
-- trigger function sync_record_delete (SECURITY DEFINER) on every synced table.
-- sync_pull returns them as _tombstone changes in the same sync_xid window as
-- live rows, so devices drop the row too; a live row for the same key in that
-- page outranks the tombstone on the device. Server-only: no client grants, and
-- RLS is on with no policies (deny all); devices see tombstones only via sync_pull.
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

comment on table public.sync_tombstones is 'Server-only record of deleted rows from synced tables, served by sync_pull so devices delete them too. No client grants; RLS on with no policies (deny all).';

comment on column public.sync_tombstones.id is 'Insertion-order surrogate key (sequence sync_tombstones_id_seq); the feed orders by sync_xid, not id.';

comment on column public.sync_tombstones.arena_id is 'Arena of the deleted row (no FK, so tombstones outlive the arena row).';

comment on column public.sync_tombstones.table_name is 'Name of the table the row was deleted from (trigger tg_table_name).';

comment on column public.sync_tombstones.row_key is 'The whole deleted row as jsonb (to_jsonb(old)); the device picks the key it stores that table''s rows under.';

comment on column public.sync_tombstones.sync_xid is 'Id of the deleting transaction; places the tombstone in the sync_pull change-feed window.';

comment on column public.sync_tombstones.deleted_at is 'Server time of the delete.';

-- RLS on with no policies: deny all to client roles (defence in depth beside the revokes).
alter table "public"."sync_tombstones"
  enable row level security;

alter sequence "public"."sync_tombstones_id_seq" owned by "public"."sync_tombstones"."id";

create index ix_tombstones_sync on public.sync_tombstones using btree (arena_id, sync_xid);

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_tombstones"
  to "postgres", "service_role";

revoke all on table "public".sync_tombstones from anon;

revoke all on table "public".sync_tombstones from authenticated;
