-- op_salary_run_set_deduction — sync op 'salary_run.set_deduction': keep or waive a deduction
--
-- Permission: payroll.
-- Payload: run_id, staff_id, code (absent | lop_leave | half_day | late), applied (bool),
--   note (optional). The owner decides each suggested reduction (OWNER_CONFIRMATION S23); the
--   choice survives recalculation.
-- Checks / errors: forbidden; not_found (run / line); run_not_draft; invalid_payload.
-- Writes: salary_deduction_decisions (upsert); the person's line and the run totals.
-- Returns: {net_paise}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_run_set_deduction (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  r       salary_runs;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_code  text := p->>'code';
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'run_id')::uuid);
  if v_code is null or v_code not in ('absent', 'lop_leave', 'half_day', 'late')
     or (p->>'applied') is null then
    raise exception 'invalid_payload' using hint = 'code and applied';
  end if;
  if not exists (select 1 from salary_run_lines where run_id = r.id and staff_id = v_staff) then
    raise exception 'not_found' using hint = 'line';
  end if;
  insert into salary_deduction_decisions(arena_id, run_id, staff_id, code, applied, note, decided_by)
    values (p_arena, r.id, v_staff, v_code, (p->>'applied')::boolean,
            nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid())
  on conflict (run_id, staff_id, code) do update set applied = excluded.applied,
      note = excluded.note, decided_by = excluded.decided_by, decided_at = statement_timestamp();
  perform _pay_rebuild_run(r.id, v_staff);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = v_staff));
end;
$function$;

comment on function public.op_salary_run_set_deduction(uuid, jsonb) is 'Sync op salary_run.set_deduction: the owner keeps or waives one suggested deduction of a person in a draft run (payroll).';

grant execute on function "public"."op_salary_run_set_deduction"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_run_set_deduction"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_run_set_deduction"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_run_set_deduction"(uuid, jsonb) from authenticated;
