set local check_function_bodies = off;

create or replace function public.op_shift_assign (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_shift uuid := (p->>'shift_id')::uuid;
  v_from  date := (p->>'effective_from')::date;
  v_to    date := (p->>'effective_to')::date;
  v_old   staff_shifts;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if v_from is null then raise exception 'invalid_payload' using hint = 'effective_from'; end if;
  if v_to is not null and v_to < v_from then
    raise exception 'invalid_payload' using hint = 'effective_to is before effective_from';
  end if;
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if not exists (select 1 from shifts where id = v_shift and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'shift';
  end if;
  select * into v_old from staff_shifts where id = v_id and arena_id = p_arena for update;
  if v_old.id is null and not exists (select 1 from shifts where id = v_shift and active) then
    raise exception 'shift_inactive' using hint = 'turn the shift back on before assigning it';
  end if;
  -- Paid days never change: a new assignment, or the days an edit moves, may not touch a
  -- finalised period (a change of person or shift moves all of its days).
  if v_old.id is null then
    if _period_finalised(p_arena, v_from, coalesce(v_to, 'infinity'::date)) then
      raise exception 'period_finalised' using hint = 'pay for some of those days is finalised';
    end if;
  elsif ((v_old.staff_id is distinct from v_staff or v_old.shift_id is distinct from v_shift)
         and _period_finalised(p_arena, least(v_old.effective_from, v_from),
               greatest(coalesce(v_old.effective_to, 'infinity'::date), coalesce(v_to, 'infinity'::date))))
     or (v_old.effective_from is distinct from v_from
         and _period_finalised(p_arena, least(v_old.effective_from, v_from),
               greatest(v_old.effective_from, v_from)))
     or (v_old.effective_to is distinct from v_to
         and _period_finalised(p_arena,
               least(coalesce(v_old.effective_to, 'infinity'::date), coalesce(v_to, 'infinity'::date)),
               greatest(coalesce(v_old.effective_to, 'infinity'::date), coalesce(v_to, 'infinity'::date)))) then
    raise exception 'period_finalised' using hint = 'pay for some of those days is finalised';
  end if;
  begin
    insert into staff_shifts(id, arena_id, staff_id, shift_id, effective_from, effective_to)
      values (v_id, p_arena, v_staff, v_shift, v_from, v_to)
    on conflict (id) do update set staff_id = excluded.staff_id, shift_id = excluded.shift_id,
        effective_from = excluded.effective_from, effective_to = excluded.effective_to
      where staff_shifts.arena_id = p_arena;
  exception when exclusion_violation then
    raise exception 'assignment_overlap' using hint = 'this person already has this shift on some of those days';
  end;
  if not found then raise exception 'not_found' using hint = 'assignment'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_shift_unassign (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_today date := _pr_ist_date(statement_timestamp());
begin
  perform _need(p_arena, 'settings');
  -- Ending keeps the days already worked under it (they stay scheduled shift days); only an
  -- assignment that has not started yet is deleted.
  update staff_shifts set effective_to = v_today - 1, updated_at = statement_timestamp()
   where id = (p->>'id')::uuid and arena_id = p_arena and effective_from < v_today
     and (effective_to is null or effective_to >= v_today);
  delete from staff_shifts where id = (p->>'id')::uuid and arena_id = p_arena
     and effective_from >= v_today;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_shift_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_name  text := btrim(coalesce(p->>'name', ''));
  v_start int; v_end int; v_break int;
  v_days  smallint[];
  v_who   text;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_shift' using hint = 'id'; end if;
  if v_name = '' or length(v_name) > 60 then
    raise exception 'invalid_shift' using hint = 'name: 1–60 characters';
  end if;
  begin
    v_start := (p->>'start_min')::int; v_end := (p->>'end_min')::int;
    v_break := coalesce((p->>'break_min')::int, 0);
  exception when others then
    raise exception 'invalid_shift' using hint = 'start_min, end_min and break_min are whole minutes';
  end;
  if v_start is null or v_end is null or v_start not between 0 and 1439
     or v_end not between 0 and 1439 or v_start = v_end then
    raise exception 'invalid_shift' using hint = 'start_min and end_min: 0–1439, not equal';
  end if;
  if v_break not between 0 and 719 then
    raise exception 'invalid_shift' using hint = 'break_min: 0–719';
  end if;
  if jsonb_typeof(p->'days') is distinct from 'array' then
    raise exception 'invalid_shift' using hint = 'days';
  end if;
  select array_agg(distinct (d)::smallint order by (d)::smallint) into v_days
    from jsonb_array_elements_text(p->'days') d;
  if v_days is null or not (v_days <@ array[1,2,3,4,5,6,7]::smallint[]) then
    raise exception 'invalid_shift' using hint = 'days: one or more of 1–7';
  end if;
  -- "Not in use" never silently changes a roster: a shift still assigned from today on must
  -- have those assignments ended first (they keep scheduling until their end date).
  if coalesce((p->>'active')::boolean, true) = false
     and exists (select 1 from shifts where id = v_id and arena_id = p_arena and active) then
    select string_agg(distinct sp.name, ', ') into v_who
      from staff_shifts ss join staff_profiles sp on sp.id = ss.staff_id
     where ss.shift_id = v_id and ss.arena_id = p_arena
       and (ss.effective_to is null or ss.effective_to >= _pr_ist_date(statement_timestamp()));
    if v_who is not null then
      raise exception 'shift_in_use' using hint = v_who;
    end if;
  end if;
  insert into shifts(id, arena_id, name, start_min, end_min, days, break_min, active)
    values (v_id, p_arena, v_name, v_start, v_end, v_days, v_break,
            coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, start_min = excluded.start_min,
      end_min = excluded.end_min, days = excluded.days, break_min = excluded.break_min,
      active = excluded.active
    where shifts.arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'shift'; end if;
  return '{}'::jsonb;
end;
$function$;
