-- op_booking_create — sync op 'booking.create': create a booked reservation for a time window.
--
-- Permission: start.
-- Payload: id; customer_id?, resource_id?, activity_code, game_id?; scheduled_start,
--   scheduled_end; players_required?, controller_requirement?, party_name, phone, notes,
--   reminder_status? (default 'scheduled'), created_at? (default server time).
-- Checks / errors: forbidden (no start); booking_conflict (another 'booked' booking on the same
--   station overlaps the window; the station row is locked first); activity_missing (unknown
--   activity_code); constraint failures map to invalid (end not after start), duplicate (id
--   reused), missing_reference (customer / station / game outside this arena).
-- Writes: bookings. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_booking_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_now timestamptz := statement_timestamp(); v_res uuid := nullif(p->>'resource_id','')::uuid;
begin
  perform _need(p_arena, 'start');
  perform _booking_free(p_arena, (p->>'id')::uuid, v_res,
    (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz);
  insert into bookings(id, arena_id, customer_id, resource_id, activity_id, game_id, scheduled_start,
      scheduled_end, status, players_required, controller_requirement, party_name, phone, notes,
      reminder_status, created_at, updated_at)
    values ((p->>'id')::uuid, p_arena, nullif(p->>'customer_id','')::uuid, v_res,
      _activity_id(p_arena, p->>'activity_code'), nullif(p->>'game_id','')::uuid,
      (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz, 'booked',
      nullif(p->>'players_required','')::int, nullif(p->>'controller_requirement','')::int,
      p->>'party_name', p->>'phone', p->>'notes', coalesce(p->>'reminder_status', 'scheduled'),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now);
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_booking_create(uuid, jsonb) is
  'Sync op booking.create: creates a booked reservation, refusing an overlap with another open booking on the same station.';

grant execute on function "public"."op_booking_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_booking_create"(uuid, jsonb) from public;

revoke all on function "public".op_booking_create(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_booking_create(p_arena uuid, p jsonb) from authenticated;
