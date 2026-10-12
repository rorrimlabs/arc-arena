-- _pr_ist_date(t) — the Asia/Kolkata calendar date of an instant.
--
-- Adds a fixed +05:30 (IST has no DST) to the UTC wall time and takes the date.
-- Used by _pr_quote to find the IST days an interval touches for happy-hour splitting.
-- Mirrors IstDate.fromUtc (apps/mobile/lib/core/time/ist.dart).
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_ist_date (
  t timestamp with time zone
)
  returns date
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select ((t at time zone 'UTC') + interval '330 minutes')::date;
$function$;

comment on function public._pr_ist_date(timestamp with time zone) is 'Pricing: IST (fixed +05:30) business date of a UTC instant; port of Dart IstDate.fromUtc.';

grant execute
  on function "public"."_pr_ist_date"(timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_ist_date"(timestamp with time zone) from public;

revoke all on function "public"._pr_ist_date(t timestamp with time zone) from anon;

revoke all on function "public"._pr_ist_date(t timestamp with time zone) from authenticated;
