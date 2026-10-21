-- assert_resource_free_for_segment() — trigger: a session segment may only open on a free station
--
-- BEFORE INSERT OR UPDATE OF resource_id, ended_at row trigger
-- (t_segment_resource_free) on session_segments. For an open segment it locks
-- the resources row, then raises 'resource_busy' if the station has any other
-- open segment or any open group assignment. Pairs with
-- assert_resource_free_for_assignment: occupancy spans both tables.
-- Server-only: not executable by anon/authenticated.
create or replace function public.assert_resource_free_for_segment()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
declare
  busy int;
begin
  if new.ended_at is not null then
    return new;
  end if;
  -- Serialise claims on this resource: two concurrent starts must not both see
  -- it free. A unique index cannot do this because occupancy spans two tables,
  -- so the lock is what makes the check sound.
  perform 1 from resources where id = new.resource_id for update;

  select count(*) into busy from (
    select 1 from session_segments
      where resource_id = new.resource_id
        and ended_at is null
        and id <> new.id
    union all
    select 1 from group_assignments
      where resource_id = new.resource_id
        and ended_at is null
  ) t;

  if busy > 0 then
    raise exception 'resource_busy'
      using hint = 'That station already has a session on it.';
  end if;
  return new;
end;
$function$;

comment on function public.assert_resource_free_for_segment() is 'Trigger (session_segments): refuse an open segment on a station that already has an open segment or an open group assignment (resource_busy), serialised by locking the station row.';

grant execute
  on function "public"."assert_resource_free_for_segment"()
  to "postgres", "service_role";

revoke all on function "public"."assert_resource_free_for_segment"() from public;

revoke all on function "public".assert_resource_free_for_segment() from anon;

revoke all on function "public".assert_resource_free_for_segment() from authenticated;
