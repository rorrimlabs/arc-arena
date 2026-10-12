-- sessions — one single-player session (parent row of its segments)
--
-- A customer playing on the floor from start to end. Where they play (station,
-- game, controllers) lives in session_segments; the open segment is where they
-- are now. Written by op_session_start (insert; may check in a booking),
-- op_session_extend (scheduled_end_at), op_session_end (completed + billed),
-- op_session_void (owner-only) and op_payment (payment_status). pricing_snapshot
-- is frozen at start; the server re-prices every bill against it (0013).
-- Never hard-deleted: a void keeps the row and flips status.
create table "public"."sessions" (
  "id"                  uuid                     not null default gen_random_uuid(),
  "arena_id"            uuid                     not null,
  "booking_id"          uuid,
  "customer_id"         uuid                     not null,
  "status"              text                     not null default 'active'::text,
  "payment_status"      text                     not null default 'unpaid'::text,
  "started_at"          timestamp with time zone not null,
  "scheduled_end_at"    timestamp with time zone not null,
  "actual_ended_at"     timestamp with time zone,
  "pricing_snapshot"    jsonb                    not null,
  "policy_snapshot"     jsonb                    not null,
  "billed_amount_paise" bigint,
  "void_reason"         text,
  "request_id"          text,
  "created_at"          timestamp with time zone not null default now(),
  "updated_at"          timestamp with time zone not null default now(),
  "created_by"          uuid,
  "sync_xid"            xid8                     not null default pg_current_xact_id(),
  constraint "sessions_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "sessions_booking_id_fkey" foreign key (booking_id) references public.bookings(id)
    on delete set null,
  constraint "sessions_check1"
    check (((actual_ended_at IS NULL) OR (actual_ended_at >= started_at))),
  constraint "sessions_check" check ((scheduled_end_at > started_at)),
  constraint "sessions_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "sessions_customer_id_fkey" foreign key (customer_id) references public.customers(id),
  constraint "sessions_payment_status_check"
    check
    ((payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text, 'paid'::text, 'waived'::text]))),
  constraint "sessions_pkey" primary key (id),
  constraint "sessions_status_check"
    check ((status = ANY (ARRAY['active'::text, 'completed'::text, 'voided'::text])))
);

comment on table public.sessions is 'A single-player session: the parent of its segments, extensions, charges and payments. Holds the frozen price list and, once ended, the bill.';

comment on column public.sessions.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.sessions.booking_id is 'Booking checked in by this session (op_session_start sets the booking to checked_in), if any.';

comment on column public.sessions.status is 'active (running), completed (ended and billed by op_session_end) or voided (owner void; row kept).';

comment on column public.sessions.payment_status is 'unpaid, partial, paid or waived; recomputed from payments against billed_amount_paise by op_session_end / op_payment. waived is sticky.';

comment on column public.sessions.started_at is 'Device-reported start instant (UTC); the server trusts session times and validates only their order.';

comment on column public.sessions.scheduled_end_at is 'Planned end of the countdown (UTC); moved forward by each session_extensions row.';

comment on column public.sessions.actual_ended_at is 'When play actually ended (UTC); null while active. Billing uses actual time.';

comment on column public.sessions.pricing_snapshot is 'Immutable copy of the arena''s price list (rates, activities, policy, holidays) frozen at start. Must match the arena''s current catalog or one retired within 72 h (_assert_snapshot); every bill and extension is priced from it.';

comment on column public.sessions.policy_snapshot is 'The billing policy part of pricing_snapshot (pricing_snapshot->''policy''), stored separately at start.';

comment on column public.sessions.billed_amount_paise is 'Final bill in integer paise after cash rounding; null until ended. op_session_end refuses it unless it equals the server''s own re-pricing exactly.';

comment on column public.sessions.void_reason is 'Reason given by the owner when voiding; also written to audit_log.';

comment on column public.sessions.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.sessions.created_by is 'auth.users id of the staff member whose sync op started the session.';

comment on column public.sessions.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."sessions"
  enable row level security;

create index ix_sessions_arena_status on public.sessions using btree (arena_id, status);

create index ix_sessions_started on public.sessions using btree (arena_id, started_at);

create index ix_sessions_sync on public.sessions using btree (arena_id, sync_xid);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_sessions_request on public.sessions using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_sessions_booking_id on public.sessions using btree (booking_id);

create index ix_sessions_created_by on public.sessions using btree (created_by);

create index ix_sessions_customer_id on public.sessions using btree (customer_id);

-- Referenced booking and customer must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.sessions
  for each row
  execute function public._assert_same_arena('booking_id', 'bookings', 'customer_id', 'customers');

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_sessions_sync
  before insert or update on public.sessions
  for each row
  execute function public.sync_stamp();

create trigger t_sessions_tomb
  after delete on public.sessions
  for each row
  execute function public.sync_record_delete();

create trigger t_sessions_updated
  before update on public.sessions
  for each row
  execute function public.set_updated_at();

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_sessions" on "public"."sessions"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sessions"
  to "postgres", "service_role";

revoke all on table "public"."sessions" from "anon";

revoke all on table "public"."sessions" from "authenticated";

grant select on table "public"."sessions" to "authenticated";