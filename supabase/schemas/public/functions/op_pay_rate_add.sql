-- op_pay_rate_add — sync op 'pay_rate.add': a staff member's pay from a date
--
-- Permission: payroll.
-- Payload: id (client uuid), staff_id, effective_from, pay_type (monthly | daily | hourly),
--   base_paise (whole paise >= 0), extra_hours_paid (bool), extra_hourly_paise (optional, only
--   with extra_hours_paid), note.
-- Checks / errors: forbidden; not_found (hint staff); own_record (your own pay, unless role owner); invalid_rate (hint names the field);
--   rate_in_finalised_period (effective_from on or before the end of a finalised run — past
--   pay never changes); duplicate (a rate on that date already).
-- Writes: staff_pay_rates (append-only). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_pay_rate_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff uuid := (p->>'staff_id')::uuid;
  v_from  date := (p->>'effective_from')::date;
  v_type  text := p->>'pay_type';
  v_base  numeric := (p->>'base_paise')::numeric;
  v_paid  boolean := coalesce((p->>'extra_hours_paid')::boolean, false);
  v_xrate numeric := (p->>'extra_hourly_paise')::numeric;
begin
  perform _need(p_arena, 'payroll');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  perform _own_record(p_arena, v_staff);
  if v_from is null then raise exception 'invalid_rate' using hint = 'effective_from'; end if;
  if v_type is null or v_type not in ('monthly', 'daily', 'hourly') then
    raise exception 'invalid_rate' using hint = 'pay_type: monthly, daily or hourly';
  end if;
  if v_base is null or v_base < 0 or v_base % 1 <> 0 then
    raise exception 'invalid_rate' using hint = 'base_paise: whole paise';
  end if;
  if v_xrate is not null and (not v_paid or v_xrate < 0 or v_xrate % 1 <> 0) then
    raise exception 'invalid_rate' using hint = 'extra_hourly_paise: whole paise, with extra_hours_paid';
  end if;
  if exists (select 1 from salary_runs where arena_id = p_arena and status = 'finalised'
              and period_end >= v_from) then
    raise exception 'rate_in_finalised_period'
      using hint = 'pay up to ' || (select max(period_end) from salary_runs
                                    where arena_id = p_arena and status = 'finalised') || ' is finalised';
  end if;
  insert into staff_pay_rates(id, arena_id, staff_id, effective_from, pay_type, base_paise,
      extra_hours_paid, extra_hourly_paise, note, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff, v_from, v_type, v_base::bigint, v_paid,
      v_xrate::bigint, nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid());
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_pay_rate_add(uuid, jsonb) is 'Sync op pay_rate.add: a staff member''s pay (monthly / daily / hourly, extra hours) from a date after the last finalised run.';

grant execute on function "public"."op_pay_rate_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_pay_rate_add"(uuid, jsonb) from public;

revoke all on function "public"."op_pay_rate_add"(uuid, jsonb) from anon;

revoke all on function "public"."op_pay_rate_add"(uuid, jsonb) from authenticated;
