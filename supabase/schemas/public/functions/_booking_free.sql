-- _booking_free(p_arena, p_id, p_resource, p_start, p_end) — refuse overlapping bookings on a station.
--
-- No-op when p_resource is null. Locks the station row (FOR UPDATE) so bookings on it serialise,
-- then raises 'booking_conflict' if another 'booked' booking (id <> p_id) overlaps [p_start, p_end)
-- (touching ends do not conflict). Used by op_booking_create and op_booking_update.
-- Server-only: not executable by anon/authenticated.
create or replace function public._booking_free (
  p_arena    uuid,
  p_id       uuid,
  p_resource uuid,
  p_start    timestamp with time zone,
  p_end      timestamp with time zone
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  if p_resource is null then return; end if;
  perform 1 from resources where id = p_resource and arena_id = p_arena for update;
  if exists (select 1 from bookings
              where arena_id = p_arena and resource_id = p_resource and status = 'booked'
                and id <> p_id and scheduled_start < p_end and scheduled_end > p_start) then
    raise exception 'booking_conflict';
  end if;
end;
$function$;

comment on function public._booking_free(uuid, uuid, uuid, timestamp with time zone, timestamp with time zone) is 'Locks a station and raises booking_conflict if another open booking overlaps the given window.';

grant execute
  on function "public"."_booking_free"(uuid, uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_booking_free"(uuid, uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  from public;

revoke all on function "public"._booking_free(p_arena uuid, p_id uuid, p_resource uuid, p_start timestamp with time zone, p_end timestamp with time zone) from anon;

revoke all on function "public"._booking_free(p_arena uuid, p_id uuid, p_resource uuid, p_start timestamp with time zone, p_end timestamp with time zone) from authenticated;
