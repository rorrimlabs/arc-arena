-- Connection A: win the race, then hold the resource lock for 3s before commit.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select start_session((select id from arenas limit 1), jsonb_build_object(
  'id','dddddddd-0000-0000-0000-00000000000a',
  'customer_id','cccccccc-0000-0000-0000-00000000c0de',
  'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
  'pricing_snapshot','{}'::jsonb,
  'resource_id',(select id from resources where name='HEX'),'activity_code','PS5'),'reqA') as a_result;
select pg_sleep(3);
commit;
