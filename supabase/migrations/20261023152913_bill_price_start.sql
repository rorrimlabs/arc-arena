set local check_function_bodies = off;

drop function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone);

drop function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone);

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
  v_sub bigint := 0; v_until timestamptz; v_end timestamptz; v_grace int; v_last_idx int;
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
  -- The overtime grace of the type it ends on, as _pr_session_bill reads it.
  select coalesce((a->>'overtime_grace_minutes')::int, 0) into v_grace
    from session_segments sg
    cross join lateral jsonb_array_elements(coalesce(v_snap->'activities', '[]'::jsonb)) a
   where sg.session_id = p_id and sg.idx = v_last_idx and a->>'code' = sg.activity_code;
  if coalesce(v_grace, 0) > 0 and p_ended_at > v_sched
     and p_ended_at - v_sched <= make_interval(mins => v_grace) then
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

create or replace function public.arena_bill_price (
  p_arena      uuid,
  p_id         uuid,
  p_ended_at   timestamp with time zone,
  p_started_at timestamp with time zone default null::timestamp with time zone
)
  returns bigint
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_bill_price(p_arena, p_id, p_ended_at, p_started_at);
$function$;

comment on function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
  with time zone) is 'Client API (owner level): the price of a closed single session had it run between the given times, on its frozen price list, for the admin dashboard''s Edit bill.';

comment on function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
  with time zone) is 'Client API (owner level): the price of a closed single session had it run between the given times, for the admin dashboard''s Edit bill.';

revoke all
  on function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  from public;

grant execute
  on function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  from public;

grant execute
  on function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
    with time zone)
  to "authenticated", "postgres", "service_role";
