-- _discount_options(p) — validate and normalise the 'discount_options' setting.
--
-- p must be an object of exactly manual_max_percent (whole 0–100: the most a staff member
-- without the settings permission may take off a bill by hand, as a percent of its subtotal;
-- 0 = no manual discounts for them) and reason_required (boolean: a manual discount must carry
-- a reason). Raises invalid_discount_options (hint: which part). Used by op_settings_save.
-- Server-only: not executable by anon/authenticated.
create or replace function public._discount_options (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('manual_max_percent', 'reason_required')) then
    raise exception 'invalid_discount_options'
      using hint = 'an object of manual_max_percent and reason_required';
  end if;
  if jsonb_typeof(p->'manual_max_percent') is distinct from 'number'
     or (p->>'manual_max_percent')::numeric % 1 <> 0
     or (p->>'manual_max_percent')::numeric not between 0 and 100 then
    raise exception 'invalid_discount_options' using hint = 'manual_max_percent: whole 0–100';
  end if;
  if jsonb_typeof(p->'reason_required') is distinct from 'boolean' then
    raise exception 'invalid_discount_options' using hint = 'reason_required: true or false';
  end if;
  return jsonb_build_object('manual_max_percent', (p->>'manual_max_percent')::int,
    'reason_required', (p->>'reason_required')::boolean);
end;
$function$;

comment on function public._discount_options(jsonb) is 'Validates and normalises the discount_options setting (manual_max_percent 0–100, reason_required).';

grant execute on function "public"."_discount_options"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_discount_options"(jsonb) from public;

revoke all on function "public"._discount_options(p jsonb) from anon;

revoke all on function "public"._discount_options(p jsonb) from authenticated;
