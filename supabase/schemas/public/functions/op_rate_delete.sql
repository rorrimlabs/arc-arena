-- op_rate_delete — sync op 'rate.delete': delete one rate from the active rate card.
--
-- Permission: settings.
-- Payload: band (rate band code), activity_code, controller_count? (absent/empty = the any-count
--   rate).
-- Checks / errors: forbidden. No matching rate succeeds (idempotent).
-- Writes: rates (_active_card may first create a 'Current' rate card; _sync_apply then retires the
--   previous price list into pricing_catalog_history). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_rate_delete (
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
  delete from rates r using rate_bands b, activities a
   where r.arena_id = p_arena and r.rate_card_id = _active_card(p_arena)
     and b.id = r.band_id and b.code = p->>'band'
     and a.id = r.activity_id and a.code = p->>'activity_code'
     -- -1 stands for null so the any-count rate (controller_count null) matches itself.
     and coalesce(r.controller_count, -1) = coalesce(nullif(p->>'controller_count','')::int, -1);
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_rate_delete(uuid, jsonb) is
  'Sync op rate.delete: deletes the active card''s rate for a band, activity and controller count (idempotent).';

grant execute on function "public"."op_rate_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rate_delete"(uuid, jsonb) from public;

revoke all on function "public".op_rate_delete(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_rate_delete(p_arena uuid, p jsonb) from authenticated;
