set local check_function_bodies = off;

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
  constraint "attendance_entries_order_check" check (((out_at IS NULL) OR (out_at > in_at))),
  constraint "attendance_entries_out_source_check"
    check
    ((((out_at IS NULL) = (out_source IS NULL)) AND ((out_source IS NULL) OR (out_source = ANY
    (ARRAY['punch'::text, 'auto'::text, 'manual'::text]))))),
  constraint "attendance_entries_pkey" primary key (id),
  constraint "attendance_entries_reason_check"
    check ((((source = 'punch'::text) AND (replaces_id IS NULL)) OR (reason IS NOT NULL))),
  constraint "attendance_entries_review_check"
    check
    ((review = ANY (ARRAY['none'::text, 'pending'::text, 'accepted'::text, 'corrected'::text]))),
  constraint "attendance_entries_source_check"
    check ((source = ANY (ARRAY['punch'::text, 'manual'::text]))),
  constraint "attendance_entries_status_check"
    check ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'voided'::text])))
);

alter table "public"."attendance_entries"
  enable row level security;

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
  constraint "attendance_punches_device_id_check" check ((btrim(device_id) <> ''::text)),
  constraint "attendance_punches_geofence_check"
    check ((geofence = ANY (ARRAY['inside'::text, 'outside'::text, 'unknown'::text]))),
  constraint "attendance_punches_kind_check" check ((kind = ANY (ARRAY['in'::text, 'out'::text]))),
  constraint "attendance_punches_latlng_check"
    check
    ((((lat IS NULL) = (lng IS NULL)) AND ((lat IS NULL) = (accuracy_m IS NULL)) AND ((lat IS NULL)
    OR
    ((lat >= ('-90'::integer)::double precision) AND (lat <= (90)::double precision) AND (lng >=
    ('-180'::integer)::double precision) AND (lng <= (180)::double precision) AND
    (accuracy_m >= (0)::numeric))))),
  constraint "attendance_punches_location_status_check"
    check
    ((location_status = ANY (ARRAY['ok'::text, 'denied'::text, 'gps_off'::text, 'timeout'::text,
    'unavailable'::text]))),
  constraint "attendance_punches_ok_has_fix_check" check (((location_status = 'ok'::text) = (lat IS
    NOT NULL))),
  constraint "attendance_punches_pkey" primary key (id),
  constraint "attendance_punches_via_check" check ((via = 'own_device'::text))
);

alter table "public"."attendance_punches"
  enable row level security;

create or replace function private.app_my_staff_ids()
  returns SETOF uuid
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select id from staff_profiles where user_id = auth.uid() and active;
$function$;

