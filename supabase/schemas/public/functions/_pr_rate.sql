-- _pr_rate(s, p_act, p_band, p_cc) — exact rate lookup in a pricing snapshot.
--
-- First element of s->'rates' (snapshot order) whose activity_code, band and controller_count all
-- match (a null controller_count matches only null); null when none. _pr_quote asks for the
-- 'standard' band. Mirrors PricingSnapshot.rateFor (domain/pricing/pricing_snapshot.dart).
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_rate (
  s      jsonb,
  p_act  text,
  p_band text,
  p_cc   integer
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select r from jsonb_array_elements(coalesce(s->'rates', '[]'::jsonb)) with ordinality x(r, n)
   where r->>'activity_code' = p_act and r->>'band' = p_band
     and (r->>'controller_count')::int is not distinct from p_cc
   order by n limit 1;
$function$;

comment on function public._pr_rate(jsonb, text, text, integer) is 'Pricing: first rate in a snapshot matching activity, band and controller count exactly; port of PricingSnapshot.rateFor.';

grant execute
  on function "public"."_pr_rate"(jsonb, text, text, integer)
  to "postgres", "service_role";

revoke all on function "public"."_pr_rate"(jsonb, text, text, integer) from public;

revoke all on function "public"._pr_rate(s jsonb, p_act text, p_band text, p_cc integer) from anon;

revoke all on function "public"._pr_rate(s jsonb, p_act text, p_band text, p_cc integer) from authenticated;
