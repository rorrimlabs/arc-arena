-- arena_game_stats(arena, since) — per-game figures for the Games screen
--
-- Lives in `private`; clients reach it only through the SECURITY INVOKER wrapper
-- public.arena_game_stats.
--
-- Returns {game id: {minutes_30, sessions_30, playing_now}} for games played
-- since p_since or being played now (bills not voided): minutes of play (open
-- play up to now), distinct bills, and open plays of running bills.
-- SECURITY DEFINER. Caller must be owner level in p_arena (app_is_owner), else
-- 'forbidden'.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.arena_game_stats (
  p_arena uuid,
  p_since timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_out jsonb;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read game figures';
  end if;
  select coalesce(jsonb_object_agg(game_id, jsonb_build_object(
      'minutes_30', round(minutes), 'sessions_30', bills, 'playing_now', now_playing)), '{}'::jsonb)
    into v_out
    from (select game_id, sum(minutes) as minutes, count(distinct (kind, bill_id)) as bills,
                 count(*) filter (where ended_at is null and bill_status = 'active') as now_playing
            from _plays(p_arena, coalesce(p_since, now() - interval '30 days'))
           where game_id is not null group by game_id) t;
  return v_out;
end;
$function$;

comment on function private.arena_game_stats(uuid, timestamp with time zone) is 'Client API (owner level): per-game minutes, bills and stations playing it now, aggregated on the server.';

grant execute
  on function "private"."arena_game_stats"(uuid, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_game_stats"(uuid, timestamp with time zone) from public;

revoke all on function "private".arena_game_stats(p_arena uuid, p_since timestamp with time zone) from anon;
