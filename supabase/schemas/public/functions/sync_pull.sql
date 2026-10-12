-- sync_pull(arena, cursor, limit) — one page of the arena's change feed
--
-- Returns {cursor, has_more, server_time, changes: [{t, r}]}: rows of every
-- _sync_sources() relation plus sync_tombstones (t = '_tombstone',
-- r = {table, row}) with cursor <= sync_xid < xmin of the current snapshot,
-- ordered by sync_xid. Pass the returned cursor back ('0' to start); repeat
-- while has_more. p_limit (null/<1 -> 2000) is a soft page size. SECURITY
-- DEFINER; any active member of p_arena may call it, else 'forbidden' (42501).
-- Client API: callable by signed-in users (authenticated).
create or replace function public.sync_pull (
  p_arena  uuid,
  p_cursor text    default '0'::text,
  p_limit  integer default 2000
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_union text;
  v_out   jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 then p_limit := 2000; end if;

  select string_agg(format(
      'select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s '
      'where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)',
      name, rel), ' union all ')
    into v_union from _sync_sources();

  -- Upper bound is the snapshot's xmin, so a row from a transaction still open
  -- now is never skipped by a later cursor. Pages are cut on a sync_xid
  -- boundary: a transaction's changes never span two pages, and the first
  -- transaction is always included even if it alone exceeds p_limit.
  execute
    'with snap as (select pg_snapshot_xmin(pg_current_snapshot()) as hi), '
    'ch as (' || v_union ||
    ' union all select ''_tombstone'', s.sync_xid, '
    '  jsonb_build_object(''table'', s.table_name, ''row'', s.row_key) '
    '  from sync_tombstones s '
    '  where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)), '
    'g as (select x, count(*) as c from ch group by x), '
    'cum as (select x, c, sum(c) over (order by x) as run from g), '
    'cut as (select coalesce((select min(x) from cum where run - c > 0 and run > $3), '
    '                        (select hi from snap)) as upper) '
    'select jsonb_build_object('
    '  ''cursor'', (select upper from cut)::text, '
    '  ''has_more'', (select upper from cut) < (select hi from snap), '
    '  ''server_time'', clock_timestamp(), '
    '  ''changes'', coalesce((select jsonb_agg(jsonb_build_object(''t'', t, ''r'', r) order by x) '
    '                         from ch where x < (select upper from cut)), ''[]''::jsonb))'
    into v_out
    using p_arena, p_cursor::xid8, p_limit;
  return v_out;
end;
$function$;

comment on function public.sync_pull(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

grant execute
  on function "public"."sync_pull"(uuid, text, integer)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."sync_pull"(uuid, text, integer) from public;

revoke all on function "public".sync_pull(p_arena uuid, p_cursor text, p_limit integer) from anon;
