-- _pr_round_step(v, step) — round v to the nearest multiple of step, ties up.
--
-- ((v + step/2) / step) * step in integer math; step <= 1 returns v unchanged.
-- Used by _pr_money (money_rounding_dir 'nearest') and _pr_quote (block_rounding 'nearest').
-- Mirrors roundToStep in apps/mobile/lib/core/money/rounding.dart.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_round_step (
  v    bigint,
  step integer
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select case when step <= 1 then v else ((v + step / 2) / step) * step end;
$function$;

comment on function public._pr_round_step(bigint, integer) is 'Pricing: nearest multiple of step to v, ties up (v unchanged when step <= 1); port of Dart roundToStep.';

grant execute on function "public"."_pr_round_step"(bigint, integer) to "postgres", "service_role";

revoke all on function "public"."_pr_round_step"(bigint, integer) from public;

revoke all on function "public"._pr_round_step(v bigint, step integer) from anon;

revoke all on function "public"._pr_round_step(v bigint, step integer) from authenticated;
