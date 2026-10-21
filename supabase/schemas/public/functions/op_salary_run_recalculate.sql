-- op_salary_run_recalculate — sync op 'salary_run.recalculate': rebuild a draft from live data
--
-- Permission: payroll. Payload: id. Closes forgotten clock-ins, refreshes the rules snapshot
-- and rebuilds every line (keeping the owner's keep / waive decisions and adjustments).
-- Checks / errors: forbidden; not_found; run_not_draft.
-- Returns: {staff_count}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_run_recalculate (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare r salary_runs;
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'id')::uuid);
  perform _att_close_stale(p_arena, null, statement_timestamp());
  return jsonb_build_object('staff_count', _pay_rebuild_run(r.id, null));
end;
$function$;

comment on function public.op_salary_run_recalculate(uuid, jsonb) is 'Sync op salary_run.recalculate: rebuild a draft salary run from live attendance, leave and rates (payroll).';

grant execute on function "public"."op_salary_run_recalculate"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_run_recalculate"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_run_recalculate"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_run_recalculate"(uuid, jsonb) from authenticated;
