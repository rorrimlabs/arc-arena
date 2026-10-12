-- sync_v_resource_activities — resource/activity links shaped for the change feed
--
-- Adds the activity's business code, which devices store instead of the activity
-- uuid. Listed in _sync_sources as the source for the 'resource_activities' feed.
-- sync_xid is the link row's own. security_invoker, and no client grants: read
-- only by the SECURITY DEFINER sync_pull.
create view "public"."sync_v_resource_activities"
  with (security_invoker = true)
as
select
  ra.id,
  ra.arena_id,
  ra.resource_id,
  ra.activity_id,
  ra.created_at,
  ra.updated_at,
  ra.sync_xid,
  ac.code as activity_code
from public.resource_activities ra
  join public.activities ac on ac.id = ra.activity_id;

comment on view public.sync_v_resource_activities is 'Change-feed source for resource_activities: each link plus the activity''s business code. Server-only (read by sync_pull).';

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_resource_activities"
  to "postgres", "service_role";

revoke all on table "public".sync_v_resource_activities from anon;

revoke all on table "public".sync_v_resource_activities from authenticated;
