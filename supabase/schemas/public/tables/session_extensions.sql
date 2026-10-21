-- session_extensions — append-only history of extending a single session's countdown
--
-- One row per extension, written by op_session_extend together with the move of
-- sessions.scheduled_end_at. The op refuses a stale extend (old_end_at must equal
-- the session's current scheduled end) and prices added_amount_paise itself
-- (0013): quote at new end minus quote at old end on the frozen price list.
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
  constraint "session_extensions_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "session_extensions_check" check ((new_end_at > old_end_at)),
  constraint "session_extensions_created_by_fkey" foreign key (created_by)
    references auth.users(id),
  constraint "session_extensions_pkey" primary key (id),
  constraint "session_extensions_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade
);

comment on table public.session_extensions is 'Append-only record of each extension of a single session''s scheduled end, with the extra cost the server verified.';

comment on column public.session_extensions.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.session_extensions.added_minutes is 'Minutes added, as sent by the device (> 0).';

comment on column public.session_extensions.old_end_at is 'Session scheduled_end_at before this extension (UTC); must match the server''s value or the op is refused as stale.';

comment on column public.session_extensions.new_end_at is 'Session scheduled_end_at after this extension (UTC).';

comment on column public.session_extensions.added_amount_paise is 'Extra cost in integer paise: server quote at new_end_at minus quote at old_end_at on the session''s pricing_snapshot; a mismatch refuses the op.';

comment on column public.session_extensions.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.session_extensions.created_by is 'auth.users id of the staff member whose sync op extended the session.';

comment on column public.session_extensions.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."session_extensions"
  enable row level security;

create index ix_extensions_session on public.session_extensions using btree (session_id, created_at);

create index ix_session_extensions_sync on public.session_extensions
  using btree (arena_id, sync_xid);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_extensions_request on public.session_extensions
  using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_session_extensions_created_by on public.session_extensions using btree (created_by);

-- Referenced session must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.session_extensions
  for each row
  execute function public._assert_same_arena('session_id', 'sessions');

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_session_extensions_sync
  before insert or update on public.session_extensions
  for each row
  execute function public.sync_stamp();

create trigger t_session_extensions_tomb
  after delete on public.session_extensions
  for each row
  execute function public.sync_record_delete();

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_session_extensions" on "public"."session_extensions"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."session_extensions"
  to "postgres", "service_role";

revoke all on table "public"."session_extensions" from "anon";

revoke all on table "public"."session_extensions" from "authenticated";

grant select on table "public"."session_extensions" to "authenticated";