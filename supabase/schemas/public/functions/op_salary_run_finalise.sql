-- op_salary_run_finalise — sync op 'salary_run.finalise': rebuild one last time, then lock
--
-- Permission: payroll_finalise. Payload: id.
-- From then on the run never changes, and attendance corrections and leave changes on its days
-- are refused (period_finalised); pay rates and rules cannot start inside it.
-- Checks / errors: forbidden; not_found; run_not_draft; period_not_over (the period ends after
--   today IST, or ends today while someone's shift that day has not happened yet: a run may end
--   on the pay date, but never pays days still to come); entries_open (a clock-in in the period
--   is still open, hint names the people); entries_pending_review (a flagged entry in the period
--   is not reviewed yet, hint names the people); net_negative (hint names the person).
-- Writes: salary_runs (finalised, finalised_by / at), its lines; audit_log (entity salary_run,
--   action finalise, after {net_paise, staff_count}). Returns: {net_paise}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_salary_run_finalise (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare r salary_runs; v_neg text; v_today date := _pr_ist_date(statement_timestamp()); v_who text;
begin
  perform _need(p_arena, 'payroll_finalise');
  r := _pay_draft(p_arena, (p->>'id')::uuid);
  if r.period_end > v_today
     or (r.period_end = v_today and exists (
           select 1 from salary_run_lines l where l.run_id = r.id
              and _att_day(l.staff_id, v_today, statement_timestamp())->>'status' = 'upcoming')) then
    raise exception 'period_not_over'
      using hint = 'the period ends ' || r.period_end || '; finalise once its last shifts are over';
  end if;
  perform _att_close_stale(p_arena, null, statement_timestamp());
  select string_agg(distinct s.name, ', ') into v_who
    from attendance_entries e join staff_profiles s on s.id = e.staff_id
   where e.arena_id = p_arena and e.status = 'active' and e.out_at is null
     and e.work_date between r.period_start and r.period_end;
  if v_who is not null then raise exception 'entries_open' using hint = v_who; end if;
  select string_agg(distinct s.name, ', ') into v_who
    from attendance_entries e join staff_profiles s on s.id = e.staff_id
   where e.arena_id = p_arena and e.status = 'active' and e.review = 'pending'
     and e.work_date between r.period_start and r.period_end;
  if v_who is not null then raise exception 'entries_pending_review' using hint = v_who; end if;
  perform _pay_rebuild_run(r.id, null);
  select string_agg(staff_name, ', ' order by staff_name) into v_neg
    from salary_run_lines where run_id = r.id and net_paise < 0;
  if v_neg is not null then
    raise exception 'net_negative' using hint = v_neg;
  end if;
  update salary_runs set status = 'finalised', finalised_by = auth.uid(),
      finalised_at = statement_timestamp()
   where id = r.id returning * into r;
  insert into audit_log(arena_id, entity_type, entity_id, action, after, created_by, created_at)
    values (p_arena, 'salary_run', r.id, 'finalise',
            jsonb_build_object('net_paise', r.net_paise, 'staff_count', r.staff_count,
                               'period_start', r.period_start, 'period_end', r.period_end),
            auth.uid(), statement_timestamp());
  return jsonb_build_object('net_paise', r.net_paise);
end;
$function$;

comment on function public.op_salary_run_finalise(uuid, jsonb) is 'Sync op salary_run.finalise: rebuild a draft salary run and lock it and its period (payroll_finalise).';

grant execute on function "public"."op_salary_run_finalise"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_run_finalise"(uuid, jsonb) from public;

revoke all on function "public"."op_salary_run_finalise"(uuid, jsonb) from anon;

revoke all on function "public"."op_salary_run_finalise"(uuid, jsonb) from authenticated;
