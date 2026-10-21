-- op_booking_update — sync op 'booking.update': edit an open booking (customer, station, activity,
--   window, details).
--
-- Permission: start.
-- Payload: id, base_version (sync_xid the device last pulled); customer_id?, resource_id?,
--   activity_code, game_id?, scheduled_start, scheduled_end, players_required?,
--   controller_requirement?, party_name, phone, notes.
-- Checks / errors: forbidden; not_found (hint booking); stale (row changed since base_version);
--   booking_not_open; booking_conflict (overlaps another 'booked' booking on the station);
--   activity_missing; constraint failures map to invalid / missing_reference.
-- Writes: bookings. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_booking_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8; v_status text; v_res uuid := nullif(p->>'resource_id','')::uuid;
begin
  perform _need(p_arena, 'start');
  select sync_xid, status into v_xid, v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  -- base_version is the row's sync_xid as the device last pulled it; absent/empty skips the check.
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the booking was changed on another device';
  end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  perform _booking_free(p_arena, (p->>'id')::uuid, v_res,
    (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz);
  update bookings set customer_id = nullif(p->>'customer_id','')::uuid, resource_id = v_res,
      activity_id = _activity_id(p_arena, p->>'activity_code'), game_id = nullif(p->>'game_id','')::uuid,
      scheduled_start = (p->>'scheduled_start')::timestamptz,
      scheduled_end = (p->>'scheduled_end')::timestamptz,
      players_required = nullif(p->>'players_required','')::int,
      controller_requirement = nullif(p->>'controller_requirement','')::int,
      party_name = p->>'party_name', phone = p->>'phone', notes = p->>'notes',
      updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_booking_update(uuid, jsonb) is
  'Sync op booking.update: edits an open booking, refusing a stale base_version or an overlap with another booking on the station.';

grant execute on function "public"."op_booking_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_booking_update"(uuid, jsonb) from public;

revoke all on function "public".op_booking_update(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_booking_update(p_arena uuid, p jsonb) from authenticated;
