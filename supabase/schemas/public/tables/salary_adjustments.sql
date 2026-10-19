-- salary_adjustments — bonuses, advances and one-off deductions in a run (append-only)
--
-- Written by op_salary_adjustment_add / op_salary_adjustment_reverse while the run is a draft,
-- always with a note. Signed paise: a bonus is positive, an advance or a deduction negative; a
-- mistake is undone by a reversal row (the opposite amount, reverses_id), never by an edit.
create table "public"."salary_adjustments" (
  "id"           uuid                     not null,
  "arena_id"     uuid                     not null,
  "run_id"       uuid                     not null,
  "staff_id"     uuid                     not null,
  "kind"         text                     not null,
  "amount_paise" bigint                   not null,
  "note"         text                     not null,
  "reverses_id"  uuid,
  "created_by"   uuid                     not null,
  "created_at"   timestamp with time zone not null default now(),
  constraint "salary_adjustments_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "salary_adjustments_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "salary_adjustments_kind_check" check ((kind = ANY (ARRAY['bonus'::text, 'advance'::text, 'deduction'::text, 'reversal'::text]))),
  constraint "salary_adjustments_note_check" check ((btrim(note) <> ''::text)),
  constraint "salary_adjustments_pkey" primary key (id),
  constraint "salary_adjustments_reverses_id_fkey" foreign key (reverses_id) references public.salary_adjustments(id),
  constraint "salary_adjustments_reverses_id_key" unique (reverses_id),
  constraint "salary_adjustments_run_id_fkey" foreign key (run_id) references public.salary_runs(id) on delete cascade,
  constraint "salary_adjustments_sign_check" check (((amount_paise <> 0) AND ((kind <> 'bonus'::text) OR (amount_paise > 0)) AND ((kind <> ALL (ARRAY['advance'::text, 'deduction'::text])) OR (amount_paise < 0)) AND ((kind = 'reversal'::text) = (reverses_id IS NOT NULL)))),
  constraint "salary_adjustments_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id)
);

comment on table public.salary_adjustments is 'Append-only salary adjustments in a run (bonus, advance, deduction, reversal) with a note; signed paise.';

comment on column public.salary_adjustments.amount_paise is 'Signed paise: bonus > 0; advance and deduction < 0; a reversal is the opposite of the row it reverses.';

alter table "public"."salary_adjustments"
  enable row level security;

create index ix_salary_adjustments_run_staff on public.salary_adjustments using btree (run_id, staff_id);

create index ix_salary_adjustments_staff on public.salary_adjustments using btree (staff_id);

create index ix_salary_adjustments_arena on public.salary_adjustments using btree (arena_id);

create index ix_salary_adjustments_created_by on public.salary_adjustments using btree (created_by);

create trigger t_same_arena
  before insert or update on public.salary_adjustments
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'run_id', 'salary_runs');

-- Append-only: corrections are new rows (_append_only).
create trigger t_salary_adjustments_append_only
  before update or delete on public.salary_adjustments
  for each row
  execute function public._append_only();

-- payroll / payroll_finalise holders only.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_salary_adjustments" on "public"."salary_adjustments"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text, 'payroll_finalise'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_adjustments"
  to "postgres", "service_role";

revoke all on table "public"."salary_adjustments" from "anon";

revoke all on table "public"."salary_adjustments" from "authenticated";

grant select on table "public"."salary_adjustments" to "authenticated";
