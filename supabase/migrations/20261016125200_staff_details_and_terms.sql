set local check_function_bodies = off;

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
  constraint "staff_personal_details_blood_group_check"
    check
    (((blood_group IS NULL) OR (blood_group = ANY (ARRAY['A+'::text, 'A-'::text, 'B+'::text,
    'B-'::text, 'AB+'::text, 'AB-'::text, 'O+'::text, 'O-'::text])))),
  constraint "staff_personal_details_email_check"
    check
    (((email IS NULL) OR ((char_length(email) <= 254) AND (email ~
    '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text)))),
  constraint "staff_personal_details_lengths_check"
    check
    (((char_length(address_line1) <= 200) AND (char_length(address_line2) <= 200) AND
    (char_length(city) <= 80) AND (char_length(state) <= 80) AND (char_length(emergency_name) <= 80)
    AND (char_length(emergency_relation) <= 40))),
  constraint "staff_personal_details_phones_check"
    check
    ((((phone IS NULL) OR (phone ~ '^\+?[0-9][0-9 -]{5,18}[0-9]$'::text)) AND ((emergency_phone IS
    NULL) OR (emergency_phone ~ '^\+?[0-9][0-9 -]{5,18}[0-9]$'::text)))),
  constraint "staff_personal_details_pin_code_check"
    check (((pin_code IS NULL) OR (pin_code ~ '^[1-9][0-9]{5}$'::text))),
  constraint "staff_personal_details_pkey" primary key (staff_id)
);

alter table "public"."staff_personal_details"
  enable row level security;

create table "public"."staff_terms_acceptances" (
  "id"          uuid                     not null default gen_random_uuid(),
  "arena_id"    uuid                     not null,
  "staff_id"    uuid                     not null,
  "terms_id"    uuid                     not null,
  "accepted_at" timestamp with time zone not null default now(),
  "device_at"   timestamp with time zone,
  constraint "staff_terms_acceptances_pkey" primary key (id),
  constraint "staff_terms_acceptances_staff_id_terms_id_key" unique (staff_id, terms_id)
);

alter table "public"."staff_terms_acceptances"
  enable row level security;

create table "public"."staff_terms" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "version"      integer                  not null,
  "title"        text                     not null,
  "body"         text                     not null,
  "published_by" uuid,
  "published_at" timestamp with time zone not null default now(),
  constraint "staff_terms_arena_id_version_key" unique (arena_id, version),
  constraint "staff_terms_body_check"
    check (((btrim(body) <> ''::text) AND (char_length(body) <= 50000))),
  constraint "staff_terms_pkey" primary key (id),
  constraint "staff_terms_title_check"
    check (((btrim(title) <> ''::text) AND (char_length(title) <= 120))),
  constraint "staff_terms_version_check" check ((version >= 1))
);

alter table "public"."staff_terms"
  enable row level security;

create or replace function public._sync_apply (
  p_arena uuid,
  p_kind  text,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_before jsonb; v_res jsonb;
begin
  -- A price-list change retires the previous catalog into
  -- pricing_catalog_history, so a session priced on it still validates.
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove',
                'rule.upsert', 'rule.delete', 'rule.reorder') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;

  -- Dispatch: one op kind -> one op_* function. Unknown kinds return null and
  -- sync_push rejects them.
  v_res := case p_kind
      when 'session.start'        then op_session_start(p_arena, p)
      when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
      when 'session.extend'       then op_session_extend(p_arena, p)
      when 'session.end'          then op_session_end(p_arena, p)
      when 'session.void'         then op_session_void(p_arena, p)
      when 'payment.record'       then op_payment(p_arena, p)
      when 'payment.correct'      then op_payment_correct(p_arena, p)
      when 'group.create'         then op_group_create(p_arena, p)
      when 'group.add'            then op_group_add(p_arena, p)
      when 'group.switch'         then op_group_switch(p_arena, p)
      when 'group.end_player'     then op_group_end_player(p_arena, p)
      when 'group.extend'         then op_group_extend(p_arena, p)
      when 'group.end'            then op_group_end(p_arena, p)
      when 'group.void'           then op_group_void(p_arena, p)
      when 'controller.move'      then op_controller_move(p_arena, p)
      when 'controller.upsert'    then op_controller_upsert(p_arena, p)
      when 'controller.set_status' then op_controller_set_status(p_arena, p)
      when 'accessory_kind.upsert' then op_accessory_kind_upsert(p_arena, p)
      when 'accessory_kind.remove' then op_accessory_kind_remove(p_arena, p)
      when 'customer.create'      then op_customer_create(p_arena, p)
      when 'customer.update'      then op_customer_update(p_arena, p)
      when 'booking.create'       then op_booking_create(p_arena, p)
      when 'booking.update'       then op_booking_update(p_arena, p)
      when 'booking.set_status'   then op_booking_set_status(p_arena, p)
      when 'game.upsert'          then op_game_upsert(p_arena, p)
      when 'game.set_active'      then op_game_set_active(p_arena, p)
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'rule.upsert'          then op_rule_upsert(p_arena, p)
      when 'rule.delete'          then op_rule_delete(p_arena, p)
      when 'rule.reorder'         then op_rule_reorder(p_arena, p)
      when 'discount.upsert'      then op_discount_upsert(p_arena, p)
      when 'discount.set_active'  then op_discount_set_active(p_arena, p)
      when 'discount.delete'      then op_discount_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      when 'attendance.punch'     then op_attendance_punch(p_arena, p)
      when 'attendance.correct'   then op_attendance_correct(p_arena, p)
      when 'attendance.review'    then op_attendance_review(p_arena, p)
      when 'shift.upsert'         then op_shift_upsert(p_arena, p)
      when 'shift.assign'         then op_shift_assign(p_arena, p)
      when 'shift.unassign'       then op_shift_unassign(p_arena, p)
      when 'staff_holiday.upsert' then op_staff_holiday_upsert(p_arena, p)
      when 'staff_holiday.delete' then op_staff_holiday_delete(p_arena, p)
      when 'hr_profile.save'      then op_hr_profile_save(p_arena, p)
      when 'staff_details.save'   then op_staff_details_save(p_arena, p)
      when 'terms.publish'        then op_terms_publish(p_arena, p)
      when 'terms.accept'         then op_terms_accept(p_arena, p)
      when 'leave.request'        then op_leave_request(p_arena, p)
      when 'leave.cancel'         then op_leave_cancel(p_arena, p)
      when 'leave.decide'         then op_leave_decide(p_arena, p)
      when 'leave.adjust'         then op_leave_adjust(p_arena, p)
      when 'leave.record'         then op_leave_record(p_arena, p)
      when 'pay_rate.add'         then op_pay_rate_add(p_arena, p)
      when 'pay_policy.add'       then op_pay_policy_add(p_arena, p)
      when 'salary_run.create'    then op_salary_run_create(p_arena, p)
      when 'salary_run.recalculate' then op_salary_run_recalculate(p_arena, p)
      when 'salary_run.set_deduction' then op_salary_run_set_deduction(p_arena, p)
      when 'salary_run.finalise'  then op_salary_run_finalise(p_arena, p)
      when 'salary_run.discard'   then op_salary_run_discard(p_arena, p)
      when 'salary_adjustment.add' then op_salary_adjustment_add(p_arena, p)
      when 'salary_adjustment.reverse' then op_salary_adjustment_reverse(p_arena, p)
      else null
    end;

  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$function$;

create or replace function public.op_staff_details_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  c_fields constant text[] := array['phone', 'email', 'birth_date', 'blood_group', 'address_line1',
    'address_line2', 'city', 'state', 'pin_code', 'emergency_name', 'emergency_relation',
    'emergency_phone'];
  c_phone  constant text := '^\+?[0-9][0-9 -]{5,18}[0-9]$';
  v_today  date := _pr_ist_date(statement_timestamp());
  v_own    uuid;
  v_staff  uuid;
  v_patch  jsonb;
  v_old    staff_personal_details;
  v_new    staff_personal_details;
begin
  select id into v_own from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active;
  v_staff := coalesce(nullif(p->>'staff_id', '')::uuid, v_own);
  if v_staff is null
     or not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if v_staff is distinct from v_own and not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'only the person or an owner changes these details';
  end if;

  -- Only the known keys, trimmed, blank as null; the stored row supplies the rest.
  select coalesce(jsonb_object_agg(key, nullif(btrim(value), '')), '{}'::jsonb) into v_patch
    from jsonb_each_text(p) where key = any(c_fields);
  if v_patch ? 'blood_group' then
    v_patch := v_patch || jsonb_build_object('blood_group', upper(v_patch->>'blood_group'));
  end if;
  if v_patch->>'birth_date' is not null and v_patch->>'birth_date' !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'invalid_payload' using hint = 'birth_date: YYYY-MM-DD';
  end if;

  select * into v_old from staff_personal_details where staff_id = v_staff for update;
  v_new := jsonb_populate_record(v_old, v_patch);
  v_new.staff_id := v_staff;
  v_new.arena_id := p_arena;
  v_new.updated_by := auth.uid();

  if v_new.phone !~ c_phone then
    raise exception 'invalid_payload' using hint = 'phone: 7-20 digits';
  end if;
  if v_new.emergency_phone !~ c_phone then
    raise exception 'invalid_payload' using hint = 'emergency_phone: 7-20 digits';
  end if;
  if char_length(v_new.email) > 254 or v_new.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_payload' using hint = 'email';
  end if;
  if v_new.birth_date < date '1900-01-01' or v_new.birth_date > v_today then
    raise exception 'invalid_payload' using hint = 'birth_date: from 1900 to today';
  end if;
  if v_new.blood_group <> all (array['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']) then
    raise exception 'invalid_payload' using hint = 'blood_group';
  end if;
  if v_new.pin_code !~ '^[1-9][0-9]{5}$' then
    raise exception 'invalid_payload' using hint = 'pin_code: six digits';
  end if;
  if char_length(v_new.address_line1) > 200 or char_length(v_new.address_line2) > 200 then
    raise exception 'invalid_payload' using hint = 'address: at most 200 characters a line';
  end if;
  if char_length(v_new.city) > 80 or char_length(v_new.state) > 80 then
    raise exception 'invalid_payload' using hint = 'city / state: at most 80 characters';
  end if;
  if char_length(v_new.emergency_name) > 80 or char_length(v_new.emergency_relation) > 40 then
    raise exception 'invalid_payload' using hint = 'emergency contact: name 80, relation 40 characters';
  end if;

  insert into staff_personal_details(staff_id, arena_id, phone, email, birth_date, blood_group,
      address_line1, address_line2, city, state, pin_code, emergency_name, emergency_relation,
      emergency_phone, updated_by)
    values (v_new.staff_id, v_new.arena_id, v_new.phone, v_new.email, v_new.birth_date,
      v_new.blood_group, v_new.address_line1, v_new.address_line2, v_new.city, v_new.state,
      v_new.pin_code, v_new.emergency_name, v_new.emergency_relation, v_new.emergency_phone,
      v_new.updated_by)
  on conflict (staff_id) do update set phone = excluded.phone, email = excluded.email,
      birth_date = excluded.birth_date, blood_group = excluded.blood_group,
      address_line1 = excluded.address_line1, address_line2 = excluded.address_line2,
      city = excluded.city, state = excluded.state, pin_code = excluded.pin_code,
      emergency_name = excluded.emergency_name, emergency_relation = excluded.emergency_relation,
      emergency_phone = excluded.emergency_phone, updated_by = excluded.updated_by;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_terms_accept (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id     uuid := nullif(p->>'id', '')::uuid;
  v_terms  uuid := nullif(p->>'terms_id', '')::uuid;
  v_staff  uuid;
  v_latest uuid;
  v_device timestamptz;
  v_at     timestamptz;
begin
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  begin
    v_device := nullif(p->>'device_at', '')::timestamptz;
  exception when others then
    raise exception 'invalid_payload' using hint = 'device_at';
  end;
  if v_terms is null or not exists (select 1 from staff_terms where id = v_terms and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'terms';
  end if;

  select accepted_at into v_at from staff_terms_acceptances
    where staff_id = v_staff and terms_id = v_terms;
  if found then return jsonb_build_object('accepted_at', v_at); end if;

  select id into v_latest from staff_terms where arena_id = p_arena order by version desc limit 1;
  if v_latest <> v_terms then
    raise exception 'stale' using hint = 'a newer version of the terms was published';
  end if;

  insert into staff_terms_acceptances(id, arena_id, staff_id, terms_id, accepted_at, device_at)
    values (v_id, p_arena, v_staff, v_terms, statement_timestamp(), v_device)
    returning accepted_at into v_at;
  return jsonb_build_object('accepted_at', v_at);
end;
$function$;

create or replace function public.op_terms_publish (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id      uuid := nullif(p->>'id', '')::uuid;
  v_title   text := btrim(coalesce(p->>'title', ''));
  v_body    text := btrim(coalesce(p->>'body', ''));
  v_version integer;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'terms are owner-only';
  end if;
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if v_title = '' or char_length(v_title) > 120 then
    raise exception 'invalid_payload' using hint = 'title: 1 to 120 characters';
  end if;
  if v_body = '' or char_length(v_body) > 50000 then
    raise exception 'invalid_payload' using hint = 'body: 1 to 50,000 characters';
  end if;
  if exists (select 1 from staff_terms where id = v_id) then
    raise exception 'duplicate' using hint = 'id';
  end if;

  -- Two publishes at once queue here, so versions never collide.
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text || ':staff_terms', 0));
  select coalesce(max(version), 0) + 1 into v_version from staff_terms where arena_id = p_arena;
  insert into staff_terms(id, arena_id, version, title, body, published_by, published_at)
    values (v_id, p_arena, v_version, v_title, v_body, auth.uid(), statement_timestamp());
  return jsonb_build_object('version', v_version);
end;
$function$;

alter table "public"."staff_personal_details"
  add constraint "staff_personal_details_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."staff_personal_details"
  add constraint "staff_personal_details_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."staff_personal_details"
  add constraint "staff_personal_details_updated_by_fkey" foreign key (updated_by)
    references auth.users(id) on delete set null;

alter table "public"."staff_terms"
  add constraint "staff_terms_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_terms"
  add constraint "staff_terms_published_by_fkey" foreign key (published_by)
    references auth.users(id) on delete set null;

alter table "public"."staff_terms_acceptances"
  add constraint "staff_terms_acceptances_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."staff_terms_acceptances"
  add constraint "staff_terms_acceptances_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."staff_terms_acceptances"
  add constraint "staff_terms_acceptances_terms_id_fkey" foreign key (terms_id)
    references public.staff_terms(id) on delete cascade;

create index ix_staff_personal_details_arena on public.staff_personal_details using btree (arena_id);

create index ix_staff_personal_details_updated_by on public.staff_personal_details
  using btree (updated_by);

create index ix_staff_terms_acceptances_arena on public.staff_terms_acceptances
  using btree (arena_id);

create index ix_staff_terms_acceptances_terms on public.staff_terms_acceptances
  using btree (terms_id);

create index ix_staff_terms_published_by on public.staff_terms using btree (published_by);

create trigger t_same_arena
  before insert or update on public.staff_personal_details
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create trigger t_staff_personal_details_updated
  before update on public.staff_personal_details
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.staff_terms_acceptances
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create policy "p_sel_staff_personal_details" on "public"."staff_personal_details"
  for select
  to "authenticated"
  using
    (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in (
    select private.app_arena_ids_with(ARRAY['money'::text, 'reports'::text]) as
    app_arena_ids_with))));

create policy "p_sel_staff_terms" on "public"."staff_terms"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_staff_terms_acceptances" on "public"."staff_terms_acceptances"
  for select
  to "authenticated"
  using
    (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in (
    select private.app_arena_ids_with(ARRAY['money'::text, 'reports'::text]) as
    app_arena_ids_with))));

