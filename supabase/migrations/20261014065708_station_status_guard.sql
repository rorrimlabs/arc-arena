set local check_function_bodies = off;

create or replace function public.op_resource_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id     uuid := (p->>'id')::uuid;
  v_status text := p->>'status';
begin
  perform _need(p_arena, 'settings');
  perform _lock_resources(p_arena, array[v_id]);
  if not exists (select 1 from resources where id = v_id and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  if v_status is distinct from 'available' then
    if exists (select 1 from session_segments
                where arena_id = p_arena and resource_id = v_id and ended_at is null) then
      raise exception 'resource_busy' using hint = 'open session';
    end if;
    if exists (select 1 from group_assignments
                where arena_id = p_arena and resource_id = v_id and ended_at is null) then
      raise exception 'resource_busy' using hint = 'group player';
    end if;
  end if;
  update resources set status = v_status, updated_at = statement_timestamp()
    where id = v_id and arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_resource_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_code text; v_old text;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never overwritten.
  if exists (select 1 from resources where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  perform _lock_resources(p_arena, array[v_id]);
  select status into v_old from resources where id = v_id and arena_id = p_arena;
  if found and p ? 'status' and (p->>'status') is distinct from v_old
     and (p->>'status') is distinct from 'available'
     and (exists (select 1 from session_segments
                   where arena_id = p_arena and resource_id = v_id and ended_at is null)
          or exists (select 1 from group_assignments
                      where arena_id = p_arena and resource_id = v_id and ended_at is null)) then
    raise exception 'resource_busy' using hint = 'in use';
  end if;
  insert into resources(id, arena_id, name, kind, status, sort_order)
    values (v_id, p_arena, p->>'name', p->>'kind', coalesce(p->>'status', 'available'),
      coalesce((p->>'sort_order')::int, 0))
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      status = case when p ? 'status' then excluded.status else resources.status end,
      sort_order = excluded.sort_order, updated_at = statement_timestamp()
    where resources.arena_id = p_arena;
  -- The station supports exactly the listed activities.
  delete from resource_activities ra using activities a
   where ra.resource_id = v_id and a.id = ra.activity_id
     and not (a.code = any(array(select jsonb_array_elements_text(coalesce(p->'activity_codes','[]'::jsonb)))));
  for v_code in select jsonb_array_elements_text(coalesce(p->'activity_codes', '[]'::jsonb)) loop
    insert into resource_activities(arena_id, resource_id, activity_id)
      values (p_arena, v_id, _activity_id(p_arena, v_code))
    on conflict (resource_id, activity_id) do nothing;
  end loop;
  return '{}'::jsonb;
end;
$function$;

comment on function "public"."op_resource_set_status"(uuid, jsonb) is 'Sync op resource.set_status: puts a station in or out of service or removes it; refuses anything but available while a session or group player is on it (resource_busy).';

comment on function "public"."op_resource_upsert"(uuid, jsonb) is 'Sync op resource.upsert: adds or edits a station and the types it offers; an edit without a status keeps it, and a status change away from available is refused while the station is in use (resource_busy).';
