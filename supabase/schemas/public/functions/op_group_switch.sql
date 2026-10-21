-- op_group_switch — sync op 'group.switch': move a player to another station / game (close + new
--   assignment).
--
-- Permission: start.
-- Payload: group_id, player_number, expected_assignment_id, at; assignment {id, resource_id,
--   activity_code, game_id?, controller_count?, allocations[], moves[]} (player_number and
--   player_label are taken from the open assignment).
-- Checks / errors: forbidden; time_in_future, time_too_old (_client_time: device time after now + 2 min or
--   over 24 h old); not_found (hint group); not_active; no_open_assignment; stale;
--   invalid_time; retry (40001); placement errors per assignment (_group_place ->
--   _group_assignable): resource_missing, resource_unavailable, mode_locked, not_playable,
--   resource_busy (single session on the station, or another group), controllers_exceeded (> 4 on
--   the station), players_exceeded (game player limit), controllers_unavailable, game_conflict
--   (sharing a station with a different activity/game); then pad errors from _pad_borrow /
--   _pad_allocate: controller_missing, controller_unusable, controller_taken (open allocation, or
--   an untracked count-only player at that station), controller_duplicate, controller_elsewhere
--   (allocated pad not at the target station).
-- Writes: group_assignments (close + insert), controller_allocations, controllers +
--   controller_moves, games.last_played_at, group_sessions.updated_at. Returns: {assignment_id,
--   adjusted}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_switch (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_player int := (p->>'player_number')::int;
  a jsonb := p->'assignment';
  v_open uuid; v_open_res uuid; v_start timestamptz; v_idx int; v_label text; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  perform _group_active(p_arena, v_group);
  select id, resource_id, started_at, idx, player_label
    into v_open, v_open_res, v_start, v_idx, v_label
    from group_assignments
   where group_id = v_group and player_number = v_player and ended_at is null for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  -- Also lock the station the player is leaving.
  perform _group_lock(p_arena, jsonb_build_array(a), array[v_open_res]);
  -- The player keeps their label across a switch (as on the device).
  a := a || jsonb_build_object('player_number', v_player, 'player_label', v_label);
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx + 1, v_player);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$function$;

comment on function public.op_group_switch(uuid, jsonb) is
  'Sync op group.switch: closes a player''s open assignment and places them on a new station or game.';

grant execute on function "public"."op_group_switch"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_switch"(uuid, jsonb) from public;

revoke all on function "public".op_group_switch(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_switch(p_arena uuid, p jsonb) from authenticated;
