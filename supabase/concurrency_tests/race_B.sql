-- Connection B: start 0.3s after A (so A holds the lock), race for the SAME
-- station. B must block on A's resources FOR UPDATE lock, then fail resource_busy.
select pg_sleep(0.3);
set role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
select start_session((select id from arenas limit 1), jsonb_build_object(
  'id','dddddddd-0000-0000-0000-00000000000b',
  'customer_id','cccccccc-0000-0000-0000-00000000c0de',
  'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
  'pricing_snapshot','{}'::jsonb,
  'resource_id',(select id from resources where name='HEX'),'activity_code','PS5'),'reqB') as b_result;
