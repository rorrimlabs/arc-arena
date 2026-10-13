-- _sales(arena, from, to, id) — closed bills of an arena as one jsonb object each
--
-- A bill is a sessions row (kind 'single') or a group_sessions row (kind
-- 'group') that is no longer active: completed or voided. Its time `at` is when
-- it closed: actual_ended_at, or for a bill voided while it ran (never ended)
-- the void (updated_at). With p_id set, returns that one bill (any time);
-- otherwise the bills with p_from <= at < p_to. Each object:
--   {kind, id, at, started_at, ended_at, status, payment_status, customer,
--    guest, stations[], activities[], games[], players, billed_paise,
--    paid_paise, refunded_paise, methods{method: net paise}, started_by,
--    void_reason}
-- stations/activities/games are names in play order; paid_paise is the net of
-- the payments ledger (refunds negative), refunded_paise the refunds as a
-- positive sum, methods the net per payment method; started_by is the staff
-- name of the login that started it. Unordered. Shared body of arena_sales and
-- arena_sale, which check the caller. Server-only: not executable by
-- anon/authenticated.
create or replace function public._sales (
  p_arena uuid,
  p_from  timestamptz,
  p_to    timestamptz,
  p_id    uuid default null
)
  returns setof jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
      'kind', 'single', 'id', s.id, 'at', b.at,
      'started_at', s.started_at, 'ended_at', s.actual_ended_at,
      'status', s.status, 'payment_status', s.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', seg.players,
      'billed_paise', s.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods,
      'started_by', sp.name, 'void_reason', s.void_reason)
    from sessions s
    cross join lateral (select coalesce(s.actual_ended_at, s.updated_at) as at) b
    join customers c on c.id = s.customer_id
    left join staff_profiles sp on sp.arena_id = s.arena_id and sp.user_id = s.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.idx) as first
                                 from session_segments g join resources r on r.id = g.resource_id
                                where g.session_id = s.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.idx) as first
                                 from session_segments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.session_id = s.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.idx) as first
                                 from session_segments g join games gm on gm.id = g.game_id
                                where g.session_id = s.id group by gm.name) x), '[]'::jsonb) as games,
             coalesce((select max(g.controller_count) from session_segments g
                        where g.session_id = s.id), 1) as players
    ) seg
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from payments
                                where session_id = s.id group by method) m), '{}'::jsonb) as methods
        from payments p where p.session_id = s.id
    ) pay
   where s.arena_id = p_arena and s.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else s.id = p_id end)
  union all
  select jsonb_build_object(
      'kind', 'group', 'id', gs.id, 'at', b.at,
      'started_at', gs.started_at, 'ended_at', gs.actual_ended_at,
      'status', gs.status, 'payment_status', gs.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', gs.player_count,
      'billed_paise', gs.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods,
      'started_by', sp.name, 'void_reason', gs.void_reason)
    from group_sessions gs
    cross join lateral (select coalesce(gs.actual_ended_at, gs.updated_at) as at) b
    join customers c on c.id = gs.primary_customer_id
    left join staff_profiles sp on sp.arena_id = gs.arena_id and sp.user_id = gs.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join resources r on r.id = g.resource_id
                                where g.group_id = gs.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.group_id = gs.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join games gm on gm.id = g.game_id
                                where g.group_id = gs.id group by gm.name) x), '[]'::jsonb) as games
    ) seg
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from group_payments
                                where group_id = gs.id group by method) m), '{}'::jsonb) as methods
        from group_payments p where p.group_id = gs.id
    ) pay
   where gs.arena_id = p_arena and gs.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else gs.id = p_id end);
$function$;

comment on function public._sales(uuid, timestamptz, timestamptz, uuid) is 'Closed bills (completed or voided sessions and groups) of an arena as jsonb summaries, by close time range or by id. Server-only body of arena_sales / arena_sale.';

grant execute on function "public"."_sales"(uuid, timestamptz, timestamptz, uuid) to "postgres", "service_role";

revoke all on function "public"."_sales"(uuid, timestamptz, timestamptz, uuid) from public;

revoke all on function "public"._sales(p_arena uuid, p_from timestamptz, p_to timestamptz, p_id uuid) from anon;

revoke all on function "public"._sales(p_arena uuid, p_from timestamptz, p_to timestamptz, p_id uuid) from authenticated;
