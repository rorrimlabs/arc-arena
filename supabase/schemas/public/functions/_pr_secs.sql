-- _pr_secs(s, e) — whole seconds from s to e, truncated.
--
-- Epoch difference truncated toward zero (negative when e < s), like Dart Duration.inSeconds.
-- Used by _pr_quote for the total, per-band and played durations.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_secs (
  s timestamp with time zone,
  e timestamp with time zone
)
  returns bigint
  language sql
  immutable
  strict
  set search_path to 'public', 'extensions'
  AS $function$
  select trunc(extract(epoch from e) - extract(epoch from s))::bigint;
$function$;

comment on function public._pr_secs(timestamp with time zone, timestamp with time zone) is 'Pricing: whole seconds between two instants, truncated (Dart Duration.inSeconds).';

grant execute
  on function "public"."_pr_secs"(timestamp with time zone, timestamp with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_pr_secs"(timestamp with time zone, timestamp with time zone)
  from public;

revoke all on function "public"._pr_secs(s timestamp with time zone, e timestamp with time zone) from anon;

revoke all on function "public"._pr_secs(s timestamp with time zone, e timestamp with time zone) from authenticated;
