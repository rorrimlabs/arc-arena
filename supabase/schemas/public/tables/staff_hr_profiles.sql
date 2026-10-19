-- staff_hr_profiles — what payroll and leave need to know about a staff member
--
-- One optional row per staff profile, written by op_hr_profile_save (hr_profile.save, needs
-- payroll). No row means: joined on the profile's creation date (IST), not left, tracked when
-- not role owner, and the arena defaults for the standard day (work_hours) and the paid-leave
-- allowance (leave_rules) — see _staff_hr. joined_on also starts each leave year.
create table "public"."staff_hr_profiles" (
  "staff_id"          uuid                     not null,
  "arena_id"          uuid                     not null,
  "joined_on"         date,
  "left_on"           date,
  "tracks_attendance" boolean                  not null default true,
  "employee_code"     text,
  "paid_leave_days"   numeric(4,1),
  "standard_day_min"  integer,
  "created_at"        timestamp with time zone not null default now(),
  "updated_at"        timestamp with time zone not null default now(),
  constraint "staff_hr_profiles_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_hr_profiles_dates_check" check (((left_on IS NULL) OR (joined_on IS NULL) OR (left_on >= joined_on))),
  constraint "staff_hr_profiles_leave_check" check (((paid_leave_days IS NULL) OR ((paid_leave_days >= (0)::numeric) AND (paid_leave_days <= (366)::numeric)))),
  constraint "staff_hr_profiles_pkey" primary key (staff_id),
  constraint "staff_hr_profiles_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id),
  constraint "staff_hr_profiles_std_day_check" check (((standard_day_min IS NULL) OR ((standard_day_min >= 60) AND (standard_day_min <= 1440))))
);

comment on table public.staff_hr_profiles is 'HR facts per staff profile for leave and payroll: joining/leaving dates, whether attendance is tracked, employee code, and overrides of the arena standard day and paid-leave allowance.';

comment on column public.staff_hr_profiles.joined_on is 'Joining date; each leave year runs from its anniversary. Null = the profile''s creation date.';

comment on column public.staff_hr_profiles.left_on is 'Last working day, or null while employed.';

comment on column public.staff_hr_profiles.tracks_attendance is 'Whether this person clocks in and appears on timesheets.';

comment on column public.staff_hr_profiles.paid_leave_days is 'Paid leave days per leave year; null = the arena default (leave_rules).';

comment on column public.staff_hr_profiles.standard_day_min is 'Minutes in a standard day (extra hours start after it); null = the arena default (work_hours).';

alter table "public"."staff_hr_profiles"
  enable row level security;

create index ix_staff_hr_profiles_arena on public.staff_hr_profiles using btree (arena_id);

create trigger t_staff_hr_profiles_updated
  before update on public.staff_hr_profiles
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.staff_hr_profiles
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- A member reads their own row; attendance_review, leave_approve or payroll read everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_hr_profiles" on "public"."staff_hr_profiles"
  for select
  to authenticated
  using (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in ( select private.app_arena_ids_with(ARRAY['attendance_review'::text, 'leave_approve'::text, 'payroll'::text]) as app_arena_ids_with))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_hr_profiles"
  to "postgres", "service_role";

revoke all on table "public"."staff_hr_profiles" from "anon";

revoke all on table "public"."staff_hr_profiles" from "authenticated";

grant select on table "public"."staff_hr_profiles" to "authenticated";
