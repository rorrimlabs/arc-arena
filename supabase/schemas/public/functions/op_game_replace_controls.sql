-- op_game_replace_controls — sync op 'game.replace_controls': replace a game's control guide
--   wholesale.
--
-- Permission: settings.
-- Payload: game_id; controls[] {id, section, action, buttons[], explanation, notes, image_url,
--   sort_order?}.
-- Checks / errors: forbidden; not_found (hint game, or the game is in another arena); duplicate
--   (control id reused).
-- Writes: game_controls (delete all for the game, then insert the list). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_game_replace_controls (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_game uuid := (p->>'game_id')::uuid; c jsonb;
begin
  perform _need(p_arena, 'settings');
  if not exists (select 1 from games where id = v_game and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  delete from game_controls where game_id = v_game and arena_id = p_arena;
  for c in select value from jsonb_array_elements(coalesce(p->'controls', '[]'::jsonb)) loop
    insert into game_controls(id, arena_id, game_id, section, action, buttons, explanation, notes,
        image_url, sort_order)
      values ((c->>'id')::uuid, p_arena, v_game, c->>'section', c->>'action',
        array(select jsonb_array_elements_text(coalesce(c->'buttons', '[]'::jsonb))),
        c->>'explanation', c->>'notes', c->>'image_url', coalesce((c->>'sort_order')::int, 0));
  end loop;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_game_replace_controls(uuid, jsonb) is
  'Sync op game.replace_controls: replaces the full list of control-guide rows for one game.';

grant execute
  on function "public"."op_game_replace_controls"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_game_replace_controls"(uuid, jsonb) from public;

revoke all on function "public".op_game_replace_controls(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_game_replace_controls(p_arena uuid, p jsonb) from authenticated;
