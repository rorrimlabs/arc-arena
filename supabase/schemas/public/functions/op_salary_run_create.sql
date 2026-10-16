-- op_salary_run_create — sync op 'salary_run.create': a draft salary run for a pay period
--
-- Permission: payroll.
-- Payload: id (client uuid), period_start, period_end (inclusive, at most 62 days).
-- Closes the arena's forgotten clock-ins first (_att_close_stale), then builds a line for
-- every person with a pay rate in force by period_end who was employed in the period.
-- Checks / errors: forbidden; invalid_period; run_overlap (a draft or finalised run covers some
--   of those days); duplicate (id reused).
-- Writes: salary_runs, salary_run_lines; attendance_entries (forgotten clock-ins closed).
-- Returns: {staff_count}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_run_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_from date := (p->>'period_start')::date;
  v_to   date := (p->>'period_end')::date;
begin
  perform _need(p_arena, 'payroll');
  if v_id is null or v_from is null or v_to is null or v_to < v_from or v_to - v_from >= 62 then
    raise exception 'invalid_period' using hint = 'period_start to period_end, at most 62 days';
  end if;
  perform _att_close_stale(p_arena, null, statement_timestamp());
  begin
    insert into salary_runs(id, arena_id, period_start, period_end, rules_snapshot, computed_at, created_by)
      values (v_id, p_arena, v_from, v_to, '{}'::jsonb, statement_timestamp(), auth.uid());
  exception when exclusion_violation then
    raise exception 'run_overlap' using hint = 'another salary run covers some of those days';
  end;
  return jsonb_build_object('staff_count', _pay_rebuild_run(v_id, null));
end;
$function$;

comment on function public.op_salary_run_create(uuid, jsonb) is 'Sync op salary_run.create: a draft salary run for a pay period, one line per paid staff member (payroll).';

grant execute on function "public"."op_salary_run_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_run_create"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_run_create"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_run_create"(uuid, jsonb) from authenticated;