comment on column "public"."staff_personal_details"."email" is 'Personal e-mail (not the login e-mail).';

comment on column "public"."staff_personal_details"."phone" is 'Personal phone number: digits, spaces or dashes, optional leading +.';

comment on column "public"."staff_personal_details"."pin_code" is 'Indian postal PIN code, six digits.';

comment on column "public"."staff_personal_details"."updated_by" is 'Auth user who last saved the row (the person, or an owner correcting it).';

comment on column "public"."staff_terms"."body" is 'The full text (plain text, paragraphs separated by blank lines), at most 50,000 characters.';

comment on column "public"."staff_terms"."published_at" is 'Server time the version was published.';

comment on column "public"."staff_terms"."version" is 'Per-arena version number, 1 for the first; a new version asks everyone to accept again.';

comment on column "public"."staff_terms_acceptances"."accepted_at" is 'Server time of the acceptance.';

comment on column "public"."staff_terms_acceptances"."device_at" is 'The device clock at acceptance; evidence only, never used for rules.';

comment on function "public"."op_staff_details_save"(uuid, jsonb) is 'Sync op staff_details.save: a staff member''s optional personal details (contact, date of birth, blood group, address, emergency contact), saved by the person or owner level.';

comment on function "public"."op_terms_accept"(uuid, jsonb) is 'Sync op terms.accept: records that the caller accepted the latest version of the staff terms (server time; device time as evidence).';

