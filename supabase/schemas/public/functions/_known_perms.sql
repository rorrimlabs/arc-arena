-- _known_perms() — the permission codes a staff profile may hold
--
-- Returns {start, bill, discount, members, stations, money, reports, settings}.
-- Used by _assert_known_perms and by op_staff_update (an owner's profile is
-- kept holding all of them). bootstrap_owner spells the same list out inline.
-- Server-only: not executable by anon/authenticated.
create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings'];
$function$;

comment on function public._known_perms() is 'The eight permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings.';

grant execute on function "public"."_known_perms"() to "postgres", "service_role";

revoke all on function "public"."_known_perms"() from public;

revoke all on function "public"._known_perms() from anon;

revoke all on function "public"._known_perms() from authenticated;
