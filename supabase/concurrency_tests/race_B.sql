-- Connection B: start 0.3s after A (so A holds the lock), race for the SAME
-- station. B must block on A's lock, then be refused with resource_busy.
select pg_sleep(0.3);
-- Through the client write path (sync_push → session.start), as a device would.
set role authenticated;
select set_config('request.jwt.claims','{"sub":"c0c0c0c0-0000-4000-8000-000000000001","role":"authenticated"}', false);
select r->'results'->0->>'status' as b_status, r->'results'->0->>'error' as b_error
from (select sync_push((select id from arenas limit 1), jsonb_build_array(jsonb_build_object(
  'op_id', gen_random_uuid(), 'kind', 'session.start', 'payload', jsonb_build_object(
  'id','dddddddd-0000-0000-0000-00000000000b',
  'segment_id', gen_random_uuid(),
  'customer_id','cccccccc-0000-0000-0000-00000000c0de',
  'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
  'pricing_snapshot','{}'::jsonb,
  'resource_id',(select id from resources where name='HEX'),'activity_code','PS5'))), 'race') r) q;

