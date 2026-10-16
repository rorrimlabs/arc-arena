-- op_accessory_kind_remove — sync op 'accessory_kind.remove': delete an unused kind, else retire it.
--
-- Permission: settings.
-- Payload: id.
-- A kind no accessory uses is deleted (devices get the tombstone); a kind still on some accessory
-- is retired (active = false) so those accessories keep it. Idempotent: an id that is already
-- gone returns {removed: 'deleted'}.
-- Checks / errors: forbidden; not_found (hint accessory_kind: the id belongs to another arena).
-- Writes: accessory_kinds. Returns: {removed: 'deleted' | 'retired'}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_accessory_kind_remove (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from accessory_kinds where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'accessory_kind';
  end if;
  perform 1 from accessory_kinds where id = v_id and arena_id = p_arena for update;
  if not found then return jsonb_build_object('removed', 'deleted'); end if;

  if exists (select 1 from controllers where kind_id = v_id) then
    update accessory_kinds set active = false, updated_at = statement_timestamp() where id = v_id;
    return jsonb_build_object('removed', 'retired');
  end if;
  delete from accessory_kinds where id = v_id;
  return jsonb_build_object('removed', 'deleted');
end;
$function$;

comment on function public.op_accessory_kind_remove(uuid, jsonb) is
  'Sync op accessory_kind.remove: deletes an accessory kind nothing uses, or retires one still in use.';

grant execute on function "public"."op_accessory_kind_remove"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_accessory_kind_remove"(uuid, jsonb) from public;

revoke all on function "public".op_accessory_kind_remove(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_accessory_kind_remove(p_arena uuid, p jsonb) from authenticated;
