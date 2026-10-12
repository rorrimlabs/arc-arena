create or replace function public.op_settings_save (
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
  if (p->>'key') not in ('business_hours') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', p->'json')
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

grant execute on function "public"."op_settings_save"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_settings_save"(uuid, jsonb) from public;

revoke all on function "public".op_settings_save(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_settings_save(p_arena uuid, p jsonb) from authenticated;
