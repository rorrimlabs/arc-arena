-- op_shift_unassign — sync op 'shift.unassign': end a shift assignment
--
-- Permission: settings.
-- Payload: id. An assignment that has started ends yesterday (IST), so the days already
--   worked keep their schedule; one that has not started yet is deleted; one that already
--   ended is left as it is. Ending an already ended or removed assignment is a no-op.
-- Checks / errors: forbidden; own_record (a non-owner ending their own assignment).
-- Writes: staff_shifts (update effective_to, or delete). Returns: {}.
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
declare v_today date := _pr_ist_date(statement_timestamp());
begin
  perform _need(p_arena, 'settings');
  -- A schedule decides absences and late marks (pay): nobody changes their own.
  perform _own_record(p_arena, (select staff_id from staff_shifts
                                 where id = (p->>'id')::uuid and arena_id = p_arena));
  -- Ending keeps the days already worked under it (they stay scheduled shift days); only an
  -- assignment that has not started yet is deleted.
  update staff_shifts set effective_to = v_today - 1, updated_at = statement_timestamp()
   where id = (p->>'id')::uuid and arena_id = p_arena and effective_from < v_today
     and (effective_to is null or effective_to >= v_today);
  delete from staff_shifts where id = (p->>'id')::uuid and arena_id = p_arena
     and effective_from >= v_today;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_shift_unassign(uuid, jsonb) is 'Sync op shift.unassign: remove a shift assignment (no-op when already gone).';

grant execute on function "public"."op_shift_unassign"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from public;

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from anon;

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from authenticated;
