-- op_discount_set_active — sync op 'discount.set_active': turn a preset or coupon on or off.
--
-- Permission: settings.
-- Payload: id, active.
-- Checks / errors: forbidden; not_found (hint discount).
-- Writes: discounts.active. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_discount_set_active (
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
  update discounts set active = coalesce((p->>'active')::boolean, false),
      updated_at = statement_timestamp()
   where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'discount'; end if;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_discount_set_active(uuid, jsonb) is
  'Sync op discount.set_active: turns a preset discount or coupon on or off.';

grant execute on function "public"."op_discount_set_active"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_discount_set_active"(uuid, jsonb) from public;

revoke all on function "public".op_discount_set_active(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_discount_set_active(p_arena uuid, p jsonb) from authenticated;