create or replace function public._attendance_rules (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('geofence', null, 'outside_rule', 'flag', 'min_accuracy_m', 50,
                            'mock_rule', 'block', 'max_open_hours', 14)
      || coalesce((select json from settings where arena_id = p_arena and key = 'attendance'),
                  '{}'::jsonb);
$function$;

create or replace function public._attendance_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  v_fence  jsonb := p->'geofence';
  v_lat    numeric; v_lng numeric; v_radius numeric;
  v_acc    numeric; v_open numeric;
  v_outside text := p->>'outside_rule';
  v_mock    text := p->>'mock_rule';
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('geofence', 'outside_rule', 'min_accuracy_m', 'mock_rule',
                                 'max_open_hours'))
     or not (p ?& array['geofence', 'outside_rule', 'min_accuracy_m', 'mock_rule',
                        'max_open_hours']) then
    raise exception 'invalid_attendance_settings'
      using hint = 'an object of geofence, outside_rule, min_accuracy_m, mock_rule and max_open_hours';
  end if;

  if jsonb_typeof(v_fence) = 'null' then
    v_fence := null;
  elsif jsonb_typeof(v_fence) = 'object'
        and not exists (select 1 from jsonb_object_keys(v_fence) k where k not in ('lat', 'lng', 'radius_m'))
        and jsonb_typeof(v_fence->'lat') = 'number' and jsonb_typeof(v_fence->'lng') = 'number'
        and jsonb_typeof(v_fence->'radius_m') = 'number' then
    v_lat := (v_fence->>'lat')::numeric;
    v_lng := (v_fence->>'lng')::numeric;
    v_radius := (v_fence->>'radius_m')::numeric;
    if v_lat < -90 or v_lat > 90 or v_lng < -180 or v_lng > 180 then
      raise exception 'invalid_attendance_settings' using hint = 'geofence: lat -90..90, lng -180..180';
    end if;
    if v_radius % 1 <> 0 or v_radius < 20 or v_radius > 5000 then
      raise exception 'invalid_attendance_settings' using hint = 'geofence.radius_m: 20–5000 metres';
    end if;
    v_fence := jsonb_build_object('lat', round(v_lat, 6), 'lng', round(v_lng, 6),
                                  'radius_m', v_radius::int);
  else
    raise exception 'invalid_attendance_settings' using hint = 'geofence: null or {lat, lng, radius_m}';
  end if;

  if v_outside is null or v_outside not in ('block', 'flag', 'allow') then
    raise exception 'invalid_attendance_settings' using hint = 'outside_rule: block, flag or allow';
  end if;
  if v_outside = 'block' and v_fence is null then
    raise exception 'invalid_attendance_settings'
      using hint = 'outside_rule block needs the arena location (geofence)';
  end if;

  if jsonb_typeof(p->'min_accuracy_m') is distinct from 'number' then
    raise exception 'invalid_attendance_settings' using hint = 'min_accuracy_m';
  end if;
  v_acc := (p->>'min_accuracy_m')::numeric;
  if v_acc % 1 <> 0 or v_acc < 5 or v_acc > 500 then
    raise exception 'invalid_attendance_settings' using hint = 'min_accuracy_m: 5–500 metres';
  end if;

  if v_mock is null or v_mock not in ('block', 'flag') then
    raise exception 'invalid_attendance_settings' using hint = 'mock_rule: block or flag';
  end if;

  if jsonb_typeof(p->'max_open_hours') is distinct from 'number' then
    raise exception 'invalid_attendance_settings' using hint = 'max_open_hours';
  end if;
  v_open := (p->>'max_open_hours')::numeric;
  if v_open % 1 <> 0 or v_open < 4 or v_open > 24 then
    raise exception 'invalid_attendance_settings' using hint = 'max_open_hours: 4–24 hours';
  end if;

  return jsonb_build_object('geofence', coalesce(v_fence, 'null'::jsonb), 'outside_rule', v_outside,
    'min_accuracy_m', v_acc::int, 'mock_rule', v_mock, 'max_open_hours', v_open::int);
end;
$function$;

create or replace function public._create_arena_with_owner (
  p_user       uuid,
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_arena uuid;
begin
  insert into arenas(name) values (coalesce(nullif(btrim(p_arena_name), ''), 'Arena'))
    returning id into v_arena;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, p_user, coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      _known_perms(), true);
  return v_arena;
end;
$function$;

create or replace function public._geo_distance_m (
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
  returns integer
  language sql
  immutable
  strict
  set search_path to 'public'
  AS $function$
  select round(2 * 6371008.8 * asin(least(1, sqrt(
           power(sin(radians(p_lat2 - p_lat1) / 2), 2)
         + cos(radians(p_lat1)) * cos(radians(p_lat2))
           * power(sin(radians(p_lng2 - p_lng1) / 2), 2)))))::int;
$function$;

create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings',
               'attendance_review'];
$function$;

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

