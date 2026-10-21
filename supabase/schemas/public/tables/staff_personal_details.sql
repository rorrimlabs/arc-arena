-- staff_personal_details — a staff member's own contact, address and emergency details
--
-- One optional row per staff profile, every field optional (nothing is asked at invite).
-- Written by op_staff_details_save (staff_details.save): the person themselves (floor app,
-- My profile) or an owner-level member (admin web, Team › Profile). Read by the person and by
-- owner level only; other staff never see it. Not in sync_pull: the apps read it online.
create table "public"."staff_personal_details" (
  "staff_id"           uuid                     not null,
  "arena_id"           uuid                     not null,
  "phone"              text,
  "email"              text,
  "birth_date"         date,
  "blood_group"        text,
  "address_line1"      text,
  "address_line2"      text,
  "city"               text,
  "state"              text,
  "pin_code"           text,
  "emergency_name"     text,
  "emergency_relation" text,
  "emergency_phone"    text,
  "updated_by"         uuid,
  "created_at"         timestamp with time zone not null default now(),
  "updated_at"         timestamp with time zone not null default now(),
  constraint "staff_personal_details_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_personal_details_blood_group_check" check (((blood_group IS NULL) OR (blood_group = ANY (ARRAY['A+'::text, 'A-'::text, 'B+'::text, 'B-'::text, 'AB+'::text, 'AB-'::text, 'O+'::text, 'O-'::text])))),
  constraint "staff_personal_details_email_check" check (((email IS NULL) OR ((char_length(email) <= 254) AND (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text)))),
  constraint "staff_personal_details_lengths_check" check (((char_length(address_line1) <= 200) AND (char_length(address_line2) <= 200) AND (char_length(city) <= 80) AND (char_length(state) <= 80) AND (char_length(emergency_name) <= 80) AND (char_length(emergency_relation) <= 40))),
  constraint "staff_personal_details_phones_check" check ((((phone IS NULL) OR (phone ~ '^\+?[0-9][0-9 -]{5,18}[0-9]$'::text)) AND ((emergency_phone IS NULL) OR (emergency_phone ~ '^\+?[0-9][0-9 -]{5,18}[0-9]$'::text)))),
  constraint "staff_personal_details_pin_code_check" check (((pin_code IS NULL) OR (pin_code ~ '^[1-9][0-9]{5}$'::text))),
  constraint "staff_personal_details_pkey" primary key (staff_id),
  constraint "staff_personal_details_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id),
  constraint "staff_personal_details_updated_by_fkey" foreign key (updated_by) references auth.users(id) on delete set null
);

comment on table public.staff_personal_details is 'Optional personal details per staff profile (contact, date of birth, blood group, address, emergency contact), kept by the person and owner level only.';

comment on column public.staff_personal_details.phone is 'Personal phone number: digits, spaces or dashes, optional leading +.';

comment on column public.staff_personal_details.email is 'Personal e-mail (not the login e-mail).';

comment on column public.staff_personal_details.pin_code is 'Indian postal PIN code, six digits.';

comment on column public.staff_personal_details.updated_by is 'Auth user who last saved the row (the person, or an owner correcting it).';

alter table "public"."staff_personal_details"
  enable row level security;

create index ix_staff_personal_details_arena on public.staff_personal_details using btree (arena_id);

create index ix_staff_personal_details_updated_by on public.staff_personal_details using btree (updated_by);

create trigger t_staff_personal_details_updated
  before update on public.staff_personal_details
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.staff_personal_details
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- A member reads their own row; owner level (role owner, money or reports) reads everyone's.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_personal_details" on "public"."staff_personal_details"
  for select
  to authenticated
  using (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in ( select private.app_arena_ids_with(ARRAY['money'::text, 'reports'::text]) as app_arena_ids_with))));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_personal_details"
  to "postgres", "service_role";

revoke all on table "public"."staff_personal_details" from "anon";

revoke all on table "public"."staff_personal_details" from "authenticated";

grant select on table "public"."staff_personal_details" to "authenticated";
