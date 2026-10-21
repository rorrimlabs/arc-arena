-- op_staff_details_save — sync op 'staff_details.save': a staff member's personal details
--
-- Permission: the person themselves (their active profile in the arena), or owner level
--   (app_is_owner: role owner, or holds money or reports) for anyone in the arena.
-- Payload: staff_id? (default: the caller's own profile), and any of phone, email, birth_date
--   (YYYY-MM-DD), blood_group (A+ A- B+ B- AB+ AB- O+ O-), address_line1, address_line2, city,
--   state, pin_code (six digits), emergency_name, emergency_relation, emergency_phone. Text is
--   trimmed; a key left out keeps its value, and an empty string or null clears it. Every field
--   is optional.
-- Checks / errors: not_found (hint staff); forbidden (someone else's details without owner
--   level); invalid_payload (hint names the field: phone / emergency_phone: 7-20 digits, spaces
--   or dashes, optional leading +; email; birth_date: from 1900 to today (IST); blood_group;
--   pin_code; the text lengths).
-- Writes: staff_personal_details (upsert, updated_by = the caller). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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

comment on function public.op_staff_details_save(uuid, jsonb) is 'Sync op staff_details.save: a staff member''s optional personal details (contact, date of birth, blood group, address, emergency contact), saved by the person or owner level.';

grant execute on function "public"."op_staff_details_save"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_staff_details_save"(uuid, jsonb) from public;

revoke all on function "public".op_staff_details_save(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_staff_details_save(p_arena uuid, p jsonb) from authenticated;