comment on function "public"."op_terms_publish"(uuid, jsonb) is 'Sync op terms.publish: adds the next version of the venue''s staff terms (owner level); everyone else accepts it again.';

comment on table "public"."staff_personal_details" is 'Optional personal details per staff profile (contact, date of birth, blood group, address, emergency contact), kept by the person and owner level only.';

comment on table "public"."staff_terms" is 'Append-only versions of a venue''s terms and conditions for staff; the highest version is in force and every member must accept it.';

comment on table "public"."staff_terms_acceptances" is 'Append-only record of each member accepting a version of the staff terms (server time, with the device clock as evidence).';

revoke all on function "public"."op_staff_details_save"(uuid, jsonb) from public;

grant execute
  on function "public"."op_staff_details_save"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_terms_accept"(uuid, jsonb) from public;

grant execute on function "public"."op_terms_accept"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_terms_publish"(uuid, jsonb) from public;

grant execute on function "public"."op_terms_publish"(uuid, jsonb) to "postgres", "service_role";

grant select on table "public"."staff_personal_details" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_personal_details"
  to "postgres", "service_role";

grant select on table "public"."staff_terms" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_terms"
  to "postgres", "service_role";

grant select on table "public"."staff_terms_acceptances" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_terms_acceptances"
  to "postgres", "service_role";
