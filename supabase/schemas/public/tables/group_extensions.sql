-- group_extensions — append-only history of extending a group's shared countdown
--
-- One row per extension, written by op_group_extend together with the move of
-- group_sessions.scheduled_end_at. The op refuses a stale extend (old_end_at must
-- equal the group's current scheduled end) and verifies added_amount_paise as the
-- group subtotal at the new end minus that at the old end (_pr_group_bill, 0013).
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
  constraint "group_extensions_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "group_extensions_check" check ((new_end_at > old_end_at)),
  constraint "group_extensions_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "group_extensions_pkey" primary key (id),
  constraint "group_extensions_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade
);

comment on table public.group_extensions is 'Append-only record of each extension of a group session''s scheduled end, with the extra cost the server verified.';

comment on column public.group_extensions.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.group_extensions.added_minutes is 'Minutes added, as sent by the device (> 0).';

comment on column public.group_extensions.old_end_at is 'Group scheduled_end_at before this extension (UTC); must match the server''s value or the op is refused as stale.';

comment on column public.group_extensions.new_end_at is 'Group scheduled_end_at after this extension (UTC).';

comment on column public.group_extensions.added_amount_paise is 'Extra cost in integer paise: server group subtotal at new_end_at minus subtotal at old_end_at; a mismatch refuses the op.';

comment on column public.group_extensions.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.group_extensions.created_by is 'auth.users id of the staff member whose sync op extended the group.';

comment on column public.group_extensions.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."group_extensions"
  enable row level security;

create index ix_group_extensions_sync on public.group_extensions using btree (arena_id, sync_xid);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_group_extensions_request on public.group_extensions
  using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_group_extensions_created_by on public.group_extensions using btree (created_by);

create index ix_group_extensions_group_id on public.group_extensions using btree (group_id);

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_group_extensions_sync
  before insert or update on public.group_extensions
  for each row
  execute function public.sync_stamp();

create trigger t_group_extensions_tomb
  after delete on public.group_extensions
  for each row
  execute function public.sync_record_delete();

-- Referenced group must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.group_extensions
  for each row
  execute function public._assert_same_arena('group_id', 'group_sessions');

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_group_extensions" on "public"."group_extensions"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_extensions"
  to "postgres", "service_role";

revoke all on table "public"."group_extensions" from "anon";

revoke all on table "public"."group_extensions" from "authenticated";

grant select on table "public"."group_extensions" to "authenticated";