set local check_function_bodies = off;

create or replace function private.arena_bill_price (
  p_arena      uuid,
  p_id         uuid,
  p_ended_at   timestamp with time zone,
  p_started_at timestamp with time zone default null::timestamp with time zone
)
  returns bigint
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; v_started timestamptz; v_sched timestamptz; pol jsonb; seg record; q jsonb;
  v_sub bigint := 0; v_until timestamptz; v_end timestamptz; v_last_idx int;
  v_first_idx int; v_from timestamptz; v_start timestamptz;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can edit bills';
  end if;
  select pricing_snapshot, started_at, scheduled_end_at into v_snap, v_started, v_sched
    from sessions where id = p_id and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  v_from := coalesce(p_started_at, v_started);
  if p_ended_at is null or p_ended_at <= v_from then
    raise exception 'invalid_time' using hint = 'the end must be after the start';
  end if;
  pol := _pr_policy(v_snap);
  select min(idx) into v_first_idx from session_segments
   where session_id = p_id and coalesce(ended_at, 'infinity') > v_from;
  select max(idx) into v_last_idx from session_segments
   where session_id = p_id and started_at < p_ended_at;
  if v_first_idx is null or v_last_idx is null then return 0; end if;
  -- Past the booked end: billed to the booked end only, as _pr_session_bill does.
  if p_ended_at > v_sched then
    v_until := v_sched;
  end if;
  for seg in select * from session_segments
              where session_id = p_id and idx between v_first_idx and v_last_idx order by idx loop
    v_start := case when seg.idx = v_first_idx then v_from else seg.started_at end;
    v_end := case when seg.idx = v_last_idx then p_ended_at
                  else least(coalesce(seg.ended_at, p_ended_at), p_ended_at) end;
    if v_until is not null then
      continue when v_start >= v_until;
      v_end := least(v_end, v_until);
    end if;
    continue when v_end <= v_start;
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, v_start, v_end, v_from);
    continue when q is null;
    v_sub := v_sub + (q->>'subtotal')::bigint;
  end loop;
  return _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir');
end;
$function$;

create or replace function public._pr_session_bill (
  p_session  uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; v_started timestamptz; seg record; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}'; pol jsonb; v_by jsonb := '{}'::jsonb;
  v_sched timestamptz; v_last timestamptz; v_until timestamptz; v_end timestamptz;
begin
  select pricing_snapshot, started_at, scheduled_end_at into v_snap, v_started, v_sched
    from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  select max(coalesce(ended_at, p_open_end)) into v_last
    from session_segments where session_id = p_session;
  -- Played past the booked end: bill to the booked end only.
  if v_last > v_sched then
    v_until := v_sched;
  end if;
  for seg in select * from session_segments where session_id = p_session order by idx loop
    v_end := coalesce(seg.ended_at, p_open_end);
    if v_until is not null then
      continue when seg.started_at >= v_until;   -- wholly inside the forgiven overtime
      v_end := least(v_end, v_until);
    end if;
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      v_end, v_started);   -- pricing rule judged at the session start
    continue when q is null;     -- no rate: contributes nothing (device warns)
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_by := jsonb_set(v_by, array[seg.activity_code], to_jsonb(coalesce((v_by->>seg.activity_code)::bigint, 0) + (q->>'subtotal')::bigint));
    v_keys := v_keys || _pr_keys(q, seg.activity_code, seg.resource_id, seg.controller_count);
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')),
    'by_activity', v_by);
end;
$function$;
