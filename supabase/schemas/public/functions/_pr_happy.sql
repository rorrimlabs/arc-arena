-- _pr_happy(s, d) — the happy-hour window of IST day d under snapshot s, or null.
--
-- Reads s.hours.happy.<ISO weekday 1-7> = {start, end} in minutes after IST midnight and returns
-- the half-open instant range [start, end). Null when d is listed in s.holidays or s.closed_days,
-- or that weekday has no window. Used by _pr_quote.
-- Mirrors BusinessCalendar.happyWindow (apps/mobile/lib/core/time/business_calendar.dart).
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_happy (
  s jsonb,
  d date
)
  returns tstzrange
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
declare
  w jsonb := s->'hours'->'happy'->(extract(isodow from d)::int::text);
  -- IST midnight of d as an instant: d 00:00 UTC minus 5h30 (fixed offset, no DST).
  midnight timestamptz := (d::timestamp at time zone 'UTC') - interval '330 minutes';
begin
  if coalesce(s->'holidays', '[]'::jsonb) ? d::text
     or coalesce(s->'closed_days', '[]'::jsonb) ? d::text then
    return null;
  end if;
  if w is null or jsonb_typeof(w) <> 'object' then return null; end if;
  return tstzrange(midnight + make_interval(mins => (w->>'start')::int),
                   midnight + make_interval(mins => (w->>'end')::int), '[)');
end;
$function$;

comment on function public._pr_happy(jsonb, date) is 'Pricing: happy-hour range of one IST day under a snapshot, null on holidays, closed days or no window; port of BusinessCalendar.happyWindow.';

grant execute on function "public"."_pr_happy"(jsonb, date) to "postgres", "service_role";

revoke all on function "public"."_pr_happy"(jsonb, date) from public;

revoke all on function "public"._pr_happy(s jsonb, d date) from anon;

revoke all on function "public"._pr_happy(s jsonb, d date) from authenticated;
