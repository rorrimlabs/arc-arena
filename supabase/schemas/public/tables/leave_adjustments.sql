-- leave_adjustments — manual changes to a person's paid-leave balance for one leave year
--
-- Append-only, written by op_leave_adjust (leave.adjust, needs leave_approve) with a reason:
-- an opening balance for someone who joined before the app, or a correction. year_start is
-- the joining anniversary that starts the leave year it counts in (_leave_year_start).
create table "public"."leave_adjustments" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "staff_id"   uuid                     not null,
  "year_start" date                     not null,
  "days"       numeric(4,1)             not null,
  "reason"     text                     not null,
  "created_by" uuid                     not null,
  "created_at" timestamp with time zone not null default now(),
  constraint "leave_adjustments_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "leave_adjustments_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "leave_adjustments_days_check" check ((days <> (0)::numeric)),
  constraint "leave_adjustments_pkey" primary key (id),
  constraint "leave_adjustments_reason_check" check ((btrim(reason) <> ''::text)),
  constraint "leave_adjustments_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id)
);

comment on table public.leave_adjustments is 'Append-only manual changes (signed days, with a reason) to a staff member''s paid-leave balance for one leave year.';

comment on column public.leave_adjustments.year_start is 'First day of the leave year (a joining anniversary) the change counts in.';

alter table "public"."leave_adjustments"
  enable row level security;

create index ix_leave_adjustments_staff on public.leave_adjustments using btree (staff_id, year_start);

create index ix_leave_adjustments_arena on public.leave_adjustments using btree (arena_id);

create index ix_leave_adjustments_created_by on public.leave_adjustments using btree (created_by);

create trigger t_same_arena
  before insert or update on public.leave_adjustments
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- Same readers as leave_requests.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_leave_adjustments" on "public"."leave_adjustments"
  for select
  to authenticated
  using (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in ( select private.app_arena_ids_with(ARRAY['leave_approve'::text, 'attendance_review'::text, 'payroll'::text]) as app_arena_ids_with))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."leave_adjustments"
  to "postgres", "service_role";

revoke all on table "public"."leave_adjustments" from "anon";

revoke all on table "public"."leave_adjustments" from "authenticated";

grant select on table "public"."leave_adjustments" to "authenticated";
