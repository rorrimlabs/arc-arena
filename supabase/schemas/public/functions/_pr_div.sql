-- _pr_div(n, d) — n / d rounded to the nearest integer, ties up.
--
-- (2n + d) / (2d) in integer math: round-half-up for n >= 0, d > 0 (the Dart original asserts
-- both; this does not check, and d = 0 raises division_by_zero). Used by _pr_quote to turn exact
-- numerators (price x seconds) into paise and seconds into billed minutes / units.
-- Mirrors roundDivHalfUp in apps/mobile/lib/core/money/rounding.dart.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_div (
  n bigint,
  d bigint
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select (2 * n + d) / (2 * d);
$function$;

comment on function public._pr_div(bigint, bigint) is 'Pricing: integer division n / d rounded half up; port of Dart roundDivHalfUp.';

grant execute on function "public"."_pr_div"(bigint, bigint) to "postgres", "service_role";

revoke all on function "public"."_pr_div"(bigint, bigint) from public;

revoke all on function "public"._pr_div(n bigint, d bigint) from anon;

revoke all on function "public"._pr_div(n bigint, d bigint) from authenticated;
