set local check_function_bodies = off;

create or replace function public._att_work_date (
  p_staff uuid,
  p_at    timestamp with time zone
)
  returns date
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select coalesce(
    (select d from (values (0, _pr_ist_date(p_at)), (1, _pr_ist_date(p_at) - 1),
                           (2, _pr_ist_date(p_at) + 1)) v(n, d)
      where exists (select 1 from _att_blocks(p_staff, v.d) b
                     where p_at >= b.start_at - interval '2 hours' and p_at < b.end_at
                       and (v.n <> 1 or b.end_at > (v.d + 1)::timestamp at time zone 'Asia/Kolkata'))
      order by n limit 1),
    _pr_ist_date(p_at));
$function$;

create or replace function public.op_attendance_correct (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now    timestamptz := statement_timestamp();
  v_action text := p->>'action';
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_old    attendance_entries;
  v_staff  uuid;
  v_in     timestamptz := (p->>'in_at')::timestamptz;
  v_out    timestamptz := (p->>'out_at')::timestamptz;
  v_day    date;
  v_id     uuid;
begin
  perform _need(p_arena, 'attendance_review');
  if v_action is null or v_action not in ('edit', 'void', 'add') then
    raise exception 'invalid_payload' using hint = 'action: edit, void or add';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;

  if v_action in ('edit', 'void') then
    select * into v_old from attendance_entries
      where id = (p->>'entry_id')::uuid and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'entry'; end if;
    v_staff := v_old.staff_id;
    perform _own_record(p_arena, v_staff);
    if v_old.status <> 'active' then raise exception 'not_active'; end if;
    if _period_finalised(p_arena, v_old.work_date, v_old.work_date) then
      raise exception 'period_finalised' using hint = v_old.work_date::text;
    end if;
  else
    v_staff := (p->>'staff_id')::uuid;
    if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
      raise exception 'not_found' using hint = 'staff';
    end if;
    perform _own_record(p_arena, v_staff);
  end if;

  if v_action = 'void' then
    update attendance_entries set status = 'voided', review = 'corrected' where id = v_old.id;
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, created_by, created_at)
      values (p_arena, 'attendance_entry', v_old.id, 'void', v_reason,
              jsonb_build_object('in_at', v_old.in_at, 'out_at', v_old.out_at), auth.uid(), v_now);
    return jsonb_build_object('entry_id', v_old.id);
  end if;

  if v_in is null or (v_action = 'add' and v_out is null) then
    raise exception 'invalid_times' using hint = 'in_at and out_at';
  end if;
  if v_in > v_now or (v_out is not null and (v_out <= v_in or v_out > v_now
                       or v_out - v_in > interval '24 hours')) then
    raise exception 'invalid_times'
      using hint = 'clock-out after clock-in, not in the future, at most 24 h';
  end if;
  -- The work day is the shift the stretch falls in (overnight shifts count on their start day).
  v_day := _att_work_date(v_staff, v_in);
  if _period_finalised(p_arena, v_day, v_day) then
    raise exception 'period_finalised' using hint = v_day::text;
  end if;

  if v_action = 'edit' then
    update attendance_entries set status = 'superseded' where id = v_old.id;
  end if;
  begin
    insert into attendance_entries(arena_id, staff_id, work_date, in_at, out_at, in_punch_id,
        out_punch_id, source, out_source, replaces_id, flags, review, reason, created_by)
      values (p_arena, v_staff, v_day, v_in, v_out,
        case when v_action = 'edit' then v_old.in_punch_id end,
        case when v_action = 'edit' then v_old.out_punch_id end,
        'manual',
        case when v_out is null then null
             when v_action = 'edit' and v_out is not distinct from v_old.out_at then v_old.out_source
             else 'manual' end,
        case when v_action = 'edit' then v_old.id end,
        case when v_action = 'edit' then v_old.flags else '{}'::text[] end,
        'corrected', v_reason, auth.uid())
      returning id into v_id;
  exception when exclusion_violation or unique_violation then
    raise exception 'overlap' using hint = 'another stretch of this person covers that time';
  end;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after, created_by, created_at)
    values (p_arena, 'attendance_entry', v_id, case when v_action = 'edit' then 'correct' else 'add' end,
            v_reason,
            case when v_action = 'edit'
                 then jsonb_build_object('entry_id', v_old.id, 'in_at', v_old.in_at, 'out_at', v_old.out_at) end,
            jsonb_build_object('in_at', v_in, 'out_at', v_out), auth.uid(), v_now);
  return jsonb_build_object('entry_id', v_id);
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
  v_close    timestamptz;
  v_late_out boolean := false;
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
    v_flags := v_flags || 'no_geofence'::text;
  else
    v_dist := _geo_distance_m(v_lat, v_lng, (v_fence->>'lat')::double precision,
                              (v_fence->>'lng')::double precision);
    if v_acc > v_min_acc then
      v_verdict := 'unknown';
      v_flags := v_flags || 'low_accuracy'::text;
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
    v_flags := v_flags || 'mock'::text;
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

  -- The person's open stretch, closed automatically when it was forgotten.
  select * into v_open from attendance_entries
    where staff_id = v_staff and out_at is null and status = 'active' for update;
  if found then
    v_close := _att_close_time(v_staff, v_open.work_date, v_open.in_at);
    if v_open.in_at + v_max_open < v_now
       or (v_kind = 'in' and v_close + make_interval(
             mins => (_work_hours(p_arena)->>'auto_out_after_min')::int) < v_now) then
      update attendance_entries
         set out_at = v_close, out_source = 'auto',
             flags = array(select distinct f from unnest(flags || '{auto_out}'::text[]) f order by f),
             review = 'pending'
       where id = v_open.id;
      v_auto := v_open.id;
    elsif v_kind = 'out' and v_close + make_interval(
            mins => (_work_hours(p_arena)->>'auto_out_after_min')::int) < v_now then
      v_late_out := true;
      v_review := 'pending';
    end if;
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
      values (p_arena, v_staff, _att_work_date(v_staff, v_now), v_now, v_punch,
        array(select f || '_in' from unnest(v_flags) f order by f), v_review, auth.uid())
      returning id into v_entry;
  else
    -- On an automatic close the punch is kept on the row as evidence of when the person
    -- actually tapped; the stretch itself stays at in_at + max_open_hours.
    update attendance_entries
       set out_at = case when v_auto is null then v_now else out_at end,
           out_source = case when v_auto is null then 'punch' else out_source end,
           out_punch_id = v_punch,
           flags = array(select distinct f from unnest(flags
                     || array(select f2 || '_out' from unnest(v_flags) f2)
                     || case when v_late_out then '{past_shift_end}'::text[] else '{}'::text[] end) f
                   order by f),
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

comment on column "public"."attendance_entries"."work_date" is 'The work day: the start day of the shift the stretch falls in (_att_work_date; a shift crossing midnight belongs to the day it started), else the IST date of in_at.';

comment on function "public"."_att_work_date"(uuid, timestamp
  with time zone) is 'Internal: the work day of an entry starting at p_at: the shift it falls in (its start day), including an overnight shift from the day before; else the IST date.';

revoke all on function "public"."_att_work_date"(uuid, timestamp with time zone) from public;

grant execute
  on function "public"."_att_work_date"(uuid, timestamp with time zone)
  to "postgres", "service_role";
