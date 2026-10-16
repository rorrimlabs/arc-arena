-- _single_supply(p_arena, p_resource, p_activity, ...) — controller checks for a single session.
--
-- Always checks _mode_ok. Without pads (p_pad_count 0): a controller-using activity asking for
-- p_count > 0 in a tracked inventory needs that many free pads ('controllers_unavailable'), unless
-- it stays on p_prev_resource without exceeding p_prev_count. With pads: p_count must equal the
-- pad count ('controller_count_mismatch'), at most 4 ('controllers_exceeded') and at most the
-- game's max players ('players_exceeded'). Used by op_session_start and op_session_reconfigure.
-- Server-only: not executable by anon/authenticated.
create or replace function public._single_supply (
  p_arena         uuid,
  p_resource      uuid,
  p_activity      text,
  p_game          uuid,
  p_pad_count     integer,
  p_count         integer,
  p_prev_resource uuid    default null::uuid,
  p_prev_count    integer default null::integer
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_n int; v_free int; v_max int;
begin
  perform _mode_ok(p_arena, p_resource, p_activity);
  if coalesce(p_pad_count, 0) = 0 then
    v_n := coalesce(p_count, 0);
    if v_n > 0
       and not (p_prev_resource is not distinct from p_resource and v_n <= coalesce(p_prev_count, 0))
       and _uses_controllers(p_arena, p_activity) and _inventory_tracked(p_arena) then
      v_free := _free_pads_at(p_arena, p_resource);
      if v_n > v_free then
        raise exception 'controllers_unavailable' using hint = v_free::text || ' free';
      end if;
    end if;
    return;
  end if;
  if p_count is not null and p_count <> p_pad_count then
    raise exception 'controller_count_mismatch';
  end if;
  if p_pad_count > 4 then raise exception 'controllers_exceeded'; end if;
  if p_game is not null then
    v_max := _game_max_players(p_game);
    if p_pad_count > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
end;
$function$;

comment on function public._single_supply(uuid, uuid, text, uuid, integer, integer, uuid, integer) is 'Raises unless the station mode and the requested controllers (pads or a count) are valid for a single session.';

grant execute
  on function "public"."_single_supply"(uuid, uuid, text, uuid, integer, integer, uuid, integer)
  to "postgres", "service_role";

revoke all
  on function "public"."_single_supply"(uuid, uuid, text, uuid, integer, integer, uuid, integer)
  from public;

revoke all on function "public"._single_supply(p_arena uuid, p_resource uuid, p_activity text, p_game uuid, p_pad_count integer, p_count integer, p_prev_resource uuid, p_prev_count integer) from anon;

revoke all on function "public"._single_supply(p_arena uuid, p_resource uuid, p_activity text, p_game uuid, p_pad_count integer, p_count integer, p_prev_resource uuid, p_prev_count integer) from authenticated;
