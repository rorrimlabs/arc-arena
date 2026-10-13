set local check_function_bodies = off;

alter table "public"."customers"
  add column "birth_year" smallint;

create or replace function public._floor_options (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  v_methods text[];
  v_presets int[];
  v_warn    numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('payment_methods', 'start_presets', 'warn_minutes')) then
    raise exception 'invalid_floor_options'
      using hint = 'an object of payment_methods, start_presets and warn_minutes';
  end if;

  if jsonb_typeof(p->'payment_methods') is distinct from 'array' then
    raise exception 'invalid_floor_options' using hint = 'payment_methods';
  end if;
  select array_agg(distinct m order by m) into v_methods
    from jsonb_array_elements_text(p->'payment_methods') m;
  if v_methods is null or not (v_methods <@ array['cash', 'upi', 'card', 'other']) then
    raise exception 'invalid_floor_options'
      using hint = 'payment_methods: one or more of cash, upi, card, other';
  end if;

  if jsonb_typeof(p->'start_presets') is distinct from 'array'
     or exists (select 1 from jsonb_array_elements(p->'start_presets') e
                 where jsonb_typeof(e) <> 'number' or (e::text)::numeric % 1 <> 0) then
    raise exception 'invalid_floor_options' using hint = 'start_presets: whole minutes';
  end if;
  select array_agg(distinct (e::text)::int order by (e::text)::int) into v_presets
    from jsonb_array_elements(p->'start_presets') e;
  if v_presets is null or cardinality(v_presets) > 8
     or exists (select 1 from unnest(v_presets) x where x < 5 or x > 720) then
    raise exception 'invalid_floor_options'
      using hint = 'start_presets: 1–8 durations of 5–720 minutes';
  end if;

  if jsonb_typeof(p->'warn_minutes') is distinct from 'number' then
    raise exception 'invalid_floor_options' using hint = 'warn_minutes';
  end if;
  v_warn := (p->>'warn_minutes')::numeric;
  if v_warn % 1 <> 0 or v_warn < 1 or v_warn > 30 then
    raise exception 'invalid_floor_options' using hint = 'warn_minutes: 1–30';
  end if;

  return jsonb_build_object('payment_methods', to_jsonb(v_methods),
    'start_presets', to_jsonb(v_presets), 'warn_minutes', v_warn::int);
end;
$function$;

revoke all on function "public"."_floor_options"(jsonb) from public, "anon", "authenticated";

create or replace function public.op_customer_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_phone text := nullif(btrim(p->>'phone'), '');
  v_other uuid;
begin
  if not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  -- A phone already in use (two devices registering the same person offline) must not sink
  -- the sessions that reference this customer: keep the row phone-less and audit the clash.
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from v_now at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  if v_phone is not null then
    select id into v_other from customers where arena_id = p_arena and phone = v_phone;
  end if;
  insert into customers(id, arena_id, name, phone, notes, last_visit_at, is_guest, created_at, updated_at,
      birth_year)
    values ((p->>'id')::uuid, p_arena, p->>'name', case when v_other is null then v_phone end,
      p->>'notes', (p->>'last_visit_at')::timestamptz, coalesce((p->>'is_guest')::boolean, false),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now, (p->>'birth_year')::smallint);
  if v_other is not null then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
      values (p_arena, 'customer', (p->>'id')::uuid, 'duplicate_phone_on_sync',
        'phone already belongs to another customer', jsonb_build_object('phone', v_phone,
        'existing_customer_id', v_other), auth.uid(), v_now);
    return jsonb_build_object('adjusted', true, 'phone_taken_by', v_other);
  end if;
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_customer_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8;
begin
  if not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from statement_timestamp() at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  select sync_xid into v_xid from customers where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'customer'; end if;
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the customer was edited on another device';
  end if;
  begin
    update customers set name = p->>'name', phone = nullif(btrim(p->>'phone'), ''),
        notes = p->>'notes',
        -- Builds that do not send birth_year keep the stored one.
        birth_year = case when p ? 'birth_year' then (p->>'birth_year')::smallint else birth_year end,
        updated_at = statement_timestamp()
      where id = (p->>'id')::uuid;
  exception when unique_violation then
    raise exception 'phone_taken';
  end;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_settings_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_json jsonb := p->'json';
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours', 'floor_options') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

alter table "public"."customers"
  add constraint "customers_birth_year_check"
    check (((birth_year >= 1900) AND (birth_year <= 2100)));

comment on column "public"."customers"."birth_year" is 'Year of birth given at registration, for age checks (age ratings); null when not given. Written by customer.create / customer.update only when the key is sent; ops refuse a future year.';

comment on column "public"."settings"."json" is 'Setting value. business_hours: {"open": {...}, "happy": {...}}, each keyed by ISO weekday "1" (Monday) to "7", value {"start": m, "end": m} in minutes after IST midnight, or null when closed / no happy hour. floor_options: {"payment_methods": [...], "start_presets": [minutes...], "warn_minutes": n}.';

comment on column "public"."settings"."key" is 'Setting name, unique per arena. Writable: business_hours, floor_options.';

comment on function "public"."_floor_options"(jsonb) is 'Validates and normalises the floor_options setting (payment methods offered, session start presets, end-of-session warning minutes); raises invalid_floor_options.';

comment on table "public"."settings" is 'Per-arena key/value settings synced to devices. Writable through settings.save: business_hours and floor_options.';

revoke all on function "public"."_floor_options"(jsonb) from "postgres";

grant execute on function "public"."_floor_options"(jsonb) to "postgres";

grant execute on function "public"."_floor_options"(jsonb) to "service_role";
