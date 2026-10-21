-- op_game_set_compat — sync op 'game.set_compat': set how a game runs on one station.
--
-- Permission: settings.
-- Payload: game_id, resource_id, status, notes? (absent keeps the stored note, so the dashboard,
--   which does not show notes, never wipes one staff wrote on the floor app; null clears it).
-- Checks / errors: forbidden; constraint failures map to invalid (status outside
--   game_resources_status_check) and missing_reference (game or station outside this arena,
--   same-arena trigger).
-- Writes: game_resources (upsert on game_id, resource_id). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_game_set_compat (
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
  insert into game_resources(arena_id, game_id, resource_id, status, notes)
    values (p_arena, (p->>'game_id')::uuid, (p->>'resource_id')::uuid, p->>'status', p->>'notes')
  on conflict (game_id, resource_id) do update
    set status = excluded.status,
        notes = case when p ? 'notes' then excluded.notes else game_resources.notes end,
        updated_at = statement_timestamp()
    where game_resources.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_game_set_compat(uuid, jsonb) is
  'Sync op game.set_compat: upserts the compatibility status of a game on a station (what _game_playable checks).';

grant execute on function "public"."op_game_set_compat"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_set_compat"(uuid, jsonb) from public;

revoke all on function "public".op_game_set_compat(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_game_set_compat(p_arena uuid, p jsonb) from authenticated;
