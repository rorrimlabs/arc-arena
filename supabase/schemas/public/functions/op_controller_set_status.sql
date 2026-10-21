-- op_controller_set_status — sync op 'controller.set_status': set a pad's status and notes.
--
-- Permission: settings.
-- Payload: id, status, notes.
-- Checks / errors: forbidden; not_found (hint controller); invalid (status outside
--   controllers_status_check).
-- Writes: controllers.status, controllers.notes. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_controller_set_status (
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
  update controllers set status = p->>'status', notes = p->>'notes', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'controller'; end if;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_controller_set_status(uuid, jsonb) is
  'Sync op controller.set_status: sets a pad''s status and notes.';

grant execute
  on function "public"."op_controller_set_status"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_controller_set_status"(uuid, jsonb) from public;

revoke all on function "public".op_controller_set_status(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_controller_set_status(p_arena uuid, p jsonb) from authenticated;
