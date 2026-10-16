-- sync_v_bookings — bookings shaped for the sync_pull change feed
--
-- Devices refer to activities by business code, so this view adds activity_code
-- (left join: a booking may have no activity). Listed in _sync_sources as the
-- source for the 'bookings' feed and read by sync_fetch_entity. sync_xid is the
-- booking's own, so the row is re-sent when the booking changes, not when the
-- activity does. security_invoker, and no client grants: server-only.
create view "public"."sync_v_bookings"
  with (security_invoker = true)
as
select
  bk.id,
  bk.arena_id,
  bk.customer_id,
  bk.resource_id,
  bk.activity_id,
  bk.game_id,
  bk.scheduled_start,
  bk.scheduled_end,
  bk.status,
  bk.players_required,
  bk.controller_requirement,
  bk.party_name,
  bk.phone,
  bk.notes,
  bk.reminder_status,
  bk.created_at,
  bk.updated_at,
  bk.sync_xid,
  ac.code as activity_code
from public.bookings bk
  left join public.activities ac on ac.id = bk.activity_id;

comment on view public.sync_v_bookings is 'Change-feed source for bookings: every booking column plus the activity''s business code (activity_code, null when no activity). Server-only (read by sync_pull / sync_fetch_entity).';

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_bookings"
  to "postgres", "service_role";

revoke all on table "public".sync_v_bookings from anon;

revoke all on table "public".sync_v_bookings from authenticated;
