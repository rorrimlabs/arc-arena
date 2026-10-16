-- op_shift_unassign — sync op 'shift.unassign': remove a shift assignment
--
-- Permission: settings.
-- Payload: id. Removing an already removed assignment is a no-op. Finalised salary runs keep
--   the days they were built from, so history is not rewritten.
-- Writes: staff_shifts (delete). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_shift_unassign (
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
  delete from staff_shifts where id = (p->>'id')::uuid and arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_shift_unassign(uuid, jsonb) is 'Sync op shift.unassign: remove a shift assignment (no-op when already gone).';

grant execute on function "public"."op_shift_unassign"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from public;

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from anon;

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from authenticated;
