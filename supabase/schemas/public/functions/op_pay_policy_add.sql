-- op_pay_policy_add — sync op 'pay_policy.add': the arena's pay rules from a date
--
-- Permission: payroll.
-- Payload: id (client uuid), effective_from, policy (validated by _pay_policy_settings).
-- Checks / errors: forbidden; invalid_pay_policy; rate_in_finalised_period; duplicate.
-- Writes: pay_policies (append-only). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_pay_policy_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_from date := (p->>'effective_from')::date; v_policy jsonb;
begin
  perform _need(p_arena, 'payroll');
  if v_from is null then raise exception 'invalid_pay_policy' using hint = 'effective_from'; end if;
  v_policy := _pay_policy_settings(p->'policy');
  if exists (select 1 from salary_runs where arena_id = p_arena and status = 'finalised'
              and period_end >= v_from) then
    raise exception 'rate_in_finalised_period'
      using hint = 'pay up to ' || (select max(period_end) from salary_runs
                                    where arena_id = p_arena and status = 'finalised') || ' is finalised';
  end if;
  insert into pay_policies(id, arena_id, effective_from, policy, created_by)
    values ((p->>'id')::uuid, p_arena, v_from, v_policy, auth.uid());
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_pay_policy_add(uuid, jsonb) is 'Sync op pay_policy.add: the arena''s pay rules from a date after the last finalised run.';

grant execute on function "public"."op_pay_policy_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_pay_policy_add"(uuid, jsonb) from public;

revoke all on function "public"."op_pay_policy_add"(uuid, jsonb) from anon;

revoke all on function "public"."op_pay_policy_add"(uuid, jsonb) from authenticated;
