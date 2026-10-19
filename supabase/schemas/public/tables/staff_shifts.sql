-- staff_shifts — who works which shift, from when to when
--
-- A person can hold several shifts at once (a split shift); the same person and shift never
-- overlap in time (staff_shifts_no_overlap). effective_to is inclusive; null = open-ended.
-- Written by op_shift_assign / op_shift_unassign (shift.assign / shift.unassign, needs settings).
create table "public"."staff_shifts" (
  "id"             uuid                     not null default gen_random_uuid(),
  "arena_id"       uuid                     not null,
  "staff_id"       uuid                     not null,
  "shift_id"       uuid                     not null,
  "effective_from" date                     not null,
  "effective_to"   date,
  "created_at"     timestamp with time zone not null default now(),
  "updated_at"     timestamp with time zone not null default now(),
  constraint "staff_shifts_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_shifts_no_overlap" exclude using gist (staff_id with =, shift_id with =,
    daterange(effective_from, effective_to, '[]'::text) with &&),
  constraint "staff_shifts_pkey" primary key (id),
  constraint "staff_shifts_range_check" check (((effective_to IS NULL) OR (effective_to >= effective_from))),
  constraint "staff_shifts_shift_id_fkey" foreign key (shift_id) references public.shifts(id) on delete cascade,
  constraint "staff_shifts_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id)
);

comment on table public.staff_shifts is 'Shift assignments per staff profile with an inclusive effective date range (null end = open-ended).';

comment on column public.staff_shifts.effective_to is 'Last day (inclusive); null = open-ended.';

alter table "public"."staff_shifts"
  enable row level security;

create index ix_staff_shifts_staff on public.staff_shifts using btree (staff_id, effective_from);

create index ix_staff_shifts_shift on public.staff_shifts using btree (shift_id);

create index ix_staff_shifts_arena on public.staff_shifts using btree (arena_id);

create trigger t_staff_shifts_updated
  before update on public.staff_shifts
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.staff_shifts
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'shift_id', 'shifts');

-- Every member sees the roster.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_shifts" on "public"."staff_shifts"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_shifts"
  to "postgres", "service_role";

revoke all on table "public"."staff_shifts" from "anon";

revoke all on table "public"."staff_shifts" from "authenticated";

grant select on table "public"."staff_shifts" to "authenticated";
