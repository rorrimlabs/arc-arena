-- op_attendance_punch — sync op 'attendance.punch': clock the caller in or out, with location
--
-- Permission: none beyond being an active member of the arena (sync_push checks that); a
--   member only ever punches for their own staff profile.
-- Payload: punch_id (device uuid), kind ('in' | 'out'), device_id, device_at (the phone's
--   clock, evidence only), location {status: ok | denied | gps_off | timeout | unavailable,
--   lat, lng, accuracy_m, is_mocked} (lat/lng/accuracy_m required exactly when status = ok).
-- Rules: _attendance_rules(arena). The punch time is the server's statement time. Verdict:
--   inside when a fix is within geofence.radius_m and no less accurate than min_accuracy_m;
--   outside when an accurate fix is beyond the radius; unknown otherwise (no fix, accuracy too
--   poor, or no geofence set). outside_rule then applies to outside AND unknown: block refuses,
--   flag accepts and puts the entry up for review, allow accepts with only the verdict stored.
--   A mock location is refused (mock_rule block) or flagged (flag).
-- Open entries: a clock-in is forgotten once it is older than max_open_hours, or — when a new
--   clock-in arrives — once its shift ended more than work_hours.auto_out_after_min ago. A
--   forgotten one is closed at _att_close_time (the shift end, else clock-in + standard day;
--   out_source auto, flag auto_out, review pending) before this punch is applied: a clock-in
--   then opens a new entry; a clock-out records its punch on the closed entry as evidence
--   without stretching it. A clock-out after the shift end + grace but within max_open_hours
--   keeps its real time and is flagged past_shift_end for review.
-- Checks / errors: not_found (hint staff: the caller has no active profile here);
--   invalid_payload (hint names the field); already_clocked_in; not_clocked_in;
--   outside_geofence (hint: distance and radius); location_required (hint: why the position
--   is unknown); mock_location; duplicate (punch_id reused).
-- Writes: attendance_punches (always, on success); attendance_entries (a new open row on
--   clock-in, the open row closed on clock-out). Returns: {punch_id, entry_id, kind, server_at,
--   geofence, distance_m, flags, review, auto_closed_entry_id}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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

comment on function public.op_attendance_punch(uuid, jsonb) is 'Sync op attendance.punch: clock the caller in or out at server time with the captured location; applies the arena''s geofence, mock and outside rules and closes a clock-in left open past max_open_hours.';

grant execute on function "public"."op_attendance_punch"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_attendance_punch"(uuid, jsonb) from public;

revoke all on function "public".op_attendance_punch(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_attendance_punch(p_arena uuid, p jsonb) from authenticated;
