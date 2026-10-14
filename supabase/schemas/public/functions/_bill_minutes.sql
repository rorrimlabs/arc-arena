-- _bill_minutes(b) — whole minutes a closed bill ran: from its start to its end (or close).
--
-- b is a _sales object; same as the dashboard's playedMinutes(bill). Used by arena_overview.
-- Server-only: not executable by anon/authenticated.
create or replace function public._bill_minutes (
  b jsonb
)
  returns bigint
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select greatest(0, round(extract(epoch from (
    coalesce(b->>'ended_at', b->>'at')::timestamptz - (b->>'started_at')::timestamptz)) / 60))::bigint;
$function$;

comment on function public._bill_minutes(jsonb) is 'Internal (dashboard reads): whole minutes from a _sales bill''s start to its end or close.';

grant execute on function "public"."_bill_minutes"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_bill_minutes"(jsonb) from public;

revoke all on function "public"._bill_minutes(b jsonb) from anon;

revoke all on function "public"._bill_minutes(b jsonb) from authenticated;