create or replace function public.op_attendance_punch (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now      timestamptz := statement_timestamp();
  v_rules    jsonb := _attendance_rules(p_arena);
  v_fence    jsonb := nullif(v_rules->'geofence', 'null'::jsonb);
  v_rule     text  := v_rules->>'outside_rule';
  v_min_acc  int   := (v_rules->>'min_accuracy_m')::int;
  v_max_open interval := make_interval(hours => (v_rules->>'max_open_hours')::int);
  v_punch    uuid  := (p->>'punch_id')::uuid;
  v_kind     text  := p->>'kind';
  v_device   text  := nullif(btrim(p->>'device_id'), '');
  v_loc      jsonb := coalesce(p->'location', '{}'::jsonb);
  v_status   text  := v_loc->>'status';
  v_lat      double precision := (v_loc->>'lat')::double precision;
  v_lng      double precision := (v_loc->>'lng')::double precision;
  v_acc      numeric := (v_loc->>'accuracy_m')::numeric;
  v_mocked   boolean := (v_loc->>'is_mocked')::boolean;
  v_staff    uuid;
  v_dist     int;
  v_verdict  text;
  v_flags    text[] := '{}';
  v_review   text := 'none';
  v_open     attendance_entries;
  v_auto     uuid;
  v_entry    uuid;
begin
  -- Shape first: a malformed punch is refused before anything is looked up.
  if v_punch is null then raise exception 'invalid_payload' using hint = 'punch_id'; end if;
  if v_kind is null or v_kind not in ('in', 'out') then
    raise exception 'invalid_payload' using hint = 'kind: in or out';
  end if;
  if v_device is null then raise exception 'invalid_payload' using hint = 'device_id'; end if;
  if v_status is null or v_status not in ('ok', 'denied', 'gps_off', 'timeout', 'unavailable') then
    raise exception 'invalid_payload' using hint = 'location.status';
  end if;
  if (v_status = 'ok') <> (v_lat is not null and v_lng is not null and v_acc is not null) then
    raise exception 'invalid_payload' using hint = 'location: lat, lng and accuracy_m exactly when status is ok';
  end if;
  if v_status <> 'ok' then v_mocked := null; end if;

  -- The caller's own profile; locking it queues two punches from two of their devices.
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;

  -- Verdict against the rules in force now.
  if v_status <> 'ok' then
    v_verdict := 'unknown';
  elsif v_fence is null then
    v_verdict := 'unknown';
    v_flags := v_flags || 'no_geofence';
  else
    v_dist := _geo_distance_m(v_lat, v_lng, (v_fence->>'lat')::double precision,
                              (v_fence->>'lng')::double precision);
    if v_acc > v_min_acc then
      v_verdict := 'unknown';
      v_flags := v_flags || 'low_accuracy';
    elsif v_dist <= (v_fence->>'radius_m')::int then
      v_verdict := 'inside';
    else
      v_verdict := 'outside';
    end if;
  end if;

  if v_mocked then
    if v_rules->>'mock_rule' = 'block' then
      raise exception 'mock_location' using hint = 'the phone reported a mock (fake) location';
    end if;
    v_flags := v_flags || 'mock';
    v_review := 'pending';
  end if;

  if v_verdict <> 'inside' then
    if v_rule = 'block' then
      if v_verdict = 'outside' then
        raise exception 'outside_geofence'
          using hint = v_dist || ' m from the arena; the limit is ' || (v_fence->>'radius_m') || ' m';
      end if;
      raise exception 'location_required'
        using hint = case when v_status = 'denied' then 'location permission is off'
                          when v_status = 'gps_off' then 'location services are off'
                          when v_status in ('timeout', 'unavailable') then 'no location fix'
                          else 'location accuracy is ' || round(v_acc) || ' m; ' || v_min_acc
                               || ' m or better is needed' end;
    end if;
    v_flags := v_flags || v_verdict;
    if v_rule = 'flag' then v_review := 'pending'; end if;
  end if;

  -- The person's open stretch, closed automatically when it is older than max_open_hours.
  select * into v_open from attendance_entries
    where staff_id = v_staff and out_at is null and status = 'active' for update;
  if found and v_open.in_at + v_max_open < v_now then
    update attendance_entries
       set out_at = v_open.in_at + v_max_open, out_source = 'auto',
           flags = array(select distinct f from unnest(flags || '{auto_out}'::text[]) f order by f),
           review = 'pending'
     where id = v_open.id;
    v_auto := v_open.id;
  end if;

  if v_kind = 'in' and v_open.id is not null and v_auto is null then
    raise exception 'already_clocked_in'
      using hint = 'clocked in at ' || to_char(v_open.in_at at time zone 'Asia/Kolkata', 'HH24:MI DD Mon');
  end if;
  if v_kind = 'out' and v_open.id is null then
    raise exception 'not_clocked_in';
  end if;

  insert into attendance_punches(id, arena_id, staff_id, kind, server_at, device_at, device_id,
      lat, lng, accuracy_m, is_mocked, location_status, distance_m, geofence, geofence_snapshot,
      flags, created_by)
    values (v_punch, p_arena, v_staff, v_kind, v_now, (p->>'device_at')::timestamptz, v_device,
      v_lat, v_lng, v_acc, v_mocked, v_status, v_dist, v_verdict,
      jsonb_build_object('geofence', coalesce(v_fence, 'null'::jsonb), 'outside_rule', v_rule,
                         'min_accuracy_m', v_min_acc, 'mock_rule', v_rules->>'mock_rule'),
      v_flags, auth.uid());

  if v_kind = 'in' then
    insert into attendance_entries(arena_id, staff_id, work_date, in_at, in_punch_id, flags,
        review, created_by)
      values (p_arena, v_staff, _pr_ist_date(v_now), v_now, v_punch,
        array(select f || '_in' from unnest(v_flags) f order by f), v_review, auth.uid())
      returning id into v_entry;
  else
    -- On an automatic close the punch is kept on the row as evidence of when the person
    -- actually tapped; the stretch itself stays at in_at + max_open_hours.
    update attendance_entries
       set out_at = case when v_auto is null then v_now else out_at end,
           out_source = case when v_auto is null then 'punch' else out_source end,
           out_punch_id = v_punch,
           flags = array(select distinct f from unnest(flags || array(select f2 || '_out' from unnest(v_flags) f2)) f order by f),
           review = case when v_review = 'pending' then 'pending' else review end
     where id = v_open.id;
    v_entry := v_open.id;
  end if;

  return jsonb_build_object('punch_id', v_punch, 'entry_id', v_entry, 'kind', v_kind,
    'server_at', v_now, 'geofence', v_verdict, 'distance_m', v_dist, 'flags', to_jsonb(v_flags),
    'review', (select review from attendance_entries where id = v_entry),
    'auto_closed_entry_id', v_auto);
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
  if (p->>'key') not in ('business_hours', 'floor_options', 'discount_options', 'venue_profile',
                         'attendance') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  elsif p->>'key' = 'discount_options' then
    v_json := _discount_options(p->'json');
  elsif p->>'key' = 'venue_profile' then
    v_json := _venue_profile(p->'json');
  elsif p->>'key' = 'attendance' then
    v_json := _attendance_settings(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

alter table "public"."attendance_entries"
  add constraint "attendance_entries_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."attendance_entries"
  add constraint "attendance_entries_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."attendance_entries"
  add constraint "attendance_entries_no_overlap" EXCLUDE using gist (staff_id
    with =,
    tstzrange(in_at, COALESCE(out_at, 'infinity'::timestamp with time zone)) with &&)
    where ((status = 'active'::text));

alter table "public"."attendance_entries"
  add constraint "attendance_entries_replaces_id_fkey" foreign key (replaces_id)
    references public.attendance_entries(id);

alter table "public"."attendance_entries"
  add constraint "attendance_entries_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."attendance_punches"
  add constraint "attendance_punches_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."attendance_punches"
  add constraint "attendance_punches_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."attendance_entries"
  add constraint "attendance_entries_in_punch_id_fkey" foreign key (in_punch_id)
    references public.attendance_punches(id);

alter table "public"."attendance_entries"
  add constraint "attendance_entries_out_punch_id_fkey" foreign key (out_punch_id)
    references public.attendance_punches(id);

alter table "public"."attendance_punches"
  add constraint "attendance_punches_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

create index ix_attendance_entries_created_by on public.attendance_entries using btree (created_by);

create index ix_attendance_entries_day on public.attendance_entries
  using btree (arena_id, work_date);

create index ix_attendance_entries_in_punch on public.attendance_entries using btree (in_punch_id);

create index ix_attendance_entries_out_punch on public.attendance_entries using btree (out_punch_id);

create index ix_attendance_entries_replaces on public.attendance_entries using btree (replaces_id);

create index ix_attendance_entries_review on public.attendance_entries using btree (arena_id)
  where (review = 'pending'::text);

create index ix_attendance_entries_staff_day on public.attendance_entries
  using btree (staff_id, work_date);

create index ix_attendance_punches_arena_time on public.attendance_punches
  using btree (arena_id, server_at);

create index ix_attendance_punches_created_by on public.attendance_punches using btree (created_by);

create index ix_attendance_punches_staff on public.attendance_punches
  using btree (staff_id, server_at);

create unique index ux_attendance_entries_open on public.attendance_entries using btree (staff_id)
  where ((out_at is null) AND (status = 'active'::text));

create trigger t_attendance_entries_updated
  before update on public.attendance_entries
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.attendance_entries
  for each row
  execute function
    public._assert_same_arena('staff_id', 'staff_profiles', 'in_punch_id', 'attendance_punches',
    'out_punch_id', 'attendance_punches', 'replaces_id', 'attendance_entries');

create trigger t_same_arena
  before insert or update on public.attendance_punches
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create policy "p_sel_attendance_entries" on "public"."attendance_entries"
  for select
  to "authenticated"
  using
    (((arena_id in ( select private.app_arena_ids_with(ARRAY['attendance_review'::text]) as
    app_arena_ids_with)) or (staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids))));

create policy "p_sel_attendance_punches" on "public"."attendance_punches"
  for select
  to "authenticated"
  using
    (((arena_id in ( select private.app_arena_ids_with(ARRAY['attendance_review'::text]) as
    app_arena_ids_with)) or (staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids))));

