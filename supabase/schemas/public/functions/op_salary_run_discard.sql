-- op_salary_run_discard — sync op 'salary_run.discard': throw away a draft run
--
-- Permission: payroll_finalise. Payload: id. The run is kept, marked discarded; its period is
-- free for a new run.
-- Checks / errors: forbidden; not_found; run_not_draft.
-- Writes: salary_runs.status = discarded. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_run_discard (
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
  perform _need(p_arena, 'payroll_finalise');
  r := _pay_draft(p_arena, (p->>'id')::uuid);
  update salary_runs set status = 'discarded' where id = r.id;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_salary_run_discard(uuid, jsonb) is 'Sync op salary_run.discard: mark a draft salary run discarded (payroll_finalise).';

grant execute on function "public"."op_salary_run_discard"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_run_discard"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_run_discard"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_run_discard"(uuid, jsonb) from authenticated;
