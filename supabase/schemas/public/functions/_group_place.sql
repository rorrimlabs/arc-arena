-- _group_place(p_arena, p_group, a, p_at, p_idx, p_exclude_player) — place one group assignment with its pads.
--
-- Controller count = number of allocated pads, else a.controller_count. Checks _group_assignable,
-- inserts the group_assignments row (idx p_idx, started p_at), stamps games.last_played_at, borrows
-- pads (_pad_borrow, ref 'g:<group>') and allocates them (_pad_allocate, scope 'group'). Returns the
-- number of moves skipped because the pad was already there. Callers hold _group_lock first.
-- Used by op_group_create, op_group_add and op_group_switch.
-- Server-only: not executable by anon/authenticated.
create or replace function public._group_place (
  p_arena          uuid,
  p_group          uuid,
  a                jsonb,
  p_at             timestamp with time zone,
  p_idx            integer,
  p_exclude_player integer
)
  returns integer
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_res uuid := (a->>'resource_id')::uuid;
  v_game uuid := nullif(a->>'game_id','')::uuid;
  v_act text := a->>'activity_code';
  v_player int := (a->>'player_number')::int;
  v_pads uuid[] := _pad_ids(a->'allocations');
  v_npads int := coalesce(array_length(_pad_ids(a->'allocations'), 1), 0);
  v_cc int := case when v_npads > 0 then v_npads else nullif(a->>'controller_count','')::int end;
  v_aid uuid := (a->>'id')::uuid;
  v_skipped int;
begin
  perform _group_assignable(p_arena, p_group, v_res, v_act, v_game, coalesce(v_cc, 0),
    v_player, p_exclude_player, coalesce(jsonb_array_length(coalesce(a->'moves','[]'::jsonb)), 0));
  insert into group_assignments(id, arena_id, group_id, player_number, player_label, idx,
      resource_id, activity_code, game_id, controller_count, started_at, created_at)
    values (v_aid, p_arena, p_group, v_player, a->>'player_label', p_idx, v_res, v_act, v_game,
      v_cc, p_at, v_now);
  if v_game is not null then
    update games set last_played_at = p_at, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;
  v_skipped := _pad_borrow(p_arena, a->'moves', v_res, 'g:' || p_group::text, p_at);
  perform _pad_allocate(p_arena, a->'allocations', 'group', null, p_group, null, v_aid,
    v_player, a->>'player_label', v_res, v_act, v_game, p_at);
  return v_skipped;
end;
$function$;

comment on function public._group_place(uuid, uuid, jsonb, timestamp with time zone, integer, integer) is 'Validates and inserts one group assignment, borrowing and allocating its pads; returns the count of skipped pad moves.';

grant execute
  on function "public"."_group_place"(uuid, uuid, jsonb, timestamp with time zone, integer, integer)
  to "postgres", "service_role";

revoke all
  on function "public"."_group_place"(uuid, uuid, jsonb, timestamp with time zone, integer, integer)
  from public;

revoke all on function "public"._group_place(p_arena uuid, p_group uuid, a jsonb, p_at timestamp with time zone, p_idx integer, p_exclude_player integer) from anon;

revoke all on function "public"._group_place(p_arena uuid, p_group uuid, a jsonb, p_at timestamp with time zone, p_idx integer, p_exclude_player integer) from authenticated;
