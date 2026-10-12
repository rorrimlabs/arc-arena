-- sync_record_delete() — trigger: record a deleted row as a sync tombstone
--
-- AFTER DELETE row trigger (t_<table>_tomb) on the synced tables. Inserts
-- sync_tombstones(arena_id, table_name, row_key) where row_key is the whole
-- old row as jsonb; the tombstone's sync_xid defaults to the deleting
-- transaction, so sync_pull delivers it as a '_tombstone' change.
-- SECURITY DEFINER so the insert works whatever role ran the delete
-- (sync_tombstones is not writable by anon/authenticated).
-- Server-only: not executable by anon/authenticated.
create or replace function public.sync_record_delete()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  insert into sync_tombstones(arena_id, table_name, row_key)
    values (old.arena_id, tg_table_name, to_jsonb(old));
  return old;
end;
$function$;

comment on function public.sync_record_delete() is 'Trigger (after delete on synced tables): write the deleted row to sync_tombstones so sync_pull can propagate the delete to devices.';

grant execute on function "public"."sync_record_delete"() to "postgres", "service_role";

revoke all on function "public"."sync_record_delete"() from public;

revoke all on function "public".sync_record_delete() from anon;

revoke all on function "public".sync_record_delete() from authenticated;
