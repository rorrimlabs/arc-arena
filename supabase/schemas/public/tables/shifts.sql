-- shifts — the arena's named working hours (start, end, days of the week, unpaid break)
--
-- Times are minutes after IST midnight; end_min <= start_min means the shift ends the next
-- day. People are put on shifts through staff_shifts; a day none of a person's shifts covers
-- is their week off. Written by op_shift_upsert (shift.upsert, needs settings).
create table "public"."shifts" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "name"       text                     not null,
  "start_min"  integer                  not null,
  "end_min"    integer                  not null,
  "days"       smallint[]               not null,
  "break_min"  integer                  not null default 0,
  "active"     boolean                  not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  constraint "shifts_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "shifts_break_check" check (((break_min >= 0) AND (break_min < 720))),
  constraint "shifts_days_check" check (((days <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint]) AND (cardinality(days) > 0))),
  constraint "shifts_minutes_check" check (((start_min >= 0) AND (start_min <= 1439) AND (end_min >= 0) AND (end_min <= 1439) AND (end_min <> start_min))),
  constraint "shifts_name_check" check ((btrim(name) <> ''::text)),
  constraint "shifts_pkey" primary key (id)
);

comment on table public.shifts is 'Named shifts per arena: IST start/end minutes (end <= start = ends next day), ISO weekdays and an unpaid break.';

comment on column public.shifts.start_min is 'Start, minutes after IST midnight (0–1439).';

comment on column public.shifts.end_min is 'End, minutes after IST midnight; <= start_min means the next day.';

comment on column public.shifts.days is 'ISO weekdays the shift runs on (1 = Monday … 7 = Sunday).';

comment on column public.shifts.break_min is 'Unpaid break in minutes, deducted once a day (see work_hours.break_after_min).';

alter table "public"."shifts"
  enable row level security;

create unique index ux_shifts_name on public.shifts using btree (arena_id, lower(name));

create trigger t_shifts_updated
  before update on public.shifts
  for each row
  execute function public.set_updated_at();

-- Every member sees the shifts (the roster is not secret).
-- No write policy: clients change data only through sync_push.
create policy "p_sel_shifts" on "public"."shifts"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."shifts"
  to "postgres", "service_role";

revoke all on table "public"."shifts" from "anon";

revoke all on table "public"."shifts" from "authenticated";

grant select on table "public"."shifts" to "authenticated";
