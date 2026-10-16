-- _group_assignable(p_arena, p_group, p_resource, ...) — can a group player go on this station?
--
-- Raises resource_missing / resource_unavailable, mode_locked, not_playable, resource_busy (open
-- single-session segment, another group, or sharing with a non-controller activity),
-- controllers_exceeded (> 4), players_exceeded, controllers_unavailable (usable pads + p_borrowed)
-- or game_conflict (sharing players must run the same activity and game). p_exclude_player ignores
-- that player's own open assignments (switch). Called by _group_place.
-- Server-only: not executable by anon/authenticated.
create or replace function public._group_assignable (
  p_arena          uuid,
  p_group          uuid,
  p_resource       uuid,
  p_activity       text,
  p_game           uuid,
  p_cc             integer,
  p_player         integer,
  p_exclude_player integer,
  p_borrowed       integer
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_used int; v_usable int; v_max int; v_others int; v_players int;
begin
  perform _station_usable(p_arena, p_resource);
  perform _mode_ok(p_arena, p_resource, p_activity);
  perform _game_playable(p_game, p_resource);
  if exists (select 1 from session_segments where resource_id = p_resource and ended_at is null) then
    raise exception 'resource_busy';
  end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id <> p_group) then
    raise exception 'resource_busy' using hint = 'another group';
  end if;
  select count(*), coalesce(sum(coalesce(controller_count, 0)), 0)
    into v_others, v_used
    from group_assignments
   where resource_id = p_resource and ended_at is null and group_id = p_group
     and not (p_exclude_player is not null and player_number = p_exclude_player);
  if v_used + p_cc > 4 then raise exception 'controllers_exceeded'; end if;
  if p_game is not null then
    v_max := _game_max_players(p_game);
    if v_used + p_cc > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
  v_usable := _usable_pads_at(p_arena, p_resource) + coalesce(p_borrowed, 0);
  if v_used + p_cc > v_usable then
    raise exception 'controllers_unavailable' using hint = v_usable::text || ' usable';
  end if;
  if v_others = 0 then return; end if;
  -- Sharing a station with this group's other players: controller activities only, same activity and game.
  if not _uses_controllers(p_arena, p_activity) then raise exception 'resource_busy'; end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id = p_group
                and not (p_exclude_player is not null and player_number = p_exclude_player)
                and (activity_code is distinct from p_activity or game_id is distinct from p_game)) then
    raise exception 'game_conflict';
  end if;
  if p_game is not null then
    -- Distinct players on the station after placing p_player (+1 unless already there).
    select count(distinct player_number) + (case when exists (
             select 1 from group_assignments where resource_id = p_resource and ended_at is null
               and group_id = p_group and player_number = p_player
               and not (p_exclude_player is not null and player_number = p_exclude_player))
           then 0 else 1 end)
      into v_players from group_assignments
     where resource_id = p_resource and ended_at is null and group_id = p_group
       and not (p_exclude_player is not null and player_number = p_exclude_player);
    if v_players > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
end;
$function$;

comment on function public._group_assignable(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer) is 'Raises unless a group player can be placed on the station with the requested activity, game and controllers.';

grant execute
  on function
    "public"."_group_assignable"(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer)
  to "postgres", "service_role";

revoke all
  on function
    "public"."_group_assignable"(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer)
  from public;

revoke all on function "public"._group_assignable(p_arena uuid, p_group uuid, p_resource uuid, p_activity text, p_game uuid, p_cc integer, p_player integer, p_exclude_player integer, p_borrowed integer) from anon;

revoke all on function "public"._group_assignable(p_arena uuid, p_group uuid, p_resource uuid, p_activity text, p_game uuid, p_cc integer, p_player integer, p_exclude_player integer, p_borrowed integer) from authenticated;
