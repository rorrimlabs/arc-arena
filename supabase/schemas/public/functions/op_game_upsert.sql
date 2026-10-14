-- op_game_upsert — sync op 'game.upsert': create or edit a game in the catalog.
--
-- Permission: settings.
-- Payload: id, name (trimmed, 1-80 characters, unique in the arena ignoring case), aliases[],
--   category_id?, platforms[], player_mode? (default 'single'), max_local_players? (default 1),
--   active? (default true on create; absent on an edit keeps the stored flag), base_active? (the
--   active flag the editor showed), age_rating? (3/7/12/16/18 or null), media? ('digital' /
--   'disc' or null). age_rating and media are written only when their key is present, so edits
--   from builds that do not send them (the floor app) keep the stored values.
-- An edit whose base_active differs from the stored flag, and that would change it, was made
-- over an archive or restore done elsewhere meanwhile: it is refused (stale) rather than
-- silently flipping the game back. An id that game.delete removed is never created again.
-- Checks / errors: forbidden; invalid_payload (hint id); not_found (id belongs to another arena,
--   or the game was deleted); invalid_name; duplicate (hint name: another game has that name);
--   stale; constraint failures map to invalid / missing_reference.
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
declare
  v_id     uuid := (p->>'id')::uuid;
  v_name   text := btrim(p->>'name');
  v_active boolean;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from games where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  if v_name is null or v_name = '' or char_length(v_name) > 80 then
    raise exception 'invalid_name' using hint = '1 to 80 characters';
  end if;

  select active into v_active from games where id = v_id and arena_id = p_arena for update;
  if found then
    if p ? 'base_active' and (p->>'base_active')::boolean is distinct from v_active
       and p ? 'active' and (p->>'active')::boolean is distinct from v_active then
      raise exception 'stale' using hint = 'the game was archived or restored on another device';
    end if;
  elsif exists (select 1 from sync_tombstones
                 where arena_id = p_arena and table_name = 'games' and row_key->>'id' = v_id::text) then
    raise exception 'not_found' using hint = 'game deleted';
  end if;

  -- Names are unique ignoring case; the lock makes two concurrent saves of "FIFA" and "fifa" queue.
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text || ':game:' || lower(v_name), 0));
  if exists (select 1 from games
              where arena_id = p_arena and id <> v_id and lower(name) = lower(v_name)) then
    raise exception 'duplicate' using hint = 'name';
  end if;

  insert into games(id, arena_id, name, aliases, category_id, platforms, player_mode,
      max_local_players, active, age_rating, media)
    values (v_id, p_arena, v_name,
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true),
      (p->>'age_rating')::smallint, p->>'media')
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = case when p ? 'active' then excluded.active else games.active end,
      age_rating = case when p ? 'age_rating' then excluded.age_rating else games.age_rating end,
      media = case when p ? 'media' then excluded.media else games.media end,
      updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_game_upsert(uuid, jsonb) is
  'Sync op game.upsert: creates or edits a catalog game (name trimmed and unique ignoring case); refuses an edit over a newer archive/restore (stale) and never re-creates a deleted game.';

grant execute on function "public"."op_game_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_game_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_game_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_game_upsert(p_arena uuid, p jsonb) from authenticated;
