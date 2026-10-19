-- salary_deduction_decisions — the owner's keep / waive choice per suggested deduction
--
-- One row per (run, person, deduction code), written by op_salary_run_set_deduction while the
-- run is a draft; no row = the suggestion applies. Kept apart from the lines so a rebuild never
-- loses the owner's choices.
create table "public"."salary_deduction_decisions" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "run_id"     uuid                     not null,
  "staff_id"   uuid                     not null,
  "code"       text                     not null,
  "applied"    boolean                  not null,
  "note"       text,
  "decided_by" uuid                     not null,
  "decided_at" timestamp with time zone not null default now(),
  constraint "salary_deduction_decisions_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "salary_deduction_decisions_code_check" check ((code = ANY (ARRAY['absent'::text, 'lop_leave'::text, 'half_day'::text, 'late'::text]))),
  constraint "salary_deduction_decisions_decided_by_fkey" foreign key (decided_by) references auth.users(id),
  constraint "salary_deduction_decisions_pkey" primary key (id),
  constraint "salary_deduction_decisions_run_id_staff_id_code_key" unique (run_id, staff_id, code),
  constraint "salary_deduction_decisions_run_id_fkey" foreign key (run_id) references public.salary_runs(id) on delete cascade,
  constraint "salary_deduction_decisions_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id)
);

comment on table public.salary_deduction_decisions is 'The owner''s keep (applied) or waive decision on each suggested salary deduction of a draft run.';

alter table "public"."salary_deduction_decisions"
  enable row level security;

create index ix_salary_deduction_decisions_staff on public.salary_deduction_decisions using btree (staff_id);

create index ix_salary_deduction_decisions_arena on public.salary_deduction_decisions using btree (arena_id);

create index ix_salary_deduction_decisions_decided_by on public.salary_deduction_decisions using btree (decided_by);

create trigger t_same_arena
  before insert or update on public.salary_deduction_decisions
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'run_id', 'salary_runs');

-- payroll / payroll_finalise holders only.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_salary_deduction_decisions" on "public"."salary_deduction_decisions"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text, 'payroll_finalise'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_deduction_decisions"
  to "postgres", "service_role";

revoke all on table "public"."salary_deduction_decisions" from "anon";

revoke all on table "public"."salary_deduction_decisions" from "authenticated";

grant select on table "public"."salary_deduction_decisions" to "authenticated";
