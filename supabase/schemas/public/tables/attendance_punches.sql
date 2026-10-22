-- attendance_punches — immutable evidence of every clock-in and clock-out
--
-- One row per punch, written only by op_attendance_punch (attendance.punch) and never
-- changed: corrections act on attendance_entries, never here. server_at is the server's own
-- clock and is the only time worked hours are computed from; device_at is what the phone
-- said, kept as evidence. The position (lat/lng/accuracy/mock) is captured once, at the
-- punch, in the foreground; geofence is the server's verdict against the rules in force at
-- that moment, which are copied into geofence_snapshot. Not part of the sync_pull feed:
-- the apps read it online through RLS (own rows, or everyone's with attendance_review).
create table "public"."attendance_punches" (
  "id"                uuid                     not null,
  "arena_id"          uuid                     not null,
  "staff_id"          uuid                     not null,
  "kind"              text                     not null,
  "server_at"         timestamp with time zone not null default statement_timestamp(),
  "device_at"         timestamp with time zone,
  "via"               text                     not null default 'own_device'::text,
  "device_id"         text                     not null,
  "lat"               double precision,
  "lng"               double precision,
  "accuracy_m"        numeric(7,1),
  "is_mocked"         boolean,
  "location_status"   text                     not null,
  "distance_m"        integer,
  "geofence"          text                     not null,
  "geofence_snapshot" jsonb                    not null,
  "flags"             text[]                   not null default '{}'::text[],
  "created_by"        uuid                     not null,
  constraint "attendance_punches_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "attendance_punches_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "attendance_punches_device_id_check" check ((btrim(device_id) <> ''::text)),
  constraint "attendance_punches_geofence_check" check ((geofence = ANY (ARRAY['inside'::text, 'outside'::text, 'unknown'::text]))),
  constraint "attendance_punches_kind_check" check ((kind = ANY (ARRAY['in'::text, 'out'::text]))),
  -- A position is both coordinates and an accuracy, or none of them.
  constraint "attendance_punches_latlng_check" check (((lat IS NULL) = (lng IS NULL)) AND ((lat IS NULL) = (accuracy_m IS NULL))
    AND ((lat IS NULL) OR ((lat >= ('-90'::integer)::double precision) AND (lat <= (90)::double precision)
      AND (lng >= ('-180'::integer)::double precision) AND (lng <= (180)::double precision) AND (accuracy_m >= (0)::numeric)))),
  constraint "attendance_punches_location_status_check" check ((location_status = ANY (ARRAY['ok'::text, 'denied'::text, 'gps_off'::text, 'timeout'::text, 'unavailable'::text]))),
  -- 'ok' is exactly the case where a position was captured.
  constraint "attendance_punches_ok_has_fix_check" check (((location_status = 'ok'::text) = (lat IS NOT NULL))),
  constraint "attendance_punches_pkey" primary key (id),
  constraint "attendance_punches_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id),
  constraint "attendance_punches_via_check" check ((via = 'own_device'::text))
);

comment on table public.attendance_punches is 'Append-only evidence of each clock-in / clock-out: server time, device time, GPS fix, mock flag, device and the geofence verdict with the rules used. Written by op_attendance_punch only.';

comment on column public.attendance_punches.id is 'Device-generated id (uuid v4), so a resent punch cannot be recorded twice.';

comment on column public.attendance_punches.arena_id is 'Owning arena (tenant).';

comment on column public.attendance_punches.staff_id is 'The staff profile that clocked in or out.';

comment on column public.attendance_punches.kind is '''in'' or ''out''.';

comment on column public.attendance_punches.server_at is 'Server time the punch was received: the only time worked hours are computed from.';

comment on column public.attendance_punches.device_at is 'The phone''s own clock at the punch; evidence only, never used for hours or pay.';

comment on column public.attendance_punches.via is 'How the punch was made: own_device (the staff member''s signed-in phone). Registered arena tablets (kiosk) come later.';

comment on column public.attendance_punches.device_id is 'Install id of the device (the app''s sync device id).';

comment on column public.attendance_punches.lat is 'Latitude of the fix in degrees (WGS84); null when no position was captured.';

comment on column public.attendance_punches.lng is 'Longitude of the fix in degrees (WGS84); null when no position was captured.';

comment on column public.attendance_punches.accuracy_m is 'Horizontal accuracy of the fix in metres, as the phone reported it.';

comment on column public.attendance_punches.is_mocked is 'True when the phone reported a mock (fake) location; null when the platform could not tell.';

comment on column public.attendance_punches.location_status is 'ok (a fix was captured), denied (permission refused), gps_off (location services off), timeout (no fix in time) or unavailable.';

comment on column public.attendance_punches.distance_m is 'Distance from the geofence centre in whole metres; null without a fix or a geofence.';

comment on column public.attendance_punches.geofence is 'Server verdict: inside, outside, or unknown (no fix, accuracy too poor, or no geofence set).';

comment on column public.attendance_punches.geofence_snapshot is 'The attendance rules applied to this punch: {geofence, outside_rule, min_accuracy_m, mock_rule}.';

comment on column public.attendance_punches.flags is 'Why the punch needs a look: outside, unknown, low_accuracy, no_geofence, mock.';

comment on column public.attendance_punches.created_by is 'auth.users id of the login that sent the punch.';

alter table "public"."attendance_punches"
  enable row level security;

create index ix_attendance_punches_staff on public.attendance_punches using btree (staff_id, server_at);

create index ix_attendance_punches_arena_time on public.attendance_punches using btree (arena_id, server_at);

-- Foreign-key index (joins and cascading deletes).
create index ix_attendance_punches_created_by on public.attendance_punches using btree (created_by);

create trigger t_same_arena
  before insert or update on public.attendance_punches
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- Append-only: corrections are new rows (_append_only).
create trigger t_attendance_punches_append_only
  before update or delete on public.attendance_punches
  for each row
  execute function public._append_only();

-- A member reads their own punches; attendance_review (or an owner) reads everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_attendance_punches" on "public"."attendance_punches"
  for select
  to authenticated
  using (((arena_id in ( select private.app_arena_ids_with(ARRAY['attendance_review'::text]) as app_arena_ids_with))
    or (staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."attendance_punches"
  to "postgres", "service_role";

revoke all on table "public"."attendance_punches" from "anon";

revoke all on table "public"."attendance_punches" from "authenticated";

grant select on table "public"."attendance_punches" to "authenticated";
