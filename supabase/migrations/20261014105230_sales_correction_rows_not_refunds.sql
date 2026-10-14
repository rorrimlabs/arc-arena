set local check_function_bodies = off;

create or replace function public._sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone,
  p_id    uuid                     default null::uuid
)
  returns SETOF jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
      'kind', 'single', 'id', s.id, 'at', b.at,
      'started_at', s.started_at, 'ended_at', s.actual_ended_at, 'recorded_at', s.created_at,
      'status', s.status, 'payment_status', s.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = s.customer_id and o.arena_id = s.arena_id
                   and o.id <> s.id and o.status = 'completed' and o.started_at < s.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = s.customer_id and o.arena_id = s.arena_id
                      and o.status = 'completed' and o.started_at < s.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', seg.players, 'player_minutes', seg.player_minutes,
      'billed_paise', s.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', s.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by)
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
                        where g.session_id = s.id), 1) as players,
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0 * coalesce(g.controller_count, 1)))::int
                         from session_segments g where g.session_id = s.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from payments
                                where session_id = s.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.kind = 'refund', 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.session_id = s.id), '[]'::jsonb) as ledger
        from payments p where p.session_id = s.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
   where s.arena_id = p_arena and s.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else s.id = p_id end)
  union all
  select jsonb_build_object(
      'kind', 'group', 'id', gs.id, 'at', b.at,
      'started_at', gs.started_at, 'ended_at', gs.actual_ended_at, 'recorded_at', gs.created_at,
      'status', gs.status, 'payment_status', gs.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                   and o.status = 'completed' and o.started_at < gs.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                      and o.id <> gs.id and o.status = 'completed' and o.started_at < gs.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', gs.player_count, 'player_minutes', seg.player_minutes,
      'billed_paise', gs.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', gs.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by)
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
                                where g.group_id = gs.id group by gm.name) x), '[]'::jsonb) as games,
             -- Each assignment is one player's stretch on one station.
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0))::int
                         from group_assignments g where g.group_id = gs.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from group_payments
                                where group_id = gs.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.is_refund, 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from group_payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.group_id = gs.id), '[]'::jsonb) as ledger
        from group_payments p where p.group_id = gs.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
   where gs.arena_id = p_arena and gs.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else gs.id = p_id end);
$function$;
