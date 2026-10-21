-- op_shift_upsert — sync op 'shift.upsert': create or edit a named shift
--
-- Permission: settings.
-- Payload: id (client uuid), name, start_min, end_min (0–1439, minutes after IST midnight;
--   end <= start = ends next day), days (ISO 1–7, at least one), break_min (0–719), active.
-- Refuses shift_in_use (hint names the people) when turning a shift off that someone is still
--   assigned from today on: end those assignments first.
-- Checks / errors: forbidden; invalid_shift (hint names the field); duplicate (name taken).
-- Writes: shifts (insert, or update by id within the arena). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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

comment on function public.op_shift_upsert(uuid, jsonb) is 'Sync op shift.upsert: create or edit a named shift (IST start/end minutes, weekdays, unpaid break, active).';

grant execute on function "public"."op_shift_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_shift_upsert"(uuid, jsonb) from public;

revoke all on function "public"."op_shift_upsert"(uuid, jsonb) from anon;

revoke all on function "public"."op_shift_upsert"(uuid, jsonb) from authenticated;
