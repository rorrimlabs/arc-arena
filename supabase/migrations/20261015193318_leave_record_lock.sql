set local check_function_bodies = off;

create or replace function public.op_leave_record (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_today  date := _pr_ist_date(statement_timestamp());
  v_rules  jsonb := _leave_rules(p_arena);
  v_staff  uuid := (p->>'staff_id')::uuid;
  v_from   date := (p->>'from_date')::date;
  v_to     date := (p->>'to_date')::date;
  v_half   text := coalesce(p->>'half_day', 'none');
  v_paid_b boolean := (p->>'paid')::boolean;
  v_reason text := coalesce(nullif(btrim(coalesce(p->>'reason', '')), ''), 'Recorded by a manager');
  v_days   numeric;
  v_paid   numeric;
  v_split  jsonb;
begin
  perform _need(p_arena, 'leave_approve');
  -- Locking the person queues two records (or a record and their own request) for them, so the
  -- overlap check below sees the other one.
  perform 1 from staff_profiles where id = v_staff and arena_id = p_arena and active for update;
  if v_staff is null or not found then raise exception 'not_found' using hint = 'staff'; end if;
  perform _own_record(p_arena, v_staff);
  if v_paid_b is null then raise exception 'invalid_payload' using hint = 'paid'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 92 then
    raise exception 'invalid_dates' using hint = 'from_date to to_date, at most 93 days';
  end if;
  if v_half not in ('none', 'first_half', 'second_half') then
    raise exception 'invalid_payload' using hint = 'half_day';
  end if;
  if v_half <> 'none' and (v_from <> v_to or not (v_rules->>'half_day_allowed')::boolean) then
    raise exception 'half_day_not_allowed';
  end if;
  if _period_finalised(p_arena, v_from, v_to) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;
  if exists (select 1 from leave_requests where staff_id = v_staff
              and status in ('pending', 'approved', 'cancel_pending')
              and from_date <= v_to and to_date >= v_from) then
    raise exception 'leave_overlap';
  end if;
  select sum(units) into v_days from _leave_working_days(v_staff, v_from, v_to, v_half);
  if coalesce(v_days, 0) = 0 then
    raise exception 'no_working_days' using hint = 'those days are week-offs or holidays';
  end if;
  v_paid := case when v_paid_b then v_days else 0 end;
  -- Pin the paid days to the earliest working days, the rest is LOP (as op_leave_decide).
  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'units', d.units,
           'paid_units', greatest(0, least(d.units, v_paid - d.before))) order by d.day), '[]'::jsonb)
    into v_split
    from (select w.day, w.units,
                 coalesce(sum(w.units) over (order by w.day rows between unbounded preceding and 1 preceding), 0) as before
            from _leave_working_days(v_staff, v_from, v_to, v_half) w) d;
  insert into leave_requests(id, arena_id, staff_id, kind, from_date, to_date, half_day, days,
      paid_days, lop_days, day_split, reason, status, decided_by, decided_at, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff,
      case when v_from >= v_today then 'planned' else 'unplanned' end,
      v_from, v_to, v_half, v_days, v_paid, v_days - v_paid, v_split, v_reason, 'approved',
      auth.uid(), statement_timestamp(), auth.uid());
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
    values (p_arena, 'leave_request', (p->>'id')::uuid, 'record', v_reason,
            jsonb_build_object('paid_days', v_paid, 'lop_days', v_days - v_paid),
            auth.uid(), statement_timestamp());
  return jsonb_build_object('days', v_days, 'paid_days', v_paid, 'lop_days', v_days - v_paid);
end;
$function$;
