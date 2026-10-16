-- _pay_rebuild_run(run, staff) — rebuild a draft run's lines and totals
--
-- Refreshes rules_snapshot (work_hours, attendance, leave_rules and the pay rules in force on
-- period_start), rebuilds the line of p_staff (or of every staff profile of the arena when
-- null) with _pay_build_line, then the run's totals. Callers lock the run and check it is a
-- draft. Returns the number of lines.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pay_rebuild_run (
  p_run   uuid,
  p_staff uuid
)
  returns integer
  language plpgsql
  set search_path to 'public'
  AS $function$
declare r salary_runs; v_s uuid; v_n int;
begin
  select * into r from salary_runs where id = p_run;
  update salary_runs set rules_snapshot = jsonb_build_object(
      'work_hours', _work_hours(r.arena_id), 'attendance', _attendance_rules(r.arena_id),
      'leave_rules', _leave_rules(r.arena_id), 'pay_policy', _pay_policy(r.arena_id, r.period_start))
   where id = p_run;
  for v_s in select id from staff_profiles
              where arena_id = r.arena_id and (p_staff is null or id = p_staff) loop
    perform _pay_build_line(p_run, v_s);
  end loop;
  update salary_runs s set computed_at = statement_timestamp(),
      staff_count = t.n, gross_paise = t.g, deductions_paise = t.d,
      adjustments_paise = t.a, net_paise = t.net
    from (select count(*)::int as n, coalesce(sum(gross_paise), 0) as g,
                 coalesce(sum(deductions_paise), 0) as d, coalesce(sum(adjustments_paise), 0) as a,
                 coalesce(sum(net_paise), 0) as net
            from salary_run_lines where run_id = p_run) t
   where s.id = p_run
  returning s.staff_count into v_n;
  return v_n;
end;
$function$;

comment on function public._pay_rebuild_run(uuid, uuid) is 'Internal: refresh a draft salary run''s rules snapshot, rebuild one or every line, and recompute its totals.';

grant execute on function "public"."_pay_rebuild_run"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_pay_rebuild_run"(uuid, uuid) from public;

revoke all on function "public"."_pay_rebuild_run"(uuid, uuid) from anon;

revoke all on function "public"."_pay_rebuild_run"(uuid, uuid) from authenticated;
