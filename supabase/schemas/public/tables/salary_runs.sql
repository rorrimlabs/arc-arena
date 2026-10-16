-- salary_runs — one pay period's salary calculation: draft, then finalised (locked) or discarded
--
-- Created by op_salary_run_create; while draft its lines are rebuilt from live attendance,
-- leave, rates and the owner's keep/waive decisions and adjustments (_pay_rebuild_run).
-- Finalising freezes everything and locks the period: attendance corrections and leave
-- decisions inside it are refused (period_finalised). Runs that are not discarded never
-- overlap (salary_runs_no_overlap).
create table "public"."salary_runs" (
  "id"                uuid                     not null,
  "arena_id"          uuid                     not null,
  "period_start"      date                     not null,
  "period_end"        date                     not null,
  "status"            text                     not null default 'draft'::text,
  "rules_snapshot"    jsonb                    not null,
  "computed_at"       timestamp with time zone not null,
  "staff_count"       integer                  not null default 0,
  "gross_paise"       bigint                   not null default 0,
  "deductions_paise"  bigint                   not null default 0,
  "adjustments_paise" bigint                   not null default 0,
  "net_paise"         bigint                   not null default 0,
  "created_by"        uuid                     not null,
  "created_at"        timestamp with time zone not null default now(),
  "finalised_by"      uuid,
  "finalised_at"      timestamp with time zone,
  "updated_at"        timestamp with time zone not null default now(),
  constraint "salary_runs_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "salary_runs_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "salary_runs_final_check" check (((status = 'finalised'::text) = (finalised_at IS NOT NULL))),
  constraint "salary_runs_finalised_by_fkey" foreign key (finalised_by) references auth.users(id),
  constraint "salary_runs_no_overlap" exclude using gist (arena_id with =,
    daterange(period_start, period_end, '[]'::text) with &&) where ((status <> 'discarded'::text)),
  constraint "salary_runs_period_check" check (((period_end >= period_start) AND ((period_end - period_start) < 62))),
  constraint "salary_runs_pkey" primary key (id),
  constraint "salary_runs_status_check" check ((status = ANY (ARRAY['draft'::text, 'finalised'::text, 'discarded'::text])))
);

comment on table public.salary_runs is 'Salary runs per arena and pay period: draft (rebuilt on demand), finalised (frozen, locks the period) or discarded; totals in paise.';

comment on column public.salary_runs.rules_snapshot is 'The rules used: {work_hours, attendance, leave_rules, pay_policy}.';

comment on column public.salary_runs.status is 'draft, finalised (locked) or discarded.';

alter table "public"."salary_runs"
  enable row level security;

create index ix_salary_runs_arena_period on public.salary_runs using btree (arena_id, period_start);

create index ix_salary_runs_created_by on public.salary_runs using btree (created_by);

create index ix_salary_runs_finalised_by on public.salary_runs using btree (finalised_by);

create trigger t_salary_runs_updated
  before update on public.salary_runs
  for each row
  execute function public.set_updated_at();

-- payroll / payroll_finalise holders only.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_salary_runs" on "public"."salary_runs"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text, 'payroll_finalise'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_runs"
  to "postgres", "service_role";

revoke all on table "public"."salary_runs" from "anon";

revoke all on table "public"."salary_runs" from "authenticated";

grant select on table "public"."salary_runs" to "authenticated";
