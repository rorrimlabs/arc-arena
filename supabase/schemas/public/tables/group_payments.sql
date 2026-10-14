-- group_payments — append-only money in (payments) and out (refunds) for a group session
--
-- Written only by op_payment (scope group; it also recomputes
-- group_sessions.payment_status) and op_payment_correct. Same rules as payments: payments positive,
-- refunds negative with a reason; refunds need the discount permission; once the
-- bill is final, no overpayment and no refund beyond what was collected (0016,
-- group row locked). No payment on a voided group; a refund is allowed (money
-- taken before the void can be given back). op_payment_correct moves money between
-- methods as a refund + payment pair.
create table "public"."group_payments" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "group_id"     uuid                     not null,
  "amount_paise" bigint                   not null,
  "method"       text                     not null,
  "is_refund"    boolean                  not null default false,
  "note"         text,
  "reason"       text,
  "request_id"   text,
  "created_at"   timestamp with time zone not null default now(),
  "created_by"   uuid,
  "sync_xid"     xid8                     not null default pg_current_xact_id(),
  constraint "group_payments_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  -- A refund must carry a reason.
  constraint "group_payments_check" check (((NOT is_refund) OR (reason IS NOT NULL))),
  constraint "group_payments_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "group_payments_method_check"
    check ((method = ANY (ARRAY['cash'::text, 'upi'::text, 'card'::text, 'other'::text]))),
  -- Payments are positive, refunds negative; zero is never recorded.
  constraint "group_payments_amount_sign_check"
    check (((amount_paise <> 0) AND (is_refund = (amount_paise < 0)))),
  constraint "group_payments_pkey" primary key (id),
  constraint "group_payments_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade
);

comment on table public.group_payments is 'Append-only payments and refunds against a group session; their sum is what was collected.';

comment on column public.group_payments.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.group_payments.amount_paise is 'Signed integer paise: positive for a payment, negative for a refund, never zero.';

comment on column public.group_payments.method is 'cash, upi, card or other.';

comment on column public.group_payments.is_refund is 'True for a refund; must agree with the sign of amount_paise (payments.kind is the single-session equivalent).';

comment on column public.group_payments.note is 'Free-text staff note.';

comment on column public.group_payments.reason is 'Why the refund was given; required when is_refund.';

comment on column public.group_payments.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.group_payments.created_by is 'auth.users id of the staff member whose sync op recorded the payment.';

comment on column public.group_payments.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."group_payments"
  enable row level security;

create index ix_group_payments_group on public.group_payments using btree (group_id, created_at);

create index ix_group_payments_sync on public.group_payments using btree (arena_id, sync_xid);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_group_payments_request on public.group_payments
  using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_group_payments_created_by on public.group_payments using btree (created_by);

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_group_payments_sync
  before insert or update on public.group_payments
  for each row
  execute function public.sync_stamp();

create trigger t_group_payments_tomb
  after delete on public.group_payments
  for each row
  execute function public.sync_record_delete();

-- Referenced group must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.group_payments
  for each row
  execute function public._assert_same_arena('group_id', 'group_sessions');

-- Readable by an active member holding bill, or owner level (money/reports): floor billing and the dashboard's Sales.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_group_payments" on "public"."group_payments"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text, 'reports'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_payments"
  to "postgres", "service_role";

revoke all on table "public"."group_payments" from "anon";

revoke all on table "public"."group_payments" from "authenticated";

grant select on table "public"."group_payments" to "authenticated";