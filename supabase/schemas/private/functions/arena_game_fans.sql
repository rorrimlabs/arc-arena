-- arena_game_fans(arena, game, since, limit) — the members who played a game most
--
-- Lives in `private`; clients reach it only through the SECURITY INVOKER wrapper
-- public.arena_game_fans.
--
-- Returns [{customer_id, name, sessions, minutes}] for registered members (walk-in
-- guests left out) by minutes played since p_since (bills not voided), most first,
-- at most p_limit (1–20, default 4). SECURITY DEFINER. Caller must be owner
-- level in p_arena (app_is_owner), else 'forbidden'.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.arena_game_fans (
  p_arena uuid,
  p_game  uuid,
  p_since timestamp with time zone,
  p_limit integer default 4
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
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', x.customer_id, 'name', x.name,
      'sessions', x.bills, 'minutes', round(x.minutes)) order by x.minutes desc, x.name), '[]'::jsonb)
    into v_out
    from (select t.customer_id, c.name, t.bills, t.minutes
            from (select customer_id, count(distinct (kind, bill_id)) as bills, sum(minutes) as minutes
                    from _plays(p_arena, coalesce(p_since, now() - interval '30 days'))
                   where game_id = p_game group by customer_id) t
            join customers c on c.id = t.customer_id and not c.is_guest
           order by t.minutes desc, c.name
           limit least(greatest(coalesce(p_limit, 4), 1), 20)) x;
  return v_out;
end;
$function$;

comment on function private.arena_game_fans(uuid, uuid, timestamp with time zone, integer) is 'Client API (owner level): the members who played a game the most since an instant, aggregated on the server.';

grant execute
  on function "private"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "private"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  from public;

revoke all on function "private".arena_game_fans(p_arena uuid, p_game uuid, p_since timestamp with time zone, p_limit integer) from anon;
