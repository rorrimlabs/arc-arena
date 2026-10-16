-- assert_resource_free_for_assignment() — trigger: a group player may only take a free station
--
-- BEFORE INSERT OR UPDATE OF resource_id, ended_at row trigger
-- (t_assignment_resource_free) on group_assignments. For an open assignment it
-- locks the resources row (same serialisation as
-- assert_resource_free_for_segment), then raises 'resource_busy' if the station
-- has an open solo session segment or an open assignment of a different group.
-- Server-only: not executable by anon/authenticated.
create or replace function public.assert_resource_free_for_assignment()
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
  perform 1 from resources where id = new.resource_id for update;

  select count(*) into busy from (
    select 1 from session_segments
      where resource_id = new.resource_id
        and ended_at is null
    union all
    -- Open assignments of the same group may share the station.
    select 1 from group_assignments
      where resource_id = new.resource_id
        and ended_at is null
        and group_id <> new.group_id
        and id <> new.id
  ) t;

  if busy > 0 then
    raise exception 'resource_busy'
      using hint = 'That station already has a session on it.';
  end if;
  return new;
end;
$function$;

comment on function public.assert_resource_free_for_assignment() is 'Trigger (group_assignments): refuse an open assignment on a station that has an open session segment or an open assignment of another group (resource_busy).';

grant execute
  on function "public"."assert_resource_free_for_assignment"()
  to "postgres", "service_role";

revoke all on function "public"."assert_resource_free_for_assignment"() from public;

revoke all on function "public".assert_resource_free_for_assignment() from anon;

revoke all on function "public".assert_resource_free_for_assignment() from authenticated;
