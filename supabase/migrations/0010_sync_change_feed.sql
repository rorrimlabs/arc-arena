-- arena_ops — commit-safe change feed for multi-device sync.
--
-- A device keeps a cursor and asks "what changed since?". A timestamp cannot
-- answer that safely: segments, assignments and allocations are UPDATED when
-- they close and carry no updated_at, and a transaction that commits late can
-- stamp a time earlier than a cursor another device already moved past.
--
-- So every synced row carries sync_xid = the id of the transaction that last
-- wrote it, and a pull returns rows with cursor <= sync_xid < xmin of the pull's
-- own snapshot. Every transaction with an id below that xmin has finished, so a
-- row from a still-open transaction is never skipped: it simply lands in a later
-- window. Deletes leave a tombstone row so a device learns about them too.
--
-- Additive: one column, one trigger and one index per table; nothing existing
-- is rewritten (existing rows all get the migration's own xid).

create or replace function sync_stamp() returns trigger as $$
begin
  new.sync_xid := pg_current_xact_id();
  return new;
end;
$$ language plpgsql;

-- Deleted rows, so a pull can tell a device to drop them. row_key is the whole
-- old row: the client picks the key it stores the row under.
create table sync_tombstones (
  id         bigserial primary key,
  arena_id   uuid not null,
  table_name text not null,
  row_key    jsonb not null,
  sync_xid   xid8 not null default pg_current_xact_id(),
  deleted_at timestamptz not null default now()
);
create index ix_tombstones_sync on sync_tombstones(arena_id, sync_xid);
alter table sync_tombstones enable row level security;
revoke all on sync_tombstones from anon, authenticated;

create or replace function sync_record_delete() returns trigger as $$
begin
  insert into sync_tombstones(arena_id, table_name, row_key)
    values (old.arena_id, tg_table_name, to_jsonb(old));
  return old;
end;
$$ language plpgsql security definer set search_path = public;

do $$
declare
  t text;
  tables text[] := array[
    'staff_profiles','activities','resources','resource_activities','controllers',
    'customers','rate_cards','rate_bands','rates','billing_policies','holidays',
    'game_categories','games','game_controls','game_resources','bookings',
    'sessions','session_segments','session_extensions','session_charges','payments',
    'group_sessions','group_assignments','group_extensions','group_charges',
    'group_payments','controller_allocations','controller_moves','settings'
  ];
begin
  foreach t in array tables loop
    execute format(
      'alter table %I add column sync_xid xid8 not null default pg_current_xact_id()', t);
    execute format('create index %I on %I (arena_id, sync_xid)', 'ix_' || t || '_sync', t);
    execute format(
      'create trigger %I before insert or update on %I for each row execute function sync_stamp()',
      't_' || t || '_sync', t);
    execute format(
      'create trigger %I after delete on %I for each row execute function sync_record_delete()',
      't_' || t || '_tomb', t);
  end loop;
end $$;

alter table arenas add column sync_xid xid8 not null default pg_current_xact_id();
create index ix_arenas_sync on arenas(sync_xid);
create trigger t_arenas_sync before insert or update on arenas
  for each row execute function sync_stamp();

-- Client-shaped sources. The device keys rates by (activity code, band) and
-- links/bookings by activity code, so the feed carries those codes. Only the
-- active rate card is published (the device has exactly one price list).
create view sync_v_arenas as
  select a.*, a.id as arena_id from arenas a;
create view sync_v_rates as
  select r.*, ac.code as activity_code, b.code as band
    from rates r
    join activities ac on ac.id = r.activity_id
    join rate_bands b on b.id = r.band_id
    join rate_cards c on c.id = r.rate_card_id and c.active;
create view sync_v_resource_activities as
  select ra.*, ac.code as activity_code
    from resource_activities ra join activities ac on ac.id = ra.activity_id;
create view sync_v_bookings as
  select bk.*, ac.code as activity_code
    from bookings bk left join activities ac on ac.id = bk.activity_id;
revoke all on sync_v_arenas, sync_v_rates, sync_v_resource_activities, sync_v_bookings
  from anon, authenticated;

-- (published name, source relation). Order is irrelevant: rows are returned in
-- sync_xid order and the client applies closings before openings.
create or replace function _sync_sources() returns table(name text, rel text) as $$
  values
    ('arenas','sync_v_arenas'), ('staff_profiles','staff_profiles'),
    ('activities','activities'), ('resources','resources'),
    ('resource_activities','sync_v_resource_activities'), ('controllers','controllers'),
    ('customers','customers'), ('rates','sync_v_rates'),
    ('billing_policies','billing_policies'), ('holidays','holidays'),
    ('game_categories','game_categories'), ('games','games'),
    ('game_controls','game_controls'), ('game_resources','game_resources'),
    ('bookings','sync_v_bookings'), ('sessions','sessions'),
    ('session_segments','session_segments'), ('session_extensions','session_extensions'),
    ('session_charges','session_charges'), ('payments','payments'),
    ('group_sessions','group_sessions'), ('group_assignments','group_assignments'),
    ('group_extensions','group_extensions'), ('group_charges','group_charges'),
    ('group_payments','group_payments'), ('controller_allocations','controller_allocations'),
    ('controller_moves','controller_moves'), ('settings','settings')
$$ language sql immutable;

-- sync_pull: every change in the arena since p_cursor ('0' = everything).
--   cursor     next cursor to send back
--   has_more   true when the page was cut at p_limit; call again at once
--   changes    [{t: table, r: row}] in commit-safe order; t = '_tombstone' for a
--              delete, with r = {table, row}
-- One dynamic statement = one snapshot, so the window bound and the rows agree.
create or replace function sync_pull(
  p_arena  uuid,
  p_cursor text default '0',
  p_limit  int  default 2000
) returns jsonb as $$
declare
  v_union text;
  v_out   jsonb;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 then p_limit := 2000; end if;

  select string_agg(format(
      'select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s '
      'where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)',
      name, rel), ' union all ')
    into v_union from _sync_sources();

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
$$ language plpgsql stable security definer set search_path = public;

-- sync_fetch_entity: the server's current rows for whole entities, so a device
-- whose operation was rejected can roll its copy back to server truth.
--   refs: [{type: session|group, id}, {type: controller|customer|booking, id},
--          {type: row, table, id}]
-- Returns [{ref, rows: [{t, r}]}]. An entity the server never had returns no
-- rows — which tells the device to drop its local-only copy.
create or replace function sync_fetch_entity(p_arena uuid, p_refs jsonb)
returns jsonb as $$
declare
  v_ref  jsonb;
  v_id   uuid;
  v_rows jsonb;
  v_out  jsonb := '[]'::jsonb;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  for v_ref in select value from jsonb_array_elements(coalesce(p_refs, '[]'::jsonb)) loop
    v_id := nullif(v_ref->>'id', '')::uuid;
    v_rows := case v_ref->>'type'
      when 'session' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','sessions','r',to_jsonb(s)) x from sessions s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','session_segments','r',to_jsonb(s)) from session_segments s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','session_extensions','r',to_jsonb(s)) from session_extensions s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','session_charges','r',to_jsonb(s)) from session_charges s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','payments','r',to_jsonb(s)) from payments s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.session_ref = 's:' || v_id::text
        ) q)
      when 'group' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','group_sessions','r',to_jsonb(s)) x from group_sessions s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','group_assignments','r',to_jsonb(s)) from group_assignments s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_extensions','r',to_jsonb(s)) from group_extensions s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_charges','r',to_jsonb(s)) from group_charges s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_payments','r',to_jsonb(s)) from group_payments s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.session_ref = 'g:' || v_id::text
        ) q)
      when 'controller' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','controllers','r',to_jsonb(s)) x from controllers s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.controller_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.controller_id = v_id and s.ended_at is null
        ) q)
      when 'customer' then (
        select coalesce(jsonb_agg(jsonb_build_object('t','customers','r',to_jsonb(s))), '[]'::jsonb)
          from customers s where s.arena_id = p_arena and s.id = v_id)
      when 'booking' then (
        select coalesce(jsonb_agg(jsonb_build_object('t','bookings','r',to_jsonb(s))), '[]'::jsonb)
          from sync_v_bookings s where s.arena_id = p_arena and s.id = v_id)
      else '[]'::jsonb
    end;
    v_out := v_out || jsonb_build_array(jsonb_build_object('ref', v_ref, 'rows', v_rows));
  end loop;
  return v_out;
end;
$$ language plpgsql stable security definer set search_path = public;

revoke execute on function _sync_sources() from anon, public, authenticated;
revoke execute on function sync_pull(uuid, text, int), sync_fetch_entity(uuid, jsonb)
  from anon, public;
grant execute on function sync_pull(uuid, text, int), sync_fetch_entity(uuid, jsonb)
  to authenticated;
