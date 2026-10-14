set local check_function_bodies = off;

create or replace function private.arena_activity (
  p_arena    uuid,
  p_resource uuid,
  p_customer uuid,
  p_since    timestamp with time zone,
  p_limit    integer                  default 6
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
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read play history';
  end if;
  if (p_resource is null) = (p_customer is null) then
    raise exception 'invalid' using hint = 'one of station or member';
  end if;

  with pl as (
    select 'single' as kind, g.session_id as bill_id, s.status, s.customer_id, g.resource_id,
           g.game_id, g.started_at, s.billed_amount_paise as billed
      from session_segments g join sessions s on s.id = g.session_id
     where g.arena_id = p_arena and (g.started_at >= p_since or g.ended_at is null)
       and (g.resource_id = p_resource or s.customer_id = p_customer)
    union all
    select 'group', a.group_id, gs.status, gs.primary_customer_id, a.resource_id, a.game_id,
           a.started_at, gs.billed_amount_paise
      from group_assignments a join group_sessions gs on gs.id = a.group_id
     where a.arena_id = p_arena and (a.started_at >= p_since or a.ended_at is null)
       and (a.resource_id = p_resource or gs.primary_customer_id = p_customer)
  ), latest as (
    select distinct on (kind, bill_id) * from pl order by kind, bill_id, started_at desc
  )
  select jsonb_build_object(
    'bills', coalesce((select jsonb_agg(jsonb_build_object('bill_id', l.bill_id, 'kind', l.kind,
        'started_at', l.started_at, 'status', l.status, 'billed_paise', l.billed,
        'customer', case when c.is_guest then null else c.name end, 'station', r.name,
        'game', gm.name) order by l.started_at desc, l.bill_id)
        from (select * from latest order by started_at desc, bill_id
               limit least(greatest(coalesce(p_limit, 6), 1), 50)) l
        left join customers c on c.id = l.customer_id
        left join resources r on r.id = l.resource_id
        left join games gm on gm.id = l.game_id), '[]'::jsonb),
    'games', case when p_customer is null then '[]'::jsonb else coalesce((
        select jsonb_agg(jsonb_build_object('game_id', t.game_id, 'name', gm.name,
            'minutes', round(t.minutes)) order by t.minutes desc, gm.name)
          from (select game_id, sum(minutes) as minutes from _plays(p_arena, p_since)
                 where customer_id = p_customer and game_id is not null group by game_id) t
          join games gm on gm.id = t.game_id), '[]'::jsonb) end)
    into v_out;
  return v_out;
end;
$function$;

create or replace function private.arena_game_fans (
  p_arena uuid,
  p_game  uuid,
  p_since timestamp with time zone,
  p_limit integer                  default 4
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

create or replace function private.arena_members (
  p_arena    uuid,
  p_since    timestamp with time zone,
  p_since_30 timestamp with time zone,
  p_search   text                     default null::text,
  p_limit    integer                  default 50,
  p_offset   integer                  default 0
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_q      text := nullif(lower(btrim(coalesce(p_search, ''))), '');
  v_digits text := nullif(regexp_replace(coalesce(p_search, ''), '\D', '', 'g'), '');
  v_out    jsonb;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read members';
  end if;

  with m as (
    select c.* from customers c
     where c.arena_id = p_arena and not c.is_guest
       and (v_q is null or position(v_q in lower(c.name)) > 0
            or (v_digits is not null
                and position(v_digits in regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')) > 0))
  ), b as (
    select s.customer_id as cid, s.started_at, s.billed_amount_paise as billed from sessions s
     where s.arena_id = p_arena and s.status <> 'voided' and (s.started_at >= p_since or s.status = 'active')
    union all
    select g.primary_customer_id, g.started_at, g.billed_amount_paise from group_sessions g
     where g.arena_id = p_arena and g.status <> 'voided' and (g.started_at >= p_since or g.status = 'active')
  ), pl as (
    select customer_id, sum(minutes) as minutes from _plays(p_arena, p_since) group by customer_id
  ), s as (
    select m.id, m.name, m.phone, m.birth_year, m.created_at,
           (select count(*) from b where b.cid = m.id) as visits,
           coalesce((select round(pl.minutes) from pl where pl.customer_id = m.id), 0) as minutes,
           coalesce((select sum(b.billed) from b where b.cid = m.id and b.started_at >= p_since_30), 0)
             as spent,
           greatest(m.last_visit_at, (select max(b.started_at) from b where b.cid = m.id)) as last_visit
      from m
  )
  select jsonb_build_object(
    'total', (select count(*) from s),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'phone', phone,
        'birth_year', birth_year, 'created_at', created_at, 'visits', visits, 'minutes', minutes,
        'spent_30_paise', spent, 'last_visit', last_visit) order by last_visit desc nulls last, name, id)
        from (select * from s order by last_visit desc nulls last, name, id
               limit least(greatest(coalesce(p_limit, 50), 1), 200)
               offset greatest(coalesce(p_offset, 0), 0)) p), '[]'::jsonb))
    into v_out;
  return v_out;
end;
$function$;

create or replace function private.arena_overview (
  p_arena     uuid,
  p_from      timestamp with time zone,
  p_to        timestamp with time zone,
  p_prev_from timestamp with time zone,
  p_prev_to   timestamp with time zone,
  p_bucket    text,
  p_today     timestamp with time zone
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
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read sales';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '400 days'
     or p_prev_from is null or p_prev_to is null or p_prev_to < p_prev_from
     or p_prev_to - p_prev_from > interval '400 days'
     or p_bucket is null or p_bucket not in ('hour', 'day', 'month') then
    raise exception 'invalid_range' using hint = 'up to 400 days; bucket hour, day or month';
  end if;

  with cur as (
    select x as b, (x->>'at')::timestamptz as at from _sales(p_arena, p_from, p_to) x
  ), live as (
    select b, at from cur where b->>'status' <> 'voided'
  ), prev as (
    select x as b from _sales(p_arena, p_prev_from, p_prev_to) x where x->>'status' <> 'voided'
  )
  select jsonb_build_object(
    'totals', (select jsonb_build_object(
        'takings_paise', coalesce(sum((b->>'paid_paise')::bigint), 0),
        'bills', count(*),
        'minutes', coalesce(sum(_bill_minutes(b)), 0),
        'discount_paise', coalesce(sum((b->>'discount_paise')::bigint), 0),
        'discounts', count(*) filter (where (b->>'discount_paise')::bigint > 0)) from live),
    'previous', (select jsonb_build_object(
        'takings_paise', coalesce(sum((b->>'paid_paise')::bigint), 0),
        'bills', count(*),
        'minutes', coalesce(sum(_bill_minutes(b)), 0)) from prev),
    'buckets', coalesce((select jsonb_agg(jsonb_build_object('start', k, 'paise', paise) order by k)
        from (select date_trunc(p_bucket, at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' as k,
                     sum((b->>'paid_paise')::bigint) as paise
                from live group by 1) t), '[]'::jsonb),
    'methods', coalesce((select jsonb_object_agg(m, jsonb_build_object('paise', paise, 'bills', bills))
        from (select e.key as m, sum(e.value::bigint) as paise,
                     count(*) filter (where e.value::bigint > 0) as bills
                from live, jsonb_each_text(b->'methods') e group by e.key) t), '{}'::jsonb),
    'by_type', coalesce((select jsonb_object_agg(code, paise)
        from (select activity_code as code, sum(amount_paise) as paise from (
                select ch.activity_code, ch.amount_paise from session_charges ch
                  join sessions s on s.id = ch.session_id
                 where ch.arena_id = p_arena and s.status <> 'voided'
                   and ch.segment_start >= p_from and ch.segment_start < p_to
                union all
                select ch.activity_code, ch.amount_paise from group_charges ch
                  join group_sessions g on g.id = ch.group_id
                 where ch.arena_id = p_arena and g.status <> 'voided'
                   and ch.segment_start >= p_from and ch.segment_start < p_to) c
              group by activity_code) t), '{}'::jsonb),
    'top_games', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'minutes', round(minutes))
                             order by minutes desc, name)
        from (select g.value as name,
                     sum(_bill_minutes(b)::numeric / jsonb_array_length(b->'games')) as minutes
                from live, jsonb_array_elements_text(b->'games') g
               group by g.value order by 2 desc, 1 limit 5) t), '[]'::jsonb),
    'by_staff', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'bills', bills, 'paise', paise)
                            order by paise desc, name)
        from (select b->>'started_by' as name, count(*) as bills,
                     sum((b->>'paid_paise')::bigint) as paise
                from live where b->>'started_by' is not null group by 1) t), '[]'::jsonb),
    'latest', coalesce((select jsonb_agg(b order by at desc, b->>'id' desc)
        from (select b, at from cur where at >= p_today order by at desc, b->>'id' desc limit 8) t),
        '[]'::jsonb))
  into v_out;
  return v_out;
