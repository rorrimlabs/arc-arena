-- op_rule_delete — sync op 'rule.delete': delete a pricing rule.
--
-- Permission: settings.
-- Payload: id. Idempotent: an id that is already gone is a no-op. Sessions already started keep
--   the rule in their frozen pricing snapshot, so their bills do not change.
-- Checks / errors: forbidden; not_found (hint rule: the id belongs to another arena).
-- Writes: pricing_rules (delete; devices get the tombstone). A price-list change: _sync_apply
--   retires the previous catalog into pricing_catalog_history. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_rule_delete (
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
  if exists (select 1 from pricing_rules where id = (p->>'id')::uuid and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'rule';
  end if;
  delete from pricing_rules where id = (p->>'id')::uuid and arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_rule_delete(uuid, jsonb) is
  'Sync op rule.delete: deletes a pricing rule; sessions already started keep it in their snapshot.';

grant execute on function "public"."op_rule_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rule_delete"(uuid, jsonb) from public;

revoke all on function "public".op_rule_delete(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_rule_delete(p_arena uuid, p jsonb) from authenticated;
