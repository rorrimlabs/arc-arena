-- group_sessions — one shared countdown over several players (parent of assignments)
--
-- A party sharing one start/end and one bill; who plays where lives in
-- group_assignments. Written by op_group_create, op_group_add / switch /
-- end_player (updated_at), op_group_extend (scheduled_end_at), op_group_end
-- (completed + billed), op_group_void (owner-only) and op_payment
-- (payment_status). pricing_snapshot is frozen at create and billing_mode must be
-- the one it prescribes; the server re-prices the bill (_pr_group_bill, 0013).
create table "public"."group_sessions" (
  "id"                         uuid                     not null default gen_random_uuid(),
  "arena_id"                   uuid                     not null,
  "primary_customer_id"        uuid                     not null,
  "player_count"               integer                  not null,
  "purchased_controller_count" integer                  not null default 0,
  "status"                     text                     not null default 'active'::text,
  "payment_status"             text                     not null default 'unpaid'::text,
  "started_at"                 timestamp with time zone not null,
  "scheduled_end_at"           timestamp with time zone not null,
  "actual_ended_at"            timestamp with time zone,
  "pricing_snapshot"           jsonb                    not null,
  "policy_snapshot"            jsonb,
  "billing_mode"               text                     not null default 'per_system'::text,
  "billed_amount_paise"        bigint,
  "void_reason"                text,
  "request_id"                 text,
  "created_at"                 timestamp with time zone not null default now(),
  "updated_at"                 timestamp with time zone not null default now(),
  "created_by"                 uuid,
  "sync_xid"                   xid8                     not null default pg_current_xact_id(),
  constraint "group_sessions_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "group_sessions_billing_mode_check"
    check ((billing_mode = ANY (ARRAY['per_system'::text, 'shared_controller_pool'::text]))),
  constraint "group_sessions_check" check ((scheduled_end_at > started_at)),
  constraint "group_sessions_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "group_sessions_payment_status_check"
    check
    ((payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text, 'paid'::text, 'waived'::text]))),
  constraint "group_sessions_pkey" primary key (id),
  constraint "group_sessions_player_count_check" check ((player_count > 0)),
  constraint "group_sessions_primary_customer_id_fkey" foreign key (primary_customer_id)
    references public.customers(id),
  constraint "group_sessions_status_check"
    check ((status = ANY (ARRAY['active'::text, 'completed'::text, 'voided'::text])))
);

comment on table public.group_sessions is 'A group session: one shared countdown and one bill over several players, whose station placements are group_assignments.';

comment on column public.group_sessions.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.group_sessions.primary_customer_id is 'Lead customer of the group; op_group_create records the visit on this customer.';

comment on column public.group_sessions.player_count is 'Number of players in the party (> 0), as declared at create.';

comment on column public.group_sessions.purchased_controller_count is 'Controllers bought for the whole window in shared_controller_pool mode (staff''s declaration); 0 otherwise.';

comment on column public.group_sessions.status is 'active, completed (ended and billed by op_group_end) or voided (owner void; row kept).';

comment on column public.group_sessions.payment_status is 'unpaid, partial, paid or waived; recomputed from group_payments against billed_amount_paise. waived is sticky.';

comment on column public.group_sessions.started_at is 'Group start (UTC), as reported by the device.';

comment on column public.group_sessions.scheduled_end_at is 'Planned end of the shared countdown (UTC); moved by group_extensions.';

comment on column public.group_sessions.actual_ended_at is 'When the group actually ended (UTC); null while active.';

comment on column public.group_sessions.pricing_snapshot is 'Immutable copy of the arena''s price list frozen at create; must match the current catalog or one retired within 72 h (_assert_snapshot). Every bill and extension is priced from it.';

comment on column public.group_sessions.policy_snapshot is 'The billing policy part of pricing_snapshot (pricing_snapshot->''policy''), stored separately at create.';

comment on column public.group_sessions.billing_mode is 'per_system (each station billed at its own controller count) or shared_controller_pool (purchased controllers billed once over the window); must equal the snapshot policy''s group_billing_mode.';

comment on column public.group_sessions.billed_amount_paise is 'Final bill in integer paise after cash rounding; null until ended. Must equal the server''s re-pricing exactly.';

comment on column public.group_sessions.void_reason is 'Reason given by the owner when voiding; also written to audit_log.';

comment on column public.group_sessions.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.group_sessions.created_by is 'auth.users id of the staff member whose sync op created the group.';

comment on column public.group_sessions.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."group_sessions"
  enable row level security;

create index ix_group_sessions_sync on public.group_sessions using btree (arena_id, sync_xid);

create index ix_groups_arena_status on public.group_sessions using btree (arena_id, status);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_groups_request on public.group_sessions using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_group_sessions_created_by on public.group_sessions using btree (created_by);

create index ix_group_sessions_primary_customer_id on public.group_sessions using btree (primary_customer_id);

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_group_sessions_sync
  before insert or update on public.group_sessions
  for each row
  execute function public.sync_stamp();

create trigger t_group_sessions_tomb
  after delete on public.group_sessions
  for each row
  execute function public.sync_record_delete();

create trigger t_groups_updated
  before update on public.group_sessions
  for each row
  execute function public.set_updated_at();

-- Referenced customer must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.group_sessions
  for each row
  execute function public._assert_same_arena('primary_customer_id', 'customers');

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_group_sessions" on "public"."group_sessions"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_sessions"
  to "postgres", "service_role";

revoke all on table "public"."group_sessions" from "anon";

revoke all on table "public"."group_sessions" from "authenticated";

grant select on table "public"."group_sessions" to "authenticated";