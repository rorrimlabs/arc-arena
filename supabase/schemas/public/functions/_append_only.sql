-- _append_only() — trigger: money, audit and evidence rows are never edited or deleted
--
-- BEFORE UPDATE OR DELETE row trigger (t_<table>_append_only) on payments, group_payments,
-- session_charges, group_charges, bill_discounts, audit_log, salary_adjustments,
-- attendance_punches and controller_moves. Corrections are new rows (refunds, reversals,
-- superseding entries), so no op changes these; the trigger makes that hold against a
-- dashboard / SQL-editor delete, a cascade from a deleted session, group or arena, a script or a
-- future op bug. Raises append_only. An operator who must really remove an arena does it as an
-- explicit procedure with `set session_replication_role = replica` (docs/DEPLOY_SUPABASE.md).
-- Server-only: not executable by anon/authenticated.
create or replace function public._append_only()
  returns trigger
  language plpgsql
  set search_path to 'public'
  AS $function$
begin
  raise exception 'append_only' using errcode = '55000',
    hint = tg_table_name || ' rows are never ' || lower(tg_op) || 'd: record a correction instead';
end;
$function$;

comment on function public._append_only() is 'Trigger (before update or delete on money, audit and evidence tables): raise append_only; corrections are new rows.';

grant execute on function "public"."_append_only"() to "postgres", "service_role";

revoke all on function "public"."_append_only"() from public;

revoke all on function "public"."_append_only"() from anon;

revoke all on function "public"."_append_only"() from authenticated;
