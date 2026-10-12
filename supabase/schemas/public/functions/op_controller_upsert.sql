-- op_controller_upsert — sync op 'controller.upsert': create or edit a pad in the inventory.
--
-- Permission: settings.
-- Payload: id, label, home_resource_id, current_resource_id, status? (default 'usable'), notes,
--   loan_return_to, loan_session_ref.
-- Checks / errors: forbidden; not_found (id belongs to another arena); controller_in_use (changing
--   the location of a pad that has an open allocation); constraint failures map to invalid /
--   missing_reference.
-- Writes: controllers (insert or update; no controller_moves row). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_controller_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_loc uuid;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from controllers where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'controller';
  end if;
  select current_resource_id into v_loc from controllers where id = v_id and arena_id = p_arena for update;
  if found and v_loc <> (p->>'current_resource_id')::uuid and exists (
       select 1 from controller_allocations where controller_id = v_id and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  insert into controllers(id, arena_id, label, home_resource_id, current_resource_id, status,
      notes, loan_return_to, loan_session_ref)
    values (v_id, p_arena, p->>'label', (p->>'home_resource_id')::uuid,
      (p->>'current_resource_id')::uuid, coalesce(p->>'status', 'usable'), p->>'notes',
      p->>'loan_return_to', p->>'loan_session_ref')
  on conflict (id) do update set label = excluded.label,
      home_resource_id = excluded.home_resource_id, current_resource_id = excluded.current_resource_id,
      status = excluded.status, notes = excluded.notes, loan_return_to = excluded.loan_return_to,
      loan_session_ref = excluded.loan_session_ref, updated_at = statement_timestamp()
    where controllers.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_controller_upsert(uuid, jsonb) is
  'Sync op controller.upsert: creates or edits a pad, refusing to relocate one that is in use.';

grant execute on function "public"."op_controller_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_controller_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_controller_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_controller_upsert(p_arena uuid, p jsonb) from authenticated;
