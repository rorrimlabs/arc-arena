-- _pr_ceil_step(v, step) — round v up to the next multiple of step.
--
-- Smallest multiple of step that is >= v, in integer math; step <= 1 returns v unchanged.
-- Used by _pr_money (money_rounding_dir 'up') and _pr_quote (block billing, block_rounding 'up').
-- Mirrors ceilToStep in apps/mobile/lib/core/money/rounding.dart.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_ceil_step (
  v    bigint,
  step integer
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select case when step <= 1 then v else ((v + step - 1) / step) * step end;
$function$;

comment on function public._pr_ceil_step(bigint, integer) is 'Pricing: smallest multiple of step that is >= v (v unchanged when step <= 1); port of Dart ceilToStep.';

grant execute on function "public"."_pr_ceil_step"(bigint, integer) to "postgres", "service_role";

revoke all on function "public"."_pr_ceil_step"(bigint, integer) from public;

revoke all on function "public"._pr_ceil_step(v bigint, step integer) from anon;

revoke all on function "public"._pr_ceil_step(v bigint, step integer) from authenticated;
