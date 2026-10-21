-- sync_stamp() — trigger: stamp a row with the writing transaction's id
--
-- BEFORE INSERT OR UPDATE row trigger (t_<table>_sync) on the synced tables.
-- Sets sync_xid = pg_current_xact_id(); that is the row's position in the
-- change feed (sync_pull) and its version for optimistic checks (_stale vs a
-- payload's base_version).
-- Server-only: not executable by anon/authenticated.
create or replace function public.sync_stamp()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
begin
  new.sync_xid := pg_current_xact_id();
  return new;
end;
$function$;

comment on function public.sync_stamp() is 'Trigger (before insert or update on synced tables): set sync_xid to the current transaction id, the row''s change-feed position and version.';

grant execute on function "public"."sync_stamp"() to "postgres", "service_role";

revoke all on function "public"."sync_stamp"() from public;

revoke all on function "public".sync_stamp() from anon;

revoke all on function "public".sync_stamp() from authenticated;
