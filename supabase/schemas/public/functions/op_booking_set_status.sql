-- op_booking_set_status — sync op 'booking.set_status': cancel an open booking or mark it a
--   no-show.
--
-- Permission: start.
-- Payload: id, status ('cancelled' | 'no_show').
-- Checks / errors: forbidden; invalid_status (any other status); not_found (hint booking);
--   booking_not_open (booking is no longer 'booked', e.g. already checked in). Already in the
--   requested status: success, no write.
-- Writes: bookings.status. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_booking_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  perform _need(p_arena, 'start');
  if (p->>'status') not in ('cancelled', 'no_show') then
    raise exception 'invalid_status' using hint = coalesce(p->>'status', 'null');
  end if;
  select status into v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  -- Already in that state (a replay, or the other device did it): succeed without writing.
  if v_status = p->>'status' then return '{}'::jsonb; end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  update bookings set status = p->>'status', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_booking_set_status(uuid, jsonb) is
  'Sync op booking.set_status: cancels an open booking or marks it a no-show; a repeat of the same status is a no-op.';

grant execute
  on function "public"."op_booking_set_status"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_booking_set_status"(uuid, jsonb) from public;

revoke all on function "public".op_booking_set_status(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_booking_set_status(p_arena uuid, p jsonb) from authenticated;
