-- _leave_rules_settings(p) — validate the arena's leave rules (settings key 'leave_rules')
--
-- Shape (every key required, nothing else): paid_leave_days 0–366 in steps of 0.5 (the paid
-- allowance per leave year, which runs from each person's joining date; no carry-forward),
-- half_day_allowed bool, unplanned_backdate_days 0–31 whole (how far back an unplanned
-- request may start). Returns the object as stored. Raises invalid_leave_rules.
-- Server-only: used by op_settings_save; not executable by anon/authenticated.
create or replace function public._leave_rules_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare v_days numeric; v_back numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('paid_leave_days', 'half_day_allowed', 'unplanned_backdate_days'))
     or not (p ?& array['paid_leave_days', 'half_day_allowed', 'unplanned_backdate_days']) then
    raise exception 'invalid_leave_rules'
      using hint = 'an object of paid_leave_days, half_day_allowed and unplanned_backdate_days';
  end if;
  if jsonb_typeof(p->'paid_leave_days') is distinct from 'number' then
    raise exception 'invalid_leave_rules' using hint = 'paid_leave_days';
  end if;
  v_days := (p->>'paid_leave_days')::numeric;
  if v_days < 0 or v_days > 366 or (v_days * 2) % 1 <> 0 then
    raise exception 'invalid_leave_rules' using hint = 'paid_leave_days: 0–366, in halves';
  end if;
  if jsonb_typeof(p->'half_day_allowed') is distinct from 'boolean' then
    raise exception 'invalid_leave_rules' using hint = 'half_day_allowed';
  end if;
  if jsonb_typeof(p->'unplanned_backdate_days') is distinct from 'number' then
    raise exception 'invalid_leave_rules' using hint = 'unplanned_backdate_days';
  end if;
  v_back := (p->>'unplanned_backdate_days')::numeric;
  if v_back % 1 <> 0 or v_back < 0 or v_back > 31 then
    raise exception 'invalid_leave_rules' using hint = 'unplanned_backdate_days: 0–31';
  end if;
  return jsonb_build_object('paid_leave_days', v_days, 'half_day_allowed', p->'half_day_allowed',
    'unplanned_backdate_days', v_back::int);
end;
$function$;

comment on function public._leave_rules_settings(jsonb) is
  'Validates the leave_rules setting (paid days per leave year, half days allowed, how far back unplanned leave may start); raises invalid_leave_rules.';

grant execute on function "public"."_leave_rules_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_leave_rules_settings"(jsonb) from public;

revoke all on function "public"."_leave_rules_settings"(jsonb) from anon;

revoke all on function "public"."_leave_rules_settings"(jsonb) from authenticated;
