-- op_salary_adjustment_reverse — sync op 'salary_adjustment.reverse': undo an adjustment
--
-- Permission: payroll. Payload: id (client uuid of the reversal), reverses_id, note.
-- Adds the opposite amount as a reversal row (append-only; the original stays).
-- Checks / errors: forbidden; not_found; run_not_draft; note_required; already_reversed.
-- Writes: salary_adjustments; the person's line and the run totals. Returns: {net_paise}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_adjustment_reverse (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  a      salary_adjustments;
  r      salary_runs;
  v_note text := nullif(btrim(coalesce(p->>'note', '')), '');
begin
  perform _need(p_arena, 'payroll');
  select * into a from salary_adjustments
   where id = (p->>'reverses_id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'adjustment'; end if;
  r := _pay_draft(p_arena, a.run_id);
  if v_note is null then raise exception 'note_required'; end if;
  if a.kind = 'reversal' then raise exception 'invalid_payload' using hint = 'a reversal cannot be reversed'; end if;
  begin
    insert into salary_adjustments(id, arena_id, run_id, staff_id, kind, amount_paise, note,
        reverses_id, created_by)
      values ((p->>'id')::uuid, p_arena, a.run_id, a.staff_id, 'reversal', -a.amount_paise,
              v_note, a.id, auth.uid());
  exception when unique_violation then
    if exists (select 1 from salary_adjustments where reverses_id = a.id) then
      raise exception 'already_reversed';
    end if;
    raise;
  end;
  perform _pay_rebuild_run(r.id, a.staff_id);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = a.staff_id));
end;
$function$;

comment on function public.op_salary_adjustment_reverse(uuid, jsonb) is 'Sync op salary_adjustment.reverse: undo a salary adjustment with an opposite reversal row (payroll).';

grant execute on function "public"."op_salary_adjustment_reverse"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_adjustment_reverse"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_adjustment_reverse"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_adjustment_reverse"(uuid, jsonb) from authenticated;
