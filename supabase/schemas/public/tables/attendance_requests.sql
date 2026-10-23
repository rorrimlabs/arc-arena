-- attendance_requests — a staff member's request to fix their own attendance (a missed punch)
--
-- Written by op_attendance_request (the person) and op_attendance_request_decide
-- (attendance_review). kind 'add': a stretch that was never punched (in_at → out_at); kind
-- 'fix_out': a clock-out for an existing entry (entry_id) that was never closed or was closed
-- automatically (in_at copies the entry's clock-in). Nothing counts until approved: approval
-- applies it through op_attendance_correct (add / edit), which writes attendance_entries and
-- the audit log, and result_entry_id points at the row it made. _att_day never reads this table.
create table "public"."attendance_requests" (
  "id"              uuid                     not null,
  "arena_id"        uuid                     not null,
  "staff_id"        uuid                     not null,
  "kind"            text                     not null,
  "entry_id"        uuid,
  "in_at"           timestamp with time zone not null,
  "out_at"          timestamp with time zone not null,
  "reason"          text                     not null,
  "status"          text                     not null default 'pending'::text,
  "decided_by"      uuid,
  "decided_at"      timestamp with time zone,
  "decision_note"   text,
  "result_entry_id" uuid,
  "created_by"      uuid                     not null,
  "created_at"      timestamp with time zone not null default now(),
  "updated_at"      timestamp with time zone not null default now(),
  constraint "attendance_requests_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "attendance_requests_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "attendance_requests_decided_by_fkey" foreign key (decided_by) references auth.users(id),
  constraint "attendance_requests_entry_id_fkey" foreign key (entry_id) references public.attendance_entries(id),
  constraint "attendance_requests_entry_check" check (((kind = 'fix_out'::text) = (entry_id IS NOT NULL))),
  constraint "attendance_requests_kind_check" check ((kind = ANY (ARRAY['add'::text, 'fix_out'::text]))),
  constraint "attendance_requests_pkey" primary key (id),
  constraint "attendance_requests_reason_check" check ((btrim(reason) <> ''::text)),
  constraint "attendance_requests_result_entry_id_fkey" foreign key (result_entry_id) references public.attendance_entries(id),
  constraint "attendance_requests_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id),
  constraint "attendance_requests_status_check" check ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
  constraint "attendance_requests_times_check" check ((out_at > in_at))
);

comment on table public.attendance_requests is 'Staff requests to fix their own attendance (a missed stretch, or a missed clock-out on an entry); applied through attendance.correct only when a reviewer approves.';

comment on column public.attendance_requests.kind is 'add (a stretch never punched) or fix_out (a clock-out for entry_id).';

comment on column public.attendance_requests.status is 'pending, approved (applied: result_entry_id) or rejected (decision_note).';

comment on column public.attendance_requests.result_entry_id is 'The attendance_entries row the approval created.';

alter table "public"."attendance_requests"
  enable row level security;

create index ix_attendance_requests_arena_status on public.attendance_requests using btree (arena_id, status);

create index ix_attendance_requests_staff on public.attendance_requests using btree (staff_id, in_at);

create index ix_attendance_requests_entry_id on public.attendance_requests using btree (entry_id);

create index ix_attendance_requests_result_entry_id on public.attendance_requests using btree (result_entry_id);

create index ix_attendance_requests_decided_by on public.attendance_requests using btree (decided_by);

create index ix_attendance_requests_created_by on public.attendance_requests using btree (created_by);

create trigger t_attendance_requests_updated
  before update on public.attendance_requests
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.attendance_requests
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- A member reads their own requests; attendance_review reads everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_attendance_requests" on "public"."attendance_requests"
  for select
  to authenticated
  using (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in ( select private.app_arena_ids_with(ARRAY['attendance_review'::text]) as app_arena_ids_with))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."attendance_requests"
  to "postgres", "service_role";

revoke all on table "public"."attendance_requests" from "anon";

revoke all on table "public"."attendance_requests" from "authenticated";

grant select on table "public"."attendance_requests" to "authenticated";
