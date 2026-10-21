set local check_function_bodies = off;

drop policy "p_sel_discounts" on "public"."discounts";

alter table "public"."attendance_entries"
  drop constraint "attendance_entries_staff_id_fkey";

alter table "public"."attendance_punches"
  drop constraint "attendance_punches_staff_id_fkey";

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

create or replace function private.sync_push (
  p_arena  uuid,
  p_ops    jsonb,
  p_device text  default null::text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_op jsonb; v_id uuid; v_kind text; v_prev sync_ops; v_res jsonb;
  v_out jsonb := '[]'::jsonb;
  v_state text; v_msg text; v_hint text; v_code text;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  if jsonb_typeof(p_ops) = 'array' and jsonb_array_length(p_ops) > 200 then
    raise exception 'batch_too_large' using errcode = '54000', hint = 'at most 200 ops per push';
  end if;
  for v_op in select value from jsonb_array_elements(coalesce(p_ops, '[]'::jsonb)) loop
    v_kind := v_op->>'kind';
    if coalesce(v_op->>'op_id', '')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_op->'op_id',
        'status', 'rejected', 'error', 'invalid_op_id', 'replayed', false));
      continue;
    end if;
    v_id := (v_op->>'op_id')::uuid;
    -- Two pushes of the same op (a retry racing the original) queue here.
    perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));
    select * into v_prev from sync_ops where op_id = v_id;
    if found then
      if v_prev.arena_id <> p_arena or v_prev.kind <> coalesce(v_kind, '?') then
        v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
          'status', 'rejected', 'error', 'op_id_reused', 'replayed', false));
        continue;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', v_prev.status, 'result', v_prev.result, 'error', v_prev.error_code,
        'detail', v_prev.error_message, 'replayed', true));
      continue;
    end if;
    begin
      v_res := _sync_apply(p_arena, v_kind, coalesce(v_op->'payload', '{}'::jsonb));
      if v_res is null then raise exception 'unknown_op' using hint = coalesce(v_kind, 'null'); end if;
      -- Configuration, permission and pay ops keep what they asked for (audit).
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, result, payload)
        values (v_id, p_arena, auth.uid(), p_device, v_kind, 'applied', v_res,
          case when split_part(v_kind, '.', 1) in ('staff', 'arena', 'activity', 'resource', 'rate',
                 'policy', 'settings', 'holiday', 'rule', 'discount', 'shift', 'staff_holiday',
                 'hr_profile', 'pay_rate', 'pay_policy', 'salary_run', 'salary_adjustment')
                 or v_kind = 'leave.adjust'
               then v_op->'payload' end);
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'applied', 'result', v_res, 'replayed', false));
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text,
        v_hint = pg_exception_hint;
      -- Transient (serialization failure, deadlock, lock not available, query
      -- cancelled, connection, out of resources, internal): not recorded, so the
      -- device resends this op and the rest later.
      if left(v_state, 2) in ('40', '08', '53', 'XX') or v_state in ('55P03', '57014') then
        v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
          'status', 'retry', 'error', v_state));
        exit;
      end if;
      -- Stable error code for the device: a plain `raise exception '<code>'`
      -- (P0001) passes its message through; known SQLSTATEs are mapped.
      v_code := case
        when v_state = '42501' then 'forbidden'
        when v_state = '23505' then 'duplicate'
        when v_state = '23503' then 'missing_reference'
        when v_state in ('23514', '23502') then 'invalid'
        when v_state like '22%' then 'invalid_payload'
        when v_state = 'P0001' then v_msg
        else 'server_error' end;
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, error_code, error_message)
        values (v_id, p_arena, auth.uid(), p_device, coalesce(v_kind, '?'), 'rejected', v_code,
          coalesce(v_hint, v_msg));
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'rejected', 'error', v_code, 'detail', coalesce(v_hint, v_msg), 'replayed', false));
    end;
  end loop;
  return jsonb_build_object('results', v_out, 'server_time', clock_timestamp());
end;
$function$;

