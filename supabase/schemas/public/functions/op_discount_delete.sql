-- op_discount_delete — sync op 'discount.delete': delete a preset or coupon no bill has used.
--
-- Permission: settings.
-- Payload: id. Idempotent: an id that is already gone is a no-op.
-- Checks / errors: forbidden; not_found (hint discount: the id belongs to another arena);
--   discount_used (hint: how many bills used it — turn it off instead, so their record stays).
-- Writes: discounts (delete; devices get the tombstone). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_discount_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_used int;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from discounts where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'discount';
  end if;
  perform 1 from discounts where id = v_id and arena_id = p_arena for update;
  if not found then return '{}'::jsonb; end if;
  select count(*) into v_used from bill_discounts where discount_id = v_id;
  if v_used > 0 then raise exception 'discount_used' using hint = v_used::text; end if;
  delete from discounts where id = v_id;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_discount_delete(uuid, jsonb) is
  'Sync op discount.delete: deletes a preset or coupon that no bill has used (a used one is turned off instead).';

grant execute on function "public"."op_discount_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_discount_delete"(uuid, jsonb) from public;

revoke all on function "public".op_discount_delete(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_discount_delete(p_arena uuid, p jsonb) from authenticated;