end;
$function$;

create or replace function private.arena_station_stats (
  p_arena uuid,
  p_today timestamp with time zone,
  p_since timestamp with time zone,
  p_to    timestamp with time zone
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
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read station figures';
  end if;
  if p_since is null or p_today is null or p_to is null or p_to <= p_since
     or p_to - p_since > interval '400 days' then
    raise exception 'invalid_range' using hint = 'up to 400 days';
  end if;

  with ch as (
    select ch.resource_id, ch.segment_start, ch.amount_paise from session_charges ch
      join sessions s on s.id = ch.session_id
     where ch.arena_id = p_arena and s.status <> 'voided'
       and ch.segment_start >= p_since and ch.segment_start < p_to
    union all
    select ch.resource_id, ch.segment_start, ch.amount_paise from group_charges ch
      join group_sessions g on g.id = ch.group_id
     where ch.arena_id = p_arena and g.status <> 'voided'
       and ch.segment_start >= p_since and ch.segment_start < p_to
  ), pl as (
    select * from _plays(p_arena, p_since)
  )
  select coalesce(jsonb_object_agg(r.id, jsonb_build_object(
      'billed_today', coalesce((select sum(amount_paise) from ch
                                 where ch.resource_id = r.id and ch.segment_start >= p_today), 0),
      'sessions_today', (select count(distinct (pl.kind, pl.bill_id)) from pl
                          where pl.resource_id = r.id and pl.started_at >= p_today),
      'minutes_30', coalesce((select round(sum(pl.minutes)) from pl
                               where pl.resource_id = r.id and pl.started_at >= p_since), 0),
      'billed_30', coalesce((select sum(amount_paise) from ch where ch.resource_id = r.id), 0),
      'accessories', (select count(*) from controllers c
                       where c.home_resource_id = r.id and c.status <> 'retired'))), '{}'::jsonb)
    into v_out
    from resources r where r.arena_id = p_arena;
  return v_out;
end;
$function$;

create or replace function public._bill_minutes (
  b jsonb
)
  returns bigint
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select greatest(0, round(extract(epoch from (
    coalesce(b->>'ended_at', b->>'at')::timestamptz - (b->>'started_at')::timestamptz)) / 60))::bigint;
$function$;

create or replace function public._plays (
  p_arena uuid,
  p_since timestamp with time zone
)
  returns table (
    kind          text,
    bill_id       uuid,
    bill_status   text,
    customer_id   uuid,
    resource_id   uuid,
    activity_code text,
    game_id       uuid,
    started_at    timestamp with time zone,
    ended_at      timestamp with time zone,
    minutes       numeric
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select 'single', g.session_id, s.status, s.customer_id, g.resource_id, g.activity_code, g.game_id,
         g.started_at, g.ended_at,
         greatest(0, extract(epoch from (coalesce(g.ended_at, now()) - g.started_at)) / 60)
    from session_segments g join sessions s on s.id = g.session_id
   where g.arena_id = p_arena and s.status <> 'voided'
     and (g.started_at >= p_since or g.ended_at is null)
  union all
  select 'group', a.group_id, gs.status, gs.primary_customer_id, a.resource_id, a.activity_code,
         a.game_id, a.started_at, a.ended_at,
         greatest(0, extract(epoch from (coalesce(a.ended_at, now()) - a.started_at)) / 60)
    from group_assignments a join group_sessions gs on gs.id = a.group_id
   where a.arena_id = p_arena and gs.status <> 'voided'
     and (a.started_at >= p_since or a.ended_at is null);
$function$;

create or replace function public.arena_activity (
  p_arena    uuid,
  p_resource uuid,
  p_customer uuid,
  p_since    timestamp with time zone,
  p_limit    integer                  default 6
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_activity(p_arena, p_resource, p_customer, p_since, p_limit);
$function$;

create or replace function public.arena_game_fans (
  p_arena uuid,
  p_game  uuid,
  p_since timestamp with time zone,
  p_limit integer                  default 4
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_game_fans(p_arena, p_game, p_since, p_limit);
$function$;

create or replace function public.arena_game_stats (
  p_arena uuid,
  p_since timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_game_stats(p_arena, p_since);
$function$;

create or replace function public.arena_members (
  p_arena    uuid,
  p_since    timestamp with time zone,
  p_since_30 timestamp with time zone,
  p_search   text                     default null::text,
  p_limit    integer                  default 50,
  p_offset   integer                  default 0
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_members(p_arena, p_since, p_since_30, p_search, p_limit, p_offset);
$function$;

create or replace function public.arena_overview (
  p_arena     uuid,
  p_from      timestamp with time zone,
  p_to        timestamp with time zone,
  p_prev_from timestamp with time zone,
  p_prev_to   timestamp with time zone,
  p_bucket    text,
  p_today     timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_overview(p_arena, p_from, p_to, p_prev_from, p_prev_to, p_bucket, p_today);
$function$;

create or replace function public.arena_station_stats (
  p_arena uuid,
  p_today timestamp with time zone,
  p_since timestamp with time zone,
  p_to    timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_station_stats(p_arena, p_today, p_since, p_to);
$function$;

comment on function "private"."arena_activity"(uuid, uuid, uuid, timestamp
  with time zone, integer) is 'Client API (owner level): a station''s or member''s newest bills and (for a member) minutes per game, read when the dashboard opens it.';

comment on function "private"."arena_game_fans"(uuid, uuid, timestamp
  with time zone, integer) is 'Client API (owner level): the members who played a game the most since an instant, aggregated on the server.';

comment on function "private"."arena_game_stats"(uuid, timestamp
  with time zone) is 'Client API (owner level): per-game minutes, bills and stations playing it now, aggregated on the server.';

comment on function "private"."arena_members"(uuid, timestamp with time zone, timestamp
  with time zone, text, integer, integer) is 'Client API (owner level): one searched page of registered members with their visits, minutes, 30-day spend and last visit, aggregated on the server.';

comment on function "private"."arena_overview"(uuid, timestamp with time zone, timestamp
  with time zone,
  timestamp with time zone,
  timestamp with time zone, text, timestamp with time zone) is 'Client API (owner level): the Overview''s aggregated figures for a period and the one before it (totals, takings buckets, payment split, by type, top games, by staff, latest bills).';

comment on function "private"."arena_station_stats"(uuid, timestamp with time zone, timestamp
  with time zone, timestamp with time zone) is 'Client API (owner level): per-station billed today / 30 days, sessions today, minutes played and accessory count, aggregated on the server.';

comment on function "public"."_bill_minutes"(jsonb) is 'Internal (dashboard reads): whole minutes from a _sales bill''s start to its end or close.';

comment on function "public"."_plays"(uuid, timestamp with time zone) is 'Internal (dashboard reads): segments and group assignments of non-voided bills started since an instant or still open, with minutes played.';

comment on function "public"."arena_activity"(uuid, uuid, uuid, timestamp
  with time zone, integer) is 'Client API (owner level): a station''s or member''s newest bills and (for a member) minutes per game, read when the dashboard opens it.';

comment on function "public"."arena_game_fans"(uuid, uuid, timestamp
  with time zone, integer) is 'Client API (owner level): the members who played a game the most since an instant, aggregated on the server.';

comment on function "public"."arena_game_stats"(uuid, timestamp
  with time zone) is 'Client API (owner level): per-game minutes, bills and stations playing it now, aggregated on the server.';

comment on function "public"."arena_members"(uuid, timestamp with time zone, timestamp
  with time zone, text, integer, integer) is 'Client API (owner level): one searched page of registered members with their visits, minutes, 30-day spend and last visit, aggregated on the server.';

comment on function "public"."arena_overview"(uuid, timestamp with time zone, timestamp
  with time zone,
  timestamp with time zone,
  timestamp with time zone, text, timestamp with time zone) is 'Client API (owner level): the Overview''s aggregated figures for a period and the one before it (totals, takings buckets, payment split, by type, top games, by staff, latest bills).';

comment on function "public"."arena_station_stats"(uuid, timestamp with time zone, timestamp
  with time zone, timestamp with time zone) is 'Client API (owner level): per-station billed today / 30 days, sessions today, minutes played and accessory count, aggregated on the server.';

revoke all
  on function "private"."arena_activity"(uuid, uuid, uuid, timestamp with time zone, integer)
  from public;

grant execute
  on function "private"."arena_activity"(uuid, uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "private"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  from public;

grant execute
  on function "private"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_game_stats"(uuid, timestamp with time zone) from public;

grant execute
  on function "private"."arena_game_stats"(uuid, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "private"."arena_members"(uuid, timestamp with time zone, timestamp
    with time zone, text, integer, integer)
  from public;

grant execute
  on function "private"."arena_members"(uuid, timestamp with time zone, timestamp
    with time zone, text, integer, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "private"."arena_overview"(uuid, timestamp with time zone, timestamp
    with time zone,
    timestamp with time zone, timestamp with time zone, text, timestamp with time zone)
  from public;

grant execute
  on function "private"."arena_overview"(uuid, timestamp with time zone, timestamp
    with time zone,
    timestamp with time zone, timestamp with time zone, text, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "private"."arena_station_stats"(uuid, timestamp with time zone, timestamp
    with time zone, timestamp with time zone)
  from public;

grant execute
  on function "private"."arena_station_stats"(uuid, timestamp with time zone, timestamp
    with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."_bill_minutes"(jsonb) from public;

grant execute on function "public"."_bill_minutes"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_plays"(uuid, timestamp with time zone) from public;

grant execute
  on function "public"."_plays"(uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."arena_activity"(uuid, uuid, uuid, timestamp with time zone, integer)
  from public;

grant execute
  on function "public"."arena_activity"(uuid, uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  from public;

grant execute
  on function "public"."arena_game_fans"(uuid, uuid, timestamp with time zone, integer)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_game_stats"(uuid, timestamp with time zone) from public;

grant execute
  on function "public"."arena_game_stats"(uuid, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_members"(uuid, timestamp with time zone, timestamp
    with time zone, text, integer, integer)
  from public;

grant execute
  on function "public"."arena_members"(uuid, timestamp with time zone, timestamp
    with time zone, text, integer, integer)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_overview"(uuid, timestamp with time zone, timestamp
    with time zone,
    timestamp with time zone, timestamp with time zone, text, timestamp with time zone)
  from public;

grant execute
  on function "public"."arena_overview"(uuid, timestamp with time zone, timestamp
    with time zone,
    timestamp with time zone, timestamp with time zone, text, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_station_stats"(uuid, timestamp with time zone, timestamp
    with time zone, timestamp with time zone)
  from public;

grant execute
  on function "public"."arena_station_stats"(uuid, timestamp with time zone, timestamp
    with time zone, timestamp with time zone)
  to "authenticated", "postgres", "service_role";
