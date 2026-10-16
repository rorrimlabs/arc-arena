-- attendance_entries — one stretch of work: a clock-in and (once closed) its clock-out
--
-- Opened by a clock-in punch and closed by the next clock-out (op_attendance_punch). A person
-- has at most one open entry (ux_attendance_entries_open) and active entries never overlap
-- (attendance_entries_no_overlap); split shifts are several entries on one day. work_date is
-- the IST date of in_at, so a shift that crosses midnight stays on the day it started. A
-- clock-in left open longer than the arena's max_open_hours is closed automatically at
-- in_at + max_open_hours on the person's next punch (out_source 'auto', flag auto_out,
-- review pending). Corrections (later phase) never edit a closed row: they mark it
-- superseded or voided and add a new row pointing at it through replaces_id. Not part of the
-- sync_pull feed: read online through RLS (own rows, or everyone's with attendance_review).
create table "public"."attendance_entries" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "staff_id"     uuid                     not null,
  "work_date"    date                     not null,
  "in_at"        timestamp with time zone not null,
  "out_at"       timestamp with time zone,
  "in_punch_id"  uuid,
  "out_punch_id" uuid,
  "source"       text                     not null default 'punch'::text,
  "out_source"   text,
  "status"       text                     not null default 'active'::text,
  "replaces_id"  uuid,
  "flags"        text[]                   not null default '{}'::text[],
  "review"       text                     not null default 'none'::text,
  "reason"       text,
  "created_by"   uuid                     not null,
  "created_at"   timestamp with time zone not null default now(),
  "updated_at"   timestamp with time zone not null default now(),
  constraint "attendance_entries_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "attendance_entries_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "attendance_entries_in_punch_id_fkey" foreign key (in_punch_id) references public.attendance_punches(id),
  -- No two active stretches of one person overlap (an open one runs to infinity).
  constraint "attendance_entries_no_overlap" exclude using gist (staff_id with =,
    tstzrange(in_at, coalesce(out_at, 'infinity'::timestamp with time zone)) with &&) where ((status = 'active'::text)),
  constraint "attendance_entries_order_check" check (((out_at IS NULL) OR (out_at > in_at))),
  constraint "attendance_entries_out_punch_id_fkey" foreign key (out_punch_id) references public.attendance_punches(id),
  constraint "attendance_entries_out_source_check" check ((((out_at IS NULL) = (out_source IS NULL))
    AND ((out_source IS NULL) OR (out_source = ANY (ARRAY['punch'::text, 'auto'::text, 'manual'::text]))))),
  constraint "attendance_entries_pkey" primary key (id),
  -- A row made by hand or as a correction says why.
  constraint "attendance_entries_reason_check" check ((((source = 'punch'::text) AND (replaces_id IS NULL)) OR (reason IS NOT NULL))),
  constraint "attendance_entries_replaces_id_fkey" foreign key (replaces_id) references public.attendance_entries(id),
  constraint "attendance_entries_review_check" check ((review = ANY (ARRAY['none'::text, 'pending'::text, 'accepted'::text, 'corrected'::text]))),
  constraint "attendance_entries_source_check" check ((source = ANY (ARRAY['punch'::text, 'manual'::text]))),
  constraint "attendance_entries_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id)
    on delete cascade,
  constraint "attendance_entries_status_check" check ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'voided'::text])))
);

comment on table public.attendance_entries is 'Stretches of work (clock-in to clock-out) per staff profile; worked hours are computed from these server times. Corrections supersede rows, never edit history.';

comment on column public.attendance_entries.arena_id is 'Owning arena (tenant).';

comment on column public.attendance_entries.staff_id is 'The staff profile that worked.';

comment on column public.attendance_entries.work_date is 'IST calendar date of in_at: a shift crossing midnight belongs to the day it started.';

comment on column public.attendance_entries.in_at is 'Server time of the clock-in.';

comment on column public.attendance_entries.out_at is 'Server time of the clock-out (or the automatic close); null while the person is on the clock.';

comment on column public.attendance_entries.in_punch_id is 'The clock-in punch (evidence); null for a row added by hand.';

comment on column public.attendance_entries.out_punch_id is 'The clock-out punch, when there was one (also kept on an automatic close made by a late clock-out).';

comment on column public.attendance_entries.source is 'punch (opened by a clock-in) or manual (added by a reviewer).';

comment on column public.attendance_entries.out_source is 'punch, auto (closed automatically after max_open_hours) or manual; null while open.';

comment on column public.attendance_entries.status is 'active, superseded (replaced by a correction) or voided. Only active rows count.';

comment on column public.attendance_entries.replaces_id is 'The row this correction replaces.';

comment on column public.attendance_entries.flags is 'Why the entry needs a look: outside_in/out, unknown_in/out, low_accuracy_in/out, no_geofence_in/out, mock_in/out, auto_out.';

comment on column public.attendance_entries.review is 'none, pending (flagged for a reviewer), accepted or corrected.';

comment on column public.attendance_entries.reason is 'Why the row was added or corrected by hand; required then.';

comment on column public.attendance_entries.created_by is 'auth.users id of the login that opened the row.';

alter table "public"."attendance_entries"
  enable row level security;

-- One open stretch per person.
create unique index ux_attendance_entries_open on public.attendance_entries using btree (staff_id)
  where ((out_at IS NULL) AND (status = 'active'::text));

create index ix_attendance_entries_day on public.attendance_entries using btree (arena_id, work_date);

create index ix_attendance_entries_staff_day on public.attendance_entries using btree (staff_id, work_date);

create index ix_attendance_entries_review on public.attendance_entries using btree (arena_id)
  where (review = 'pending'::text);

-- Foreign-key indexes (joins and cascading deletes).
create index ix_attendance_entries_in_punch on public.attendance_entries using btree (in_punch_id);

create index ix_attendance_entries_out_punch on public.attendance_entries using btree (out_punch_id);

create index ix_attendance_entries_replaces on public.attendance_entries using btree (replaces_id);

create index ix_attendance_entries_created_by on public.attendance_entries using btree (created_by);

create trigger t_attendance_entries_updated
  before update on public.attendance_entries
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.attendance_entries
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'in_punch_id', 'attendance_punches',
    'out_punch_id', 'attendance_punches', 'replaces_id', 'attendance_entries');

-- A member reads their own entries; attendance_review (or an owner) reads everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_attendance_entries" on "public"."attendance_entries"
  for select
  to authenticated
  using (((arena_id in ( select private.app_arena_ids_with(ARRAY['attendance_review'::text]) as app_arena_ids_with))
    or (staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."attendance_entries"
  to "postgres", "service_role";

revoke all on table "public"."attendance_entries" from "anon";

revoke all on table "public"."attendance_entries" from "authenticated";

grant select on table "public"."attendance_entries" to "authenticated";
