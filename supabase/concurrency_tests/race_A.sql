-- Connection A: win the race, then hold the station lock for 3s before commit.
begin;
-- The arena's own price list, as an in-sync device freezes it (0013 refuses others).
select _pricing_snapshot('e0000000-0000-4000-8000-0000000000c1'::uuid) as snap \gset
-- Through the client write path (sync_push → session.start), as a device would.
set role authenticated;
select set_config('request.jwt.claims','{"sub":"c0c0c0c0-0000-4000-8000-000000000001","role":"authenticated"}', false);
select r->'results'->0->>'status' as a_status, r->'results'->0->>'error' as a_error
from (select sync_push('e0000000-0000-4000-8000-0000000000c1'::uuid, jsonb_build_array(jsonb_build_object(
  'op_id', gen_random_uuid(), 'kind', 'session.start', 'payload', jsonb_build_object(
  'id','dddddddd-0000-0000-0000-00000000000a',
  'segment_id', gen_random_uuid(),
  'customer_id','cccccccc-0000-0000-0000-00000000c0de',
  'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
  'pricing_snapshot',:'snap'::jsonb,
  'resource_id',(select id from resources where name='HEX' and arena_id='e0000000-0000-4000-8000-0000000000c1'),'activity_code','PS5'))), 'race') r) q;
select pg_sleep(3);
commit;
