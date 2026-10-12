-- op_game_upsert — sync op 'game.upsert': create or edit a game in the catalog.
--
-- Permission: settings.
-- Payload: id, name, aliases[], category_id?, platforms[], player_mode? (default 'single'),
--   max_local_players? (default 1), active? (default true).
-- Checks / errors: forbidden; not_found (id belongs to another arena); constraint failures map to
--   invalid / missing_reference.
-- Writes: games. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_game_upsert (
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
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from games where id = (p->>'id')::uuid and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  insert into games(id, arena_id, name, aliases, category_id, platforms, player_mode,
      max_local_players, active)
    values ((p->>'id')::uuid, p_arena, p->>'name',
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = excluded.active, updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_game_upsert(uuid, jsonb) is
  'Sync op game.upsert: creates or edits a catalog game.';

grant execute on function "public"."op_game_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_game_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_game_upsert(p_arena uuid, p jsonb) from authenticated;
