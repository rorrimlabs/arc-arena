-- op_rule_reorder — sync op 'rule.reorder': set the order pricing rules are tried in.
--
-- Permission: settings.
-- Payload: ids[] — every rule of the arena, highest priority first; priorities become 1, 2, 3 …
-- Checks / errors: forbidden; stale (ids is not exactly the arena's rules: one was added or
--   deleted on another device).
-- Writes: pricing_rules.priority. A price-list change: _sync_apply retires the previous catalog
--   into pricing_catalog_history. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_rule_reorder (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_ids uuid[] := _jsonb_uuids(p->'ids');
begin
  perform _need(p_arena, 'settings');
  perform 1 from pricing_rules where arena_id = p_arena for update;
  if not _same_ids(coalesce((select array_agg(id) from pricing_rules where arena_id = p_arena), '{}'),
                   v_ids)
     or cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'stale' using hint = 'the rules were changed on another device';
  end if;
  update pricing_rules r set priority = o.n, updated_at = statement_timestamp()
    from unnest(v_ids) with ordinality o(id, n)
   where r.id = o.id and r.arena_id = p_arena and r.priority <> o.n;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_rule_reorder(uuid, jsonb) is
  'Sync op rule.reorder: renumbers every pricing rule of the arena in the given order (first wins).';

grant execute on function "public"."op_rule_reorder"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rule_reorder"(uuid, jsonb) from public;

revoke all on function "public".op_rule_reorder(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_rule_reorder(p_arena uuid, p jsonb) from authenticated;
