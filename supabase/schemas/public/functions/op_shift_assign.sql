-- op_shift_assign — sync op 'shift.assign': put a person on a shift for a date range
--
-- Permission: settings.
-- Payload: id (client uuid; resending with the same id edits the assignment), staff_id,
--   shift_id, effective_from, effective_to (inclusive, optional).
-- Checks / errors: forbidden; not_found (hint staff / shift); invalid_payload (hint names the
--   field); assignment_overlap (the person already has this shift on some of those days).
--   shift_inactive (a new assignment to a shift that is not in use); period_finalised (a new
--   assignment, or the days an edit moves, falls in a finalised salary period).
-- Writes: staff_shifts. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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

comment on function public.op_shift_assign(uuid, jsonb) is 'Sync op shift.assign: assign (or re-date) a staff profile to a shift for an inclusive date range.';

grant execute on function "public"."op_shift_assign"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_shift_assign"(uuid, jsonb) from public;

revoke all on function "public"."op_shift_assign"(uuid, jsonb) from anon;

revoke all on function "public"."op_shift_assign"(uuid, jsonb) from authenticated;
