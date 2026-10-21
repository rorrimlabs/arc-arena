-- sync_pull(arena, cursor, limit) — one page of the arena's change feed
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Clients reach it only through the
-- SECURITY INVOKER wrapper public.sync_pull.
--
-- Returns {cursor, has_more, server_time, scope, changes: [{t, r}]}: rows of every
-- _sync_sources() relation the caller may read (customers, money and coupons
-- by permission, as RLS: _sync_hidden; scope = the hidden names, and a device
-- whose scope changes re-reads from '0') plus sync_tombstones (t = '_tombstone',
-- r = {table, row}) with cursor <= sync_xid < xmin of the current snapshot,
-- ordered by sync_xid. Pass the returned cursor back ('0' to start); repeat
-- while has_more. p_limit (null/<1 -> 2000) is a soft page size; each source
-- reads at most p_limit + 1 rows per page, so a page never scans the whole
-- remaining feed. SECURITY
-- DEFINER; any active member of p_arena may call it, else 'forbidden' (42501).
-- Client API: callable by signed-in users (authenticated).
create or replace function private.sync_pull (
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
  v_lim    text;
  v_exact  text;
  v_out    jsonb;
  v_hidden text[];
  v_hi     xid8;
  v_bound  xid8;
  v_first  xid8;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 then p_limit := 2000; end if;
  -- One page is bounded whatever the caller asks for.
  p_limit := least(p_limit, 5000);
  -- Customers, money and coupons only for those who may read them (as RLS does).
  v_hidden := _sync_hidden(p_arena);
  -- Upper bound is the snapshot's xmin, taken once: every transaction below it
  -- has finished, so a row from a transaction still open now is never skipped
  -- by a later cursor, and the statements below all see the same window.
  v_hi := pg_snapshot_xmin(pg_current_snapshot());

  -- Each source reads at most p_limit + 1 rows past the cursor (index on
  -- arena_id, sync_xid), so a page costs O(sources × limit), not the whole
  -- remaining feed. A source that filled its share may hold more rows at its
  -- last sync_xid: rows below the smallest such xid are complete.
  select string_agg(format(
      '(select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s '
      'where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < $4 '
      'order by s.sync_xid limit $3 + 1)', name, rel), ' union all ')
    into v_lim from _sync_sources() where name <> all(v_hidden);
  v_lim := v_lim || ' union all (select ''_tombstone'', s.sync_xid, '
    'jsonb_build_object(''table'', s.table_name, ''row'', s.row_key) from sync_tombstones s '
    'where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < $4 and s.table_name <> all($5) '
    'order by s.sync_xid limit $3 + 1)';

  execute 'with ch as (' || v_lim || '), cnt as (select t, count(*) as c, max(x) as mx from ch group by t) '
    'select (select min(mx) from cnt where c > $3), (select min(x) from ch)'
    into v_bound, v_first
    using p_arena, p_cursor::xid8, p_limit, v_hi, v_hidden;

  if v_first is null then
    -- Nothing past the cursor: the window is complete.
    return jsonb_build_object('cursor', v_hi::text, 'has_more', false,
      'server_time', clock_timestamp(), 'scope', to_jsonb(v_hidden), 'changes', '[]'::jsonb);
  end if;

  if v_bound is not null and v_bound <= v_first then
    -- The first transaction alone fills a source's share: send it whole (a
    -- transaction's changes never span two pages), however large.
    select string_agg(format(
        'select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s '
        'where s.arena_id = $1 and s.sync_xid = $2', name, rel), ' union all ')
      into v_exact from _sync_sources() where name <> all(v_hidden);
    v_exact := v_exact || ' union all select ''_tombstone'', s.sync_xid, '
      'jsonb_build_object(''table'', s.table_name, ''row'', s.row_key) from sync_tombstones s '
      'where s.arena_id = $1 and s.sync_xid = $2 and s.table_name <> all($3)';
    execute 'select coalesce(jsonb_agg(jsonb_build_object(''t'', t, ''r'', r)), ''[]''::jsonb) '
      'from (' || v_exact || ') q'
      into v_out using p_arena, v_first, v_hidden;
    v_bound := (v_first::text::numeric + 1)::text::xid8;
    return jsonb_build_object('cursor', v_bound::text, 'has_more', v_bound < v_hi,
      'server_time', clock_timestamp(), 'scope', to_jsonb(v_hidden), 'changes', v_out);
  end if;

  -- Complete rows only (below the bound), cut on a sync_xid boundary at about
  -- p_limit rows; the first transaction is always included.
  v_bound := coalesce(v_bound, v_hi);
  execute
    'with ch as (select * from (' || v_lim || ') l where x < $6), '
    'g as (select x, count(*) as c from ch group by x), '
    'cum as (select x, c, sum(c) over (order by x) as run from g), '
    'cut as (select coalesce((select min(x) from cum where run - c > 0 and run > $3), $6) as upper) '
    'select jsonb_build_object('
    '  ''cursor'', (select upper from cut)::text, '
    '  ''has_more'', (select upper from cut) < $4, '
    '  ''server_time'', clock_timestamp(), '
    '  ''scope'', to_jsonb($5), '
    '  ''changes'', coalesce((select jsonb_agg(jsonb_build_object(''t'', t, ''r'', r) order by x) '
    '                         from ch where x < (select upper from cut)), ''[]''::jsonb))'
    into v_out
    using p_arena, p_cursor::xid8, p_limit, v_hi, v_hidden, v_bound;
  return v_out;
end;
$function$;

comment on function private.sync_pull(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

grant execute
  on function "private"."sync_pull"(uuid, text, integer)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."sync_pull"(uuid, text, integer) from public;

revoke all on function "private".sync_pull(p_arena uuid, p_cursor text, p_limit integer) from anon;