comment on column "public"."attendance_entries"."arena_id" is 'Owning arena (tenant).';

comment on column "public"."attendance_entries"."created_by" is 'auth.users id of the login that opened the row.';

comment on column "public"."attendance_entries"."flags" is 'Why the entry needs a look: outside_in/out, unknown_in/out, low_accuracy_in/out, no_geofence_in/out, mock_in/out, auto_out.';

comment on column "public"."attendance_entries"."in_at" is 'Server time of the clock-in.';

comment on column "public"."attendance_entries"."in_punch_id" is 'The clock-in punch (evidence); null for a row added by hand.';

comment on column "public"."attendance_entries"."out_at" is 'Server time of the clock-out (or the automatic close); null while the person is on the clock.';

comment on column "public"."attendance_entries"."out_punch_id" is 'The clock-out punch, when there was one (also kept on an automatic close made by a late clock-out).';

comment on column "public"."attendance_entries"."out_source" is 'punch, auto (closed automatically after max_open_hours) or manual; null while open.';

comment on column "public"."attendance_entries"."reason" is 'Why the row was added or corrected by hand; required then.';

comment on column "public"."attendance_entries"."replaces_id" is 'The row this correction replaces.';

comment on column "public"."attendance_entries"."review" is 'none, pending (flagged for a reviewer), accepted or corrected.';

