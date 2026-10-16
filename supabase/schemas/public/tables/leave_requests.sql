-- leave_requests — a staff member's request for time off and the decision on it
--
-- Written by op_leave_request (the person), op_leave_cancel (the person) and op_leave_decide
-- (leave_approve). days counts working days only (a shift that day, not a staff holiday),
-- fixed when the request is made. On approval the approver splits the days into paid and LOP
-- (loss of pay) and day_split pins which dates are which (paid days fill the earliest dates):
-- the attendance day (_att_day) and the salary run read the split, never recompute it.
-- A cancellation of approved leave waits for approval (cancel_pending keeps the split).
create table "public"."leave_requests" (
  "id"             uuid                     not null,
  "arena_id"       uuid                     not null,
  "staff_id"       uuid                     not null,
  "kind"           text                     not null,
  "from_date"      date                     not null,
  "to_date"        date                     not null,
  "half_day"       text                     not null default 'none'::text,
  "days"           numeric(4,1)             not null,
  "paid_days"      numeric(4,1),
  "lop_days"       numeric(4,1),
  "day_split"      jsonb,
  "reason"         text                     not null,
  "status"         text                     not null default 'pending'::text,
  "decided_by"     uuid,
  "decided_at"     timestamp with time zone,
  "decision_note"  text,
  "cancel_reason"  text,
  "created_by"     uuid                     not null,
  "created_at"     timestamp with time zone not null default now(),
  "updated_at"     timestamp with time zone not null default now(),
  constraint "leave_requests_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "leave_requests_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "leave_requests_days_check" check ((days > (0)::numeric)),
  constraint "leave_requests_decided_by_fkey" foreign key (decided_by) references auth.users(id),
  constraint "leave_requests_half_day_check" check (((half_day = ANY (ARRAY['none'::text, 'first_half'::text, 'second_half'::text])) AND ((half_day = 'none'::text) OR (from_date = to_date)))),
  constraint "leave_requests_kind_check" check ((kind = ANY (ARRAY['planned'::text, 'unplanned'::text]))),
  constraint "leave_requests_pkey" primary key (id),
  constraint "leave_requests_range_check" check ((to_date >= from_date)),
  constraint "leave_requests_reason_check" check ((btrim(reason) <> ''::text)),
  constraint "leave_requests_split_check" check (
    CASE WHEN (status = ANY (ARRAY['approved'::text, 'cancel_pending'::text]))
         THEN ((paid_days >= (0)::numeric) AND (lop_days >= (0)::numeric) AND ((paid_days + lop_days) = days) AND (day_split IS NOT NULL))
         ELSE ((paid_days IS NULL) AND (lop_days IS NULL)) END),
  constraint "leave_requests_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "leave_requests_status_check" check ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'cancel_pending'::text])))
);

comment on table public.leave_requests is 'Leave requests per staff profile: dates, planned/unplanned, working days counted, and the approver''s paid/LOP split pinned to dates (day_split).';

comment on column public.leave_requests.days is 'Working days the request covers (0.5 for a half day), counted when it is made.';

comment on column public.leave_requests.paid_days is 'Days paid from the allowance, set on approval; null until then.';

comment on column public.leave_requests.lop_days is 'Days of loss of pay (days - paid_days), set on approval.';

comment on column public.leave_requests.day_split is 'Set on approval: [{day, units, paid_units}] for each working day, paid days filling the earliest dates. Kept while cancel_pending.';

comment on column public.leave_requests.status is 'pending, approved, rejected, cancelled, or cancel_pending (approved leave whose cancellation awaits approval).';

alter table "public"."leave_requests"
  enable row level security;

create index ix_leave_requests_staff on public.leave_requests using btree (staff_id, from_date);

create index ix_leave_requests_arena_status on public.leave_requests using btree (arena_id, status);

create index ix_leave_requests_decided_by on public.leave_requests using btree (decided_by);

create index ix_leave_requests_created_by on public.leave_requests using btree (created_by);

create trigger t_leave_requests_updated
  before update on public.leave_requests
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.leave_requests
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- A member reads their own requests; leave_approve, attendance_review or payroll read everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_leave_requests" on "public"."leave_requests"
  for select
  to authenticated
  using (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in ( select private.app_arena_ids_with(ARRAY['leave_approve'::text, 'attendance_review'::text, 'payroll'::text]) as app_arena_ids_with))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."leave_requests"
  to "postgres", "service_role";

revoke all on table "public"."leave_requests" from "anon";

revoke all on table "public"."leave_requests" from "authenticated";

grant select on table "public"."leave_requests" to "authenticated";
