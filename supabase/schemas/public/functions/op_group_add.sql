-- op_group_add — sync op 'group.add': add a player (one assignment) to an active group.
--
-- Permission: start.
-- Payload: group_id, at; assignment {id, player_number, player_label, resource_id, activity_code,
--   game_id?, controller_count?, allocations[] {id?, controller_id}, moves[] {id?,
--   controller_id}}.
-- Checks / errors: forbidden; time_in_future, time_too_old (_client_time: device time after now + 2 min or
--   over 24 h old); not_found (hint group); not_active; player_busy (player already has
--   an open assignment); retry (40001: a borrowed pad moved before it was locked); placement
--   errors per assignment (_group_place -> _group_assignable): resource_missing,
--   resource_unavailable, mode_locked, not_playable, resource_busy (single session on the station,
--   or another group), controllers_exceeded (> 4 on the station), players_exceeded (game player
--   limit), controllers_unavailable, game_conflict (sharing a station with a different
--   activity/game); then pad errors from _pad_borrow / _pad_allocate: controller_missing,
--   controller_unusable, controller_taken (open allocation, or an untracked count-only player at
--   that station), controller_duplicate, controller_elsewhere (allocated pad not at the target
--   station).
-- Writes: group_assignments, controllers + controller_moves (borrows), controller_allocations,
--   games.last_played_at, group_sessions.updated_at. Returns: {assignment_id, adjusted} (adjusted:
--   a borrow was skipped because the pad was already there).
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_add (
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
  a jsonb := p->'assignment';
  v_player int := (p->'assignment'->>'player_number')::int;
  v_idx int; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  perform _group_active(p_arena, v_group);
  if exists (select 1 from group_assignments
              where group_id = v_group and player_number = v_player and ended_at is null) then
    raise exception 'player_busy';
  end if;
  perform _group_lock(p_arena, jsonb_build_array(a));
  -- Next index in this player's assignment history (a re-added player continues it).
  select coalesce(max(idx), -1) + 1 into v_idx from group_assignments
    where group_id = v_group and player_number = v_player;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx, null);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
end;
$function$;

comment on function public.op_group_add(uuid, jsonb) is
  'Sync op group.add: adds one player assignment to an active group after re-validating the station and pads.';

grant execute on function "public"."op_group_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_add"(uuid, jsonb) from public;

revoke all on function "public".op_group_add(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_add(p_arena uuid, p jsonb) from authenticated;