create or replace function public.op_shift_assign (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_shift uuid := (p->>'shift_id')::uuid;
  v_from  date := (p->>'effective_from')::date;
  v_to    date := (p->>'effective_to')::date;
  v_old   staff_shifts;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if v_from is null then raise exception 'invalid_payload' using hint = 'effective_from'; end if;
  if v_to is not null and v_to < v_from then
    raise exception 'invalid_payload' using hint = 'effective_to is before effective_from';
  end if;
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if not exists (select 1 from shifts where id = v_shift and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'shift';
  end if;
  select * into v_old from staff_shifts where id = v_id and arena_id = p_arena for update;
  -- A schedule decides absences and late marks (pay): nobody changes their own.
  perform _own_record(p_arena, v_staff);
  if v_old.id is not null then perform _own_record(p_arena, v_old.staff_id); end if;
  if v_old.id is null and not exists (select 1 from shifts where id = v_shift and active) then
    raise exception 'shift_inactive' using hint = 'turn the shift back on before assigning it';
  end if;
  -- Paid days never change: a new assignment, or the days an edit moves, may not touch a
  -- finalised period (a change of person or shift moves all of its days).
  if v_old.id is null then
    if _period_finalised(p_arena, v_from, coalesce(v_to, 'infinity'::date)) then
      raise exception 'period_finalised' using hint = 'pay for some of those days is finalised';
    end if;
  elsif ((v_old.staff_id is distinct from v_staff or v_old.shift_id is distinct from v_shift)
         and _period_finalised(p_arena, least(v_old.effective_from, v_from),
               greatest(coalesce(v_old.effective_to, 'infinity'::date), coalesce(v_to, 'infinity'::date))))
     or (v_old.effective_from is distinct from v_from
         and _period_finalised(p_arena, least(v_old.effective_from, v_from),
               greatest(v_old.effective_from, v_from)))
     or (v_old.effective_to is distinct from v_to
         and _period_finalised(p_arena,
               least(coalesce(v_old.effective_to, 'infinity'::date), coalesce(v_to, 'infinity'::date)),
               greatest(coalesce(v_old.effective_to, 'infinity'::date), coalesce(v_to, 'infinity'::date)))) then
    raise exception 'period_finalised' using hint = 'pay for some of those days is finalised';
  end if;
  begin
    insert into staff_shifts(id, arena_id, staff_id, shift_id, effective_from, effective_to)
      values (v_id, p_arena, v_staff, v_shift, v_from, v_to)
    on conflict (id) do update set staff_id = excluded.staff_id, shift_id = excluded.shift_id,
        effective_from = excluded.effective_from, effective_to = excluded.effective_to
      where staff_shifts.arena_id = p_arena;
  exception when exclusion_violation then
    raise exception 'assignment_overlap' using hint = 'this person already has this shift on some of those days';
  end;
  if not found then raise exception 'not_found' using hint = 'assignment'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_shift_unassign (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_today date := _pr_ist_date(statement_timestamp());
begin
  perform _need(p_arena, 'settings');
  -- A schedule decides absences and late marks (pay): nobody changes their own.
  perform _own_record(p_arena, (select staff_id from staff_shifts
                                 where id = (p->>'id')::uuid and arena_id = p_arena));
  -- Ending keeps the days already worked under it (they stay scheduled shift days); only an
  -- assignment that has not started yet is deleted.
  update staff_shifts set effective_to = v_today - 1, updated_at = statement_timestamp()
   where id = (p->>'id')::uuid and arena_id = p_arena and effective_from < v_today
     and (effective_to is null or effective_to >= v_today);
  delete from staff_shifts where id = (p->>'id')::uuid and arena_id = p_arena
     and effective_from >= v_today;
  return '{}'::jsonb;
end;
$function$;

alter table "public"."attendance_entries"
  add constraint "attendance_entries_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."attendance_punches"
  add constraint "attendance_punches_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

create policy "p_sel_discounts" on "public"."discounts"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['discount'::text, 'settings'::text,
    'money'::text, 'reports'::text]) as app_arena_ids_with)));
