-- sync_v_arenas — arenas shaped for the sync_pull change feed
--
-- sync_pull filters every source by arena_id and sync_xid; arenas has no arena_id
-- column, so this view adds arena_id = id. Listed in _sync_sources as the source
-- for the 'arenas' feed. security_invoker, and no client grants: read only by
-- the SECURITY DEFINER sync_pull.
create view "public"."sync_v_arenas"
  with (security_invoker = true)
as
select
  a.id,
  a.name,
  a.timezone,
  a.created_at,
  a.updated_at,
  a.sync_xid,
  a.id as arena_id
from public.arenas a;

comment on view public.sync_v_arenas is 'Change-feed source for arenas: the arena row plus arena_id = id so sync_pull can filter it like every other table. Server-only (read by sync_pull).';

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_arenas"
  to "postgres", "service_role";

revoke all on table "public".sync_v_arenas from anon;

revoke all on table "public".sync_v_arenas from authenticated;