comment on column "public"."attendance_entries"."source" is 'punch (opened by a clock-in) or manual (added by a reviewer).';

comment on column "public"."attendance_entries"."staff_id" is 'The staff profile that worked.';

comment on column "public"."attendance_entries"."status" is 'active, superseded (replaced by a correction) or voided. Only active rows count.';

comment on column "public"."attendance_entries"."work_date" is 'IST calendar date of in_at: a shift crossing midnight belongs to the day it started.';

comment on column "public"."attendance_punches"."accuracy_m" is 'Horizontal accuracy of the fix in metres, as the phone reported it.';

comment on column "public"."attendance_punches"."arena_id" is 'Owning arena (tenant).';

comment on column "public"."attendance_punches"."created_by" is 'auth.users id of the login that sent the punch.';

comment on column "public"."attendance_punches"."device_at" is 'The phone''s own clock at the punch; evidence only, never used for hours or pay.';

comment on column "public"."attendance_punches"."device_id" is 'Install id of the device (the app''s sync device id).';

comment on column "public"."attendance_punches"."distance_m" is 'Distance from the geofence centre in whole metres; null without a fix or a geofence.';

comment on column "public"."attendance_punches"."flags" is 'Why the punch needs a look: outside, unknown, low_accuracy, no_geofence, mock.';

