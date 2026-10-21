-- salary_run_lines — one person's pay for one run: the timesheet and the breakdown
--
-- Rebuilt by _pay_build_line while the run is a draft, frozen when it is finalised. days is the
-- timesheet (one entry per day, from _att_day); deductions are the suggested ones, each with
-- the owner's keep/waive decision (applied); only applied ones count.
create table "public"."salary_run_lines" (
  "id"                uuid                     not null default gen_random_uuid(),
  "arena_id"          uuid                     not null,
  "run_id"            uuid                     not null,
  "staff_id"          uuid                     not null,
  "staff_name"        text                     not null,
  "pay_type"          text                     not null,
  "rates"             jsonb                    not null,
  "day_counts"        jsonb                    not null,
  "worked_min"        integer                  not null,
  "regular_min"       integer                  not null,
  "extra_min"         integer                  not null,
  "base_paise"        bigint                   not null,
  "extra_paise"       bigint                   not null,
  "gross_paise"       bigint                   not null,
  "deductions"        jsonb                    not null,
  "deductions_paise"  bigint                   not null,
  "adjustments_paise" bigint                   not null,
  "net_paise"         bigint                   not null,
  "days"              jsonb                    not null,
  "notes"             jsonb                    not null default '[]'::jsonb,
  constraint "salary_run_lines_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "salary_run_lines_pkey" primary key (id),
  constraint "salary_run_lines_run_id_staff_id_key" unique (run_id, staff_id),
  constraint "salary_run_lines_run_id_fkey" foreign key (run_id) references public.salary_runs(id) on delete cascade,
  constraint "salary_run_lines_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id)
);

comment on table public.salary_run_lines is 'One staff member''s pay in one salary run: day-by-day timesheet, rates used, base, extra hours, suggested deductions with keep/waive, adjustments and net, in paise.';

comment on column public.salary_run_lines.deductions is '[{code, label, units, rate_paise, amount_paise, applied, note}]: suggested deductions (absent, lop_leave, half_day, late); only applied ones count.';

comment on column public.salary_run_lines.days is 'The timesheet: one entry per day of the period from _att_day.';

alter table "public"."salary_run_lines"
  enable row level security;

create index ix_salary_run_lines_staff on public.salary_run_lines using btree (staff_id);

create index ix_salary_run_lines_arena on public.salary_run_lines using btree (arena_id);

create trigger t_same_arena
  before insert or update on public.salary_run_lines
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'run_id', 'salary_runs');

-- payroll / payroll_finalise holders only.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_salary_run_lines" on "public"."salary_run_lines"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text, 'payroll_finalise'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_run_lines"
  to "postgres", "service_role";

revoke all on table "public"."salary_run_lines" from "anon";

revoke all on table "public"."salary_run_lines" from "authenticated";

grant select on table "public"."salary_run_lines" to "authenticated";
