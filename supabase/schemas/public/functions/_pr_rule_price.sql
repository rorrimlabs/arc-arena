-- _pr_rule_price(p_price, p_unit_minutes, r) — a rate's unit price after pricing rule r.
--
-- percent: round-half-up(p_price × (100 + value) / 100); per_hour: p_price +
-- round-half-up(value × p_unit_minutes / 60), half-up meaning toward +∞ for negative values
-- too. Never below 0. A null rule returns p_price.
-- Used by _pr_quote. Server-only: not executable by anon/authenticated.
create or replace function public._pr_rule_price (
  p_price        bigint,
  p_unit_minutes integer,
  r              jsonb
)
  returns bigint
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select case
    when r is null then p_price
    when r->>'adjust_kind' = 'percent'
      then greatest(0, _pr_div(p_price * (100 + (r->>'adjust_value')::int), 100))
    -- floor((2n + d) / 2d): half-up also for a negative (discount) value, where _pr_div's
    -- integer division would truncate toward zero.
    else greatest(0, p_price + floor((2 * (r->>'adjust_value')::bigint * p_unit_minutes + 60)::numeric
                                     / 120)::bigint)
  end;
$function$;

comment on function public._pr_rule_price(bigint, integer, jsonb) is 'Pricing: a unit price after a pricing rule (percent or paise per hour, never below 0).';

grant execute on function "public"."_pr_rule_price"(bigint, integer, jsonb) to "postgres", "service_role";

revoke all on function "public"."_pr_rule_price"(bigint, integer, jsonb) from public;

revoke all on function "public"._pr_rule_price(p_price bigint, p_unit_minutes integer, r jsonb) from anon;

revoke all on function "public"._pr_rule_price(p_price bigint, p_unit_minutes integer, r jsonb) from authenticated;