comment on column "public"."attendance_punches"."geofence" is 'Server verdict: inside, outside, or unknown (no fix, accuracy too poor, or no geofence set).';

comment on column "public"."attendance_punches"."geofence_snapshot" is 'The attendance rules applied to this punch: {geofence, outside_rule, min_accuracy_m, mock_rule}.';

comment on column "public"."attendance_punches"."id" is 'Device-generated id (uuid v4), so a resent punch cannot be recorded twice.';

comment on column "public"."attendance_punches"."is_mocked" is 'True when the phone reported a mock (fake) location; null when the platform could not tell.';

comment on column "public"."attendance_punches"."kind" is '''in'' or ''out''.';

comment on column "public"."attendance_punches"."lat" is 'Latitude of the fix in degrees (WGS84); null when no position was captured.';

comment on column "public"."attendance_punches"."lng" is 'Longitude of the fix in degrees (WGS84); null when no position was captured.';

comment on column "public"."attendance_punches"."location_status" is 'ok (a fix was captured), denied (permission refused), gps_off (location services off), timeout (no fix in time) or unavailable.';

comment on column "public"."attendance_punches"."server_at" is 'Server time the punch was received: the only time worked hours are computed from.';

comment on column "public"."attendance_punches"."staff_id" is 'The staff profile that clocked in or out.';

comment on column "public"."attendance_punches"."via" is 'How the punch was made: own_device (the staff member''s signed-in phone). Registered arena tablets (kiosk) come later.';

comment on column "public"."staff_profiles"."perms" is 'Permission codes from _known_perms(): start, bill, discount, members, stations, money, reports, settings, attendance_review. Holding money or reports makes the member owner level (app_is_owner).';

comment on function "private"."app_my_staff_ids"() is 'Staff profile ids of the signed-in user (active only); the own-rows test of the RLS policies on attendance tables.';

comment on function "public"."_attendance_rules"(uuid) is 'Internal: the arena''s attendance setting merged over the defaults (no geofence, flag, 50 m, block mock, 14 h).';

comment on function "public"."_attendance_settings"(jsonb) is 'Validates and normalises the attendance setting (geofence, outside / mock rules, minimum GPS accuracy, auto-close hours); raises invalid_attendance_settings.';

comment on function
  "public"."_geo_distance_m"(double precision, double precision, double precision, double precision)
  is 'Internal: haversine distance in whole metres between two lat/lng points; used for the attendance geofence.';

comment on function "public"."_known_perms"() is 'The permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings, attendance_review.';

comment on function "public"."op_attendance_punch"(uuid, jsonb) is 'Sync op attendance.punch: clock the caller in or out at server time with the captured location; applies the arena''s geofence, mock and outside rules and closes a clock-in left open past max_open_hours.';

comment on table "public"."attendance_entries" is 'Stretches of work (clock-in to clock-out) per staff profile; worked hours are computed from these server times. Corrections supersede rows, never edit history.';

comment on table "public"."attendance_punches" is 'Append-only evidence of each clock-in / clock-out: server time, device time, GPS fix, mock flag, device and the geofence verdict with the rules used. Written by op_attendance_punch only.';

revoke all on function "private"."app_my_staff_ids"() from public;

grant execute
  on function "private"."app_my_staff_ids"()
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."_attendance_rules"(uuid) from public;

grant execute on function "public"."_attendance_rules"(uuid) to "postgres", "service_role";

revoke all on function "public"."_attendance_settings"(jsonb) from public;

grant execute on function "public"."_attendance_settings"(jsonb) to "postgres", "service_role";

revoke all
  on function
    "public"."_geo_distance_m"(double precision, double precision, double precision, double
    precision)
  from public;

grant execute
  on function
    "public"."_geo_distance_m"(double precision, double precision, double precision, double
    precision)
  to "postgres", "service_role";

revoke all on function "public"."op_attendance_punch"(uuid, jsonb) from public;

grant execute on function "public"."op_attendance_punch"(uuid, jsonb) to "postgres", "service_role";

grant select on table "public"."attendance_entries" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."attendance_entries"
  to "postgres", "service_role";

grant select on table "public"."attendance_punches" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."attendance_punches"
  to "postgres", "service_role";
