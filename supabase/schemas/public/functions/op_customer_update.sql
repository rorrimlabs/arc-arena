-- op_customer_update — sync op 'customer.update': edit a customer's name, phone and notes.
--
-- Permission: start OR members.
-- Payload: id, base_version (sync_xid the device last pulled), name, phone?, notes.
-- Checks / errors: forbidden; not_found (hint customer); stale (row changed since base_version);
--   phone_taken (phone already belongs to another customer in the arena).
-- Writes: customers. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_customer_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8;
begin
  if not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  select sync_xid into v_xid from customers where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'customer'; end if;
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the customer was edited on another device';
  end if;
  begin
    update customers set name = p->>'name', phone = nullif(btrim(p->>'phone'), ''),
        notes = p->>'notes', updated_at = statement_timestamp()
      where id = (p->>'id')::uuid;
  exception when unique_violation then
    raise exception 'phone_taken';
  end;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_customer_update(uuid, jsonb) is
  'Sync op customer.update: edits a customer, refusing a stale base_version or a phone already in use.';

grant execute on function "public"."op_customer_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_customer_update"(uuid, jsonb) from public;

revoke all on function "public".op_customer_update(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_customer_update(p_arena uuid, p jsonb) from authenticated;
