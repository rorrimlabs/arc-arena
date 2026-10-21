-- op_group_end_player — sync op 'group.end_player': end one player's open assignment while the
--   group continues.
--
-- Permission: start.
-- Payload: group_id, player_number, expected_assignment_id, at.
-- Checks / errors: forbidden; time_in_future, time_too_old (_client_time: device time after now + 2 min or
--   over 24 h old); not_found (hint group); not_active; no_open_assignment; stale
--   (player was moved on another device); invalid_time (at before the assignment started).
-- Writes: group_assignments.ended_at, controller_allocations.ended_at, group_sessions.updated_at.
--   Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_end_player (
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
  v_open uuid; v_start timestamptz;
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  perform _group_active(p_arena, v_group);
  select id, started_at into v_open, v_start from group_assignments
   where group_id = v_group and player_number = (p->>'player_number')::int and ended_at is null
   for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_group_end_player(uuid, jsonb) is
  'Sync op group.end_player: ends one player''s open assignment and releases their pads.';

grant execute on function "public"."op_group_end_player"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_end_player"(uuid, jsonb) from public;

revoke all on function "public".op_group_end_player(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_end_player(p_arena uuid, p jsonb) from authenticated;
