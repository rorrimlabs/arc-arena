-- _stale(current_xid, base_version) — optimistic-concurrency check for edit ops
--
-- True when the device sent a non-empty base_version (the row's sync_xid as it
-- last saw it) and it differs from the row's current sync_xid, i.e. another
-- device wrote the row since. A null/empty base_version is never stale (the
-- edit applies unconditionally). Used by op_customer_update and
-- op_booking_update, which then raise 'stale'.
-- Server-only: not executable by anon/authenticated.
create or replace function public._stale (
  p_current xid8,
  p_base    text
)
  returns boolean
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select p_base is not null and p_base <> '' and p_current::text <> p_base;
$function$;

comment on function public._stale(xid8, text) is 'Internal: true when a non-empty client base_version differs from the row''s current sync_xid (the row changed since the device last saw it).';

grant execute on function "public"."_stale"(xid8, text) to "postgres", "service_role";

revoke all on function "public"."_stale"(xid8, text) from public;

revoke all on function "public"._stale(p_current xid8, p_base text) from anon;

revoke all on function "public"._stale(p_current xid8, p_base text) from authenticated;
