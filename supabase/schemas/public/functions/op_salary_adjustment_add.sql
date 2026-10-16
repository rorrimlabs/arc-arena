-- op_salary_adjustment_add — sync op 'salary_adjustment.add': a bonus, advance or deduction
--
-- Permission: payroll.
-- Payload: id (client uuid), run_id, staff_id, kind (bonus | advance | deduction),
--   amount_paise (whole paise > 0; stored negative for an advance or a deduction), note.
-- Checks / errors: forbidden; not_found (run / line); run_not_draft; note_required;
--   invalid_payload; duplicate (id reused).
-- Writes: salary_adjustments (append-only); the person's line and the run totals.
-- Returns: {net_paise}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_adjustment_add (
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
  v_kind  text := p->>'kind';
  v_amt   numeric := (p->>'amount_paise')::numeric;
  v_note  text := nullif(btrim(coalesce(p->>'note', '')), '');
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'run_id')::uuid);
  if v_note is null then raise exception 'note_required'; end if;
  if v_kind is null or v_kind not in ('bonus', 'advance', 'deduction') then
    raise exception 'invalid_payload' using hint = 'kind: bonus, advance or deduction';
  end if;
  if v_amt is null or v_amt <= 0 or v_amt % 1 <> 0 then
    raise exception 'invalid_payload' using hint = 'amount_paise: whole paise above 0';
  end if;
  if not exists (select 1 from salary_run_lines where run_id = r.id and staff_id = v_staff) then
    raise exception 'not_found' using hint = 'line';
  end if;
  insert into salary_adjustments(id, arena_id, run_id, staff_id, kind, amount_paise, note, created_by)
    values ((p->>'id')::uuid, p_arena, r.id, v_staff, v_kind,
            case when v_kind = 'bonus' then v_amt else -v_amt end::bigint, v_note, auth.uid());
  perform _pay_rebuild_run(r.id, v_staff);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = v_staff));
end;
$function$;

comment on function public.op_salary_adjustment_add(uuid, jsonb) is 'Sync op salary_adjustment.add: a bonus, advance or deduction with a note on a person in a draft run (payroll).';

grant execute on function "public"."op_salary_adjustment_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_adjustment_add"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_adjustment_add"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_adjustment_add"(uuid, jsonb) from authenticated;
