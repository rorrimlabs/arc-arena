-- _rupees(paise) — format integer paise as rupees for error hints
--
-- e.g. 30000 -> '₹300.00'. Display only (money stays integer paise
-- everywhere else); used in op_payment's overpayment / over-refund hints.
-- Server-only: not executable by anon/authenticated.
create or replace function public._rupees (
  p bigint
)
  returns text
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select '₹' || to_char(p / 100.0, 'FM999999990.00');
$function$;

comment on function public._rupees(bigint) is 'Internal: format an amount in integer paise as a rupee string (e.g. 30000 -> ₹300.00) for user-facing error hints.';

grant execute on function "public"."_rupees"(bigint) to "postgres", "service_role";

revoke all on function "public"."_rupees"(bigint) from public;

revoke all on function "public"._rupees(p bigint) from anon;

revoke all on function "public"._rupees(p bigint) from authenticated;
