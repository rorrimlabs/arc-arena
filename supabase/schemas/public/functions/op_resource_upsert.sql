create or replace function public.op_resource_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_code text;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never overwritten.
  if exists (select 1 from resources where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  insert into resources(id, arena_id, name, kind, status, sort_order)
    values (v_id, p_arena, p->>'name', p->>'kind', coalesce(p->>'status', 'available'),
      coalesce((p->>'sort_order')::int, 0))
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      status = excluded.status, sort_order = excluded.sort_order, updated_at = statement_timestamp()
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

grant execute on function "public"."op_resource_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_resource_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_resource_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_resource_upsert(p_arena uuid, p jsonb) from authenticated;
