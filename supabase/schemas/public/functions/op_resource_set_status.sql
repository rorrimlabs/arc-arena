create or replace function public.op_resource_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  update resources set status = p->>'status', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'resource'; end if;
  return '{}'::jsonb;
end;
$function$;

grant execute
  on function "public"."op_resource_set_status"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_resource_set_status"(uuid, jsonb) from public;

revoke all on function "public".op_resource_set_status(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_resource_set_status(p_arena uuid, p jsonb) from authenticated;
