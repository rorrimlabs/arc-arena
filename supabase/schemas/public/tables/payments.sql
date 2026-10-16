-- payments — append-only money in (payments) and out (refunds) for a single session
--
-- Written only by op_payment (scope single; it also recomputes
-- sessions.payment_status) and op_payment_correct. Rules: payments positive, refunds negative with a
-- reason (check constraints); refunds need the discount permission; once a bill
-- is final, payments may not exceed it and refunds may not exceed what was
-- collected (0016, parent session row locked). No payment on a voided session; a
-- refund is allowed (money taken before the void can be given back).
-- op_payment_correct moves money between methods as a refund + payment pair.
-- The device-generated id is the primary key, so a re-sent payment cannot double.
create table "public"."payments" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "session_id"   uuid                     not null,
  "amount_paise" bigint                   not null,
  "method"       text                     not null,
  "kind"         text                     not null default 'payment'::text,
  "note"         text,
  "reason"       text,
  "request_id"   text,
  "created_at"   timestamp with time zone not null default now(),
  "created_by"   uuid,
  "sync_xid"     xid8                     not null default pg_current_xact_id(),
  constraint "payments_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  -- A refund must carry a reason.
  constraint "payments_check" check (((kind <> 'refund'::text) OR (reason IS NOT NULL))),
  constraint "payments_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "payments_kind_check" check ((kind = ANY (ARRAY['payment'::text, 'refund'::text]))),
  constraint "payments_method_check"
    check ((method = ANY (ARRAY['cash'::text, 'upi'::text, 'card'::text, 'other'::text]))),
  -- Payments are positive, refunds negative; zero is never recorded.
  constraint "payments_amount_sign_check"
    check (((amount_paise <> 0) AND ((kind = 'refund'::text) = (amount_paise < 0)))),
  constraint "payments_pkey" primary key (id),
  constraint "payments_session_id_fkey" foreign key (session_id) references public.sessions(id)
    on delete cascade
);

comment on table public.payments is 'Append-only payments and refunds against a single session; their sum is what was collected.';

comment on column public.payments.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.payments.amount_paise is 'Signed integer paise: positive for a payment, negative for a refund, never zero.';

comment on column public.payments.method is 'cash, upi, card or other.';

comment on column public.payments.kind is 'payment or refund; must agree with the sign of amount_paise.';

comment on column public.payments.note is 'Free-text staff note.';

comment on column public.payments.reason is 'Why the refund was given; required when kind = refund.';

comment on column public.payments.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.payments.created_by is 'auth.users id of the staff member whose sync op recorded the payment.';

comment on column public.payments.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."payments"
  enable row level security;

create index ix_payments_session on public.payments using btree (session_id, created_at);

create index ix_payments_sync on public.payments using btree (arena_id, sync_xid);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_payments_request on public.payments using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_payments_created_by on public.payments using btree (created_by);

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_payments_sync
  before insert or update on public.payments
  for each row
  execute function public.sync_stamp();

create trigger t_payments_tomb
  after delete on public.payments
  for each row
  execute function public.sync_record_delete();

-- Referenced session must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.payments
  for each row
  execute function public._assert_same_arena('session_id', 'sessions');

-- Readable by an active member holding bill, or owner level (money/reports): floor billing and the dashboard's Sales.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_payments" on "public"."payments"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text, 'reports'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."payments"
  to "postgres", "service_role";

revoke all on table "public"."payments" from "anon";

revoke all on table "public"."payments" from "authenticated";

grant select on table "public"."payments" to "authenticated";