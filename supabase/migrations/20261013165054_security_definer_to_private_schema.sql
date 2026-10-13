set local check_function_bodies = off;

drop policy "p_sel_activities" on "public"."activities";

drop policy "p_sel_arenas" on "public"."arenas";

drop policy "p_sel_audit_log" on "public"."audit_log";

drop policy "p_sel_billing_policies" on "public"."billing_policies";

drop policy "p_sel_bookings" on "public"."bookings";

drop policy "p_sel_controller_allocations" on "public"."controller_allocations";

drop policy "p_sel_controller_moves" on "public"."controller_moves";

drop policy "p_sel_controllers" on "public"."controllers";

drop policy "p_sel_customers" on "public"."customers";

drop policy "p_sel_game_categories" on "public"."game_categories";

drop policy "p_sel_game_controls" on "public"."game_controls";

drop policy "p_sel_game_resources" on "public"."game_resources";

drop policy "p_sel_games" on "public"."games";

drop policy "p_sel_group_assignments" on "public"."group_assignments";

drop policy "p_sel_group_charges" on "public"."group_charges";

drop policy "p_sel_group_extensions" on "public"."group_extensions";

drop policy "p_sel_group_payments" on "public"."group_payments";

drop policy "p_sel_group_sessions" on "public"."group_sessions";

drop policy "p_sel_holidays" on "public"."holidays";

drop policy "p_sel_payments" on "public"."payments";

drop policy "p_sel_rate_bands" on "public"."rate_bands";

drop policy "p_sel_rate_cards" on "public"."rate_cards";

drop policy "p_sel_rates" on "public"."rates";

drop policy "p_sel_resource_activities" on "public"."resource_activities";

drop policy "p_sel_resources" on "public"."resources";

drop policy "p_sel_session_charges" on "public"."session_charges";

drop policy "p_sel_session_extensions" on "public"."session_extensions";

drop policy "p_sel_session_segments" on "public"."session_segments";

drop policy "p_sel_sessions" on "public"."sessions";

drop policy "p_sel_settings" on "public"."settings";

drop policy "p_sel_staff" on "public"."staff_profiles";

drop function "public"."add_member_by_email"(uuid, text, text, text, text[]);

drop function "public"."app_arena_ids"();

drop function "public"."app_has_perm"(uuid, text);

drop function "public"."arena_pricing"(uuid);

drop function "public"."arena_sale"(uuid, uuid);

drop function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone);

drop function "public"."arena_staff"(uuid);

drop function "public"."create_my_arena"(text, text);

drop function "public"."sync_fetch_entity"(uuid, jsonb);

drop function "public"."sync_pull"(uuid, text, integer);

drop function "public"."sync_push"(uuid, jsonb, text);

create schema "private";

create or replace function private.add_member_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_user uuid; v_perms text[];
begin
  if p_role is null or p_role not in ('staff', 'owner') then
    raise exception 'invalid_role' using hint = 'role must be staff or owner';
  end if;
  if p_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add an owner';
    end if;
    v_perms := _known_perms();
  else
    if not private.app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
    end if;
    perform _assert_known_perms(p_perms);
    v_perms := coalesce(p_perms, '{}');
  end if;
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create their login first (admin dashboard → Users → Add)';
  end if;
  -- Nobody changes their own access (same rule as op_staff_update).
  if v_user = auth.uid() then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'you cannot change your own permissions';
  end if;
  if exists (select 1 from staff_profiles
              where arena_id = p_arena and user_id = v_user and role = 'owner') then
    raise exception 'owner_profile'
      using hint = 'that login is already an owner of this arena';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user,
      coalesce(nullif(btrim(p_name), ''), case p_role when 'owner' then 'Owner' else 'Staff' end),
      p_role, v_perms, true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, role = excluded.role, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  -- Re-adding someone with fewer permissions must not strand Settings.
  perform _assert_settings_holder(p_arena);
  return v_user;
end;
$function$;

create or replace function private.add_staff_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_perms text[]
)
  returns uuid
  language sql
  security definer
  set search_path to 'public'
  AS $function$
  select private.add_member_by_email(p_arena, p_email, p_name, 'staff', p_perms);
$function$;

create or replace function private.app_arena_ids()
  returns SETOF uuid
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  -- `and active` matches the client's PermissionGuard active gate and the
  -- role-aware helpers: a deactivated staff member loses all access server-side.
  select arena_id from staff_profiles where user_id = auth.uid() and active;
$function$;

create or replace function private.app_has_perm (
  p_arena uuid,
  p_perm  text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or p_perm = any(perms))
  );
$function$;

create or replace function private.app_is_owner (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or perms && array['money','reports'])
  );
$function$;

create or replace function private.arena_pricing (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read pricing';
  end if;
  return jsonb_build_object(
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', a.id, 'code', a.code, 'name', a.name,
          'uses_controllers', a.uses_controllers, 'uses_games', a.uses_games,
          'duration_model', a.duration_model, 'happy_hour_eligible', a.happy_hour_eligible,
          'sort_order', a.sort_order, 'active', a.active,
          'stations', (select count(*) from resource_activities ra
                         join resources r on r.id = ra.resource_id
                        where ra.activity_id = a.id and r.status <> 'disabled'))
        order by a.sort_order, lower(a.name))
        from activities a where a.arena_id = p_arena), '[]'::jsonb),
    'rates', coalesce((
      select jsonb_agg(jsonb_build_object('activity_code', v.activity_code, 'band', v.band,
          'controller_count', v.controller_count, 'unit_minutes', v.unit_minutes,
          'price_paise', v.price_paise)
        order by v.activity_code, v.band, v.controller_count nulls first)
        from sync_v_rates v where v.arena_id = p_arena), '[]'::jsonb),
    'hours', _pricing_snapshot(p_arena)->'hours');
end;
$function$;

create or replace function private.arena_sale (
  p_arena uuid,
  p_id    uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_bill jsonb;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read sales';
  end if;
  select b into v_bill from _sales(p_arena, null, null, p_id) b;
  if v_bill is null then raise exception 'not_found' using hint = 'bill'; end if;

  if v_bill->>'kind' = 'single' then
    v_bill := v_bill || jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player', null, 'station', r.name, 'activity', coalesce(a.name, ch.activity_code),
            'band', ch.band_code, 'controllers', ch.controller_count,
            'start', ch.segment_start, 'end', ch.segment_end,
            'played_minutes', ch.played_minutes, 'billed_minutes', ch.billed_minutes,
            'unit_minutes', ch.unit_minutes, 'unit_price_paise', ch.unit_price_paise,
            'amount_paise', ch.amount_paise)
          order by ch.segment_start, ch.segment_index)
          from session_charges ch
          left join resources r on r.id = ch.resource_id
          left join activities a on a.arena_id = ch.arena_id and a.code = ch.activity_code
         where ch.session_id = p_id), '[]'::jsonb),
      'extensions', coalesce((
        select jsonb_agg(jsonb_build_object('at', e.created_at, 'added_minutes', e.added_minutes,
            'added_amount_paise', e.added_amount_paise, 'reason', e.reason, 'by', sp.name)
          order by e.created_at)
          from session_extensions e
          left join staff_profiles sp on sp.arena_id = e.arena_id and sp.user_id = e.created_by
         where e.session_id = p_id), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(jsonb_build_object('id', p.id, 'at', p.created_at,
            'amount_paise', p.amount_paise, 'method', p.method, 'refund', p.kind = 'refund',
            'reason', p.reason, 'note', p.note, 'by', sp.name)
          order by p.created_at, p.id)
          from payments p
          left join staff_profiles sp on sp.arena_id = p.arena_id and sp.user_id = p.created_by
         where p.session_id = p_id), '[]'::jsonb));
  else
    v_bill := v_bill || jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player', ch.player_number, 'station', r.name, 'activity', coalesce(a.name, ch.activity_code),
            'band', ch.band_code, 'controllers', ch.controller_count,
            'start', ch.segment_start, 'end', ch.segment_end,
            'played_minutes', ch.played_minutes, 'billed_minutes', ch.billed_minutes,
            'unit_minutes', ch.unit_minutes, 'unit_price_paise', ch.unit_price_paise,
            'amount_paise', ch.amount_paise)
          order by ch.segment_start, ch.player_number, ch.charge_index)
          from group_charges ch
          left join resources r on r.id = ch.resource_id
          left join activities a on a.arena_id = ch.arena_id and a.code = ch.activity_code
         where ch.group_id = p_id), '[]'::jsonb),
      'extensions', coalesce((
        select jsonb_agg(jsonb_build_object('at', e.created_at, 'added_minutes', e.added_minutes,
            'added_amount_paise', e.added_amount_paise, 'reason', e.reason, 'by', sp.name)
          order by e.created_at)
          from group_extensions e
          left join staff_profiles sp on sp.arena_id = e.arena_id and sp.user_id = e.created_by
         where e.group_id = p_id), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(jsonb_build_object('id', p.id, 'at', p.created_at,
            'amount_paise', p.amount_paise, 'method', p.method, 'refund', p.is_refund,
            'reason', p.reason, 'note', p.note, 'by', sp.name)
          order by p.created_at, p.id)
          from group_payments p
          left join staff_profiles sp on sp.arena_id = p.arena_id and sp.user_id = p.created_by
         where p.group_id = p_id), '[]'::jsonb));
  end if;

  return v_bill || jsonb_build_object('voided', (
    select jsonb_build_object('at', l.created_at, 'by', sp.name, 'reason', l.reason)
      from audit_log l
      left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
     where l.arena_id = p_arena and l.entity_id = p_id and l.action = 'void'
     order by l.created_at limit 1));
end;
$function$;

create or replace function private.arena_sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list sales';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '93 days' then
    raise exception 'invalid_range' using hint = 'from < to, at most 93 days';
  end if;
  return coalesce((
    select jsonb_agg(b order by (b->>'at')::timestamptz desc, b->>'id')
      from _sales(p_arena, p_from, p_to) b), '[]'::jsonb);
end;
$function$;

create or replace function private.arena_staff (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_since timestamptz := statement_timestamp() - interval '30 days';
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list staff';
  end if;
  return coalesce((
    with money as (
      select created_by, 's:' || session_id::text as bill, amount_paise
        from payments where arena_id = p_arena and created_at >= v_since
      union all
      select created_by, 'g:' || group_id::text, amount_paise
        from group_payments where arena_id = p_arena and created_at >= v_since
    ), per as (
      select created_by,
             count(distinct bill) filter (where amount_paise > 0) as bills,
             coalesce(sum(amount_paise), 0) as net,
             coalesce(-sum(amount_paise) filter (where amount_paise < 0), 0) as refunds
        from money group by created_by
    )
    select jsonb_agg(jsonb_build_object(
        'user_id', s.user_id, 'name', s.name, 'email', u.email, 'role', s.role,
        'perms', to_jsonb(s.perms), 'active', s.active,
        'invited', u.last_sign_in_at is null,
        'bills_30d', coalesce(p.bills, 0), 'takings_30d_paise', coalesce(p.net, 0),
        'refunds_30d_paise', coalesce(p.refunds, 0))
      order by s.role = 'owner' desc, lower(s.name))
      from staff_profiles s
      join auth.users u on u.id = s.user_id
      left join per p on p.created_by = s.user_id
     where s.arena_id = p_arena), '[]'::jsonb);
end;
$function$;

create or replace function private.create_my_arena (
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_user      uuid := auth.uid();
  v_confirmed timestamptz;
  v_arena     text := btrim(coalesce(p_arena_name, ''));
  v_owner     text := btrim(coalesce(p_owner_name, ''));
begin
  if v_user is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  select email_confirmed_at into v_confirmed from auth.users where id = v_user;
  if not found then
    raise exception 'no_account' using hint = 'sign up again';
  end if;
  if v_confirmed is null then
    raise exception 'account_not_confirmed'
      using hint = 'enter the code we e-mailed you to confirm the address';
  end if;
  if v_arena = '' or length(v_arena) > 80 then
    raise exception 'invalid_name' using hint = 'the arena name must be 1 to 80 characters';
  end if;
  if v_owner = '' or length(v_owner) > 80 then
    raise exception 'invalid_name' using hint = 'your name must be 1 to 80 characters';
  end if;
  -- Serialise this login's calls until commit, then check what it already owns.
  perform pg_advisory_xact_lock(hashtextextended('create_my_arena:' || v_user::text, 0));
  if exists (select 1 from staff_profiles where user_id = v_user and role = 'owner') then
    raise exception 'arena_limit' using hint = 'this login already owns an arena';
  end if;
  return _create_arena_with_owner(v_user, v_arena, v_owner);
end;
$function$;

create or replace function private.my_arenas()
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'arena_id', s.arena_id, 'arena_name', a.name, 'name', s.name, 'role', s.role,
      'perms', to_jsonb(s.perms), 'active', s.active) order by a.name), '[]'::jsonb)
    from staff_profiles s join arenas a on a.id = s.arena_id
   where s.user_id = auth.uid();
$function$;

create or replace function private.sync_fetch_entity (
  p_arena uuid,
  p_refs  jsonb
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_ref  jsonb;
  v_id   uuid;
  v_rows jsonb;
  v_out  jsonb := '[]'::jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  for v_ref in select value from jsonb_array_elements(coalesce(p_refs, '[]'::jsonb)) loop
    v_id := nullif(v_ref->>'id', '')::uuid;
    -- controller_moves point at their session/group via session_ref
    -- ('s:<session id>' or 'g:<group id>'), not a uuid column.
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
$function$;

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
  v_union text;
  v_out   jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
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
  for v_op in select value from jsonb_array_elements(coalesce(p_ops, '[]'::jsonb)) loop
    v_id := (v_op->>'op_id')::uuid;
    v_kind := v_op->>'kind';
    -- Two pushes of the same op (a retry racing the original) queue here.
    perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));
    select * into v_prev from sync_ops where op_id = v_id;
    if found then
      if v_prev.arena_id <> p_arena then raise exception 'op_id_reused'; end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', v_prev.status, 'result', v_prev.result, 'error', v_prev.error_code,
        'detail', v_prev.error_message, 'replayed', true));
      continue;
    end if;
    begin
      v_res := _sync_apply(p_arena, v_kind, coalesce(v_op->'payload', '{}'::jsonb));
      if v_res is null then raise exception 'unknown_op' using hint = coalesce(v_kind, 'null'); end if;
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, result)
        values (v_id, p_arena, auth.uid(), p_device, v_kind, 'applied', v_res);
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'applied', 'result', v_res, 'replayed', false));
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text,
        v_hint = pg_exception_hint;
      -- Transient (serialization failure, deadlock, lock not available, query
      -- cancelled): not recorded, so the device resends this op and the rest later.
      if v_state in ('40001', '40P01', '55P03', '57014') then
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

create or replace function public._need (
  p_arena uuid,
  p_perm  text
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_has_perm(p_arena, p_perm) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs ' || p_perm;
  end if;
end;
$function$;

create or replace function public.add_member_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns uuid
  language sql
  set search_path to ''
  AS $function$
  select private.add_member_by_email(p_arena, p_email, p_name, p_role, p_perms);
$function$;

revoke all
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  from public, "anon";

create or replace function public.add_staff_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_perms text[]
)
  returns uuid
  language sql
  set search_path to ''
  AS $function$
  select private.add_staff_by_email(p_arena, p_email, p_name, p_perms);
$function$;

create or replace function public.app_is_owner (
  p_arena uuid
)
  returns boolean
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.app_is_owner(p_arena);
$function$;

create or replace function public.arena_pricing (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_pricing(p_arena);
$function$;

revoke all on function "public"."arena_pricing"(uuid) from public, "anon";

create or replace function public.arena_sale (
  p_arena uuid,
  p_id    uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_sale(p_arena, p_id);
$function$;

revoke all on function "public"."arena_sale"(uuid, uuid) from public, "anon";

create or replace function public.arena_sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_sales(p_arena, p_from, p_to);
$function$;

revoke all
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  from public, "anon";

create or replace function public.arena_staff (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_staff(p_arena);
$function$;

revoke all on function "public"."arena_staff"(uuid) from public, "anon";

create or replace function public.create_my_arena (
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language sql
  set search_path to ''
  AS $function$
  select private.create_my_arena(p_arena_name, p_owner_name);
$function$;

revoke all on function "public"."create_my_arena"(text, text) from public, "anon";

create or replace function public.my_arenas()
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.my_arenas();
$function$;

create or replace function public.op_controller_move (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_cid uuid := (p->>'controller_id')::uuid;
  v_kind text := p->>'kind';
  v_to uuid := nullif(p->>'to_resource_id','')::uuid;
  v_loc uuid; v_home uuid; v_loc2 uuid; v_home2 uuid;
begin
  if v_kind is null or v_kind not in ('loan','permanent','returnHome') then
    raise exception 'move_kind_invalid';
  end if;
  -- Carrying a pad (loan / return) is floor work: it needs start or settings
  -- (0016). Re-homing it (permanent) changes the inventory: settings.
  if v_kind in ('loan', 'returnHome')
     and not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'settings')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or settings';
  end if;
  if v_kind = 'permanent' then perform _need(p_arena, 'settings'); end if;
  select current_resource_id, home_resource_id into v_loc, v_home
    from controllers where id = v_cid and arena_id = p_arena;
  if not found then raise exception 'controller_missing'; end if;
  if v_kind = 'returnHome' then v_to := v_home; end if;
  if not exists (select 1 from resources where id = v_to and arena_id = p_arena) then
    raise exception 'resource_missing';
  end if;
  perform _lock_resources(p_arena, array[v_loc, v_to]);
  perform _lock_pads(p_arena, array[v_cid]);
  -- Stations are locked before pads (the order every op uses), so the pad was
  -- read unlocked above. If it moved or was re-homed in between, the stations
  -- we hold are the wrong ones: retry rather than move it unlocked.
  select current_resource_id, home_resource_id into v_loc2, v_home2 from controllers where id = v_cid;
  if v_loc2 is distinct from v_loc or v_home2 is distinct from v_home then
    raise exception 'retry' using errcode = '40001';
  end if;
  if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  update controllers
     set current_resource_id = v_to,
         home_resource_id = case when v_kind = 'permanent' then v_to else home_resource_id end,
         loan_return_to   = case when v_kind = 'loan' then v_home::text end,
         loan_session_ref = case when v_kind = 'loan' then p->>'session_ref' end,
         updated_at = v_now
   where id = v_cid;
  if v_to = v_loc then
    -- Nothing physically moved (e.g. a return already done on another device):
    -- the device's history row is not mirrored, so it should refetch.
    return jsonb_build_object('moved', false, 'adjusted', nullif(p->>'move_id','') is not null);
  end if;
  insert into controller_moves(id, arena_id, controller_id, from_resource_id, to_resource_id, kind,
      session_ref, moved_at, created_by, created_at)
    values (coalesce(nullif(p->>'move_id','')::uuid, gen_random_uuid()), p_arena, v_cid, v_loc,
      v_to, v_kind, case when v_kind = 'loan' then p->>'session_ref' end,
      coalesce((p->>'at')::timestamptz, v_now), auth.uid(), v_now);
  -- adjusted: no move_id was sent, so the server minted the history row id; the device refetches.
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$function$;

create or replace function public.op_customer_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_phone text := nullif(btrim(p->>'phone'), '');
  v_other uuid;
begin
  if not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  -- A phone already in use (two devices registering the same person offline) must not sink
  -- the sessions that reference this customer: keep the row phone-less and audit the clash.
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from v_now at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  if v_phone is not null then
    select id into v_other from customers where arena_id = p_arena and phone = v_phone;
  end if;
  insert into customers(id, arena_id, name, phone, notes, last_visit_at, is_guest, created_at, updated_at,
      birth_year)
    values ((p->>'id')::uuid, p_arena, p->>'name', case when v_other is null then v_phone end,
      p->>'notes', (p->>'last_visit_at')::timestamptz, coalesce((p->>'is_guest')::boolean, false),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now, (p->>'birth_year')::smallint);
  if v_other is not null then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
      values (p_arena, 'customer', (p->>'id')::uuid, 'duplicate_phone_on_sync',
        'phone already belongs to another customer', jsonb_build_object('phone', v_phone,
        'existing_customer_id', v_other), auth.uid(), v_now);
    return jsonb_build_object('adjusted', true, 'phone_taken_by', v_other);
  end if;
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_customer_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8;
begin
  if not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from statement_timestamp() at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  select sync_xid into v_xid from customers where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'customer'; end if;
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the customer was edited on another device';
  end if;
  begin
    update customers set name = p->>'name', phone = nullif(btrim(p->>'phone'), ''),
        notes = p->>'notes',
        -- Builds that do not send birth_year keep the stored one.
        birth_year = case when p ? 'birth_year' then (p->>'birth_year')::smallint else birth_year end,
        updated_at = statement_timestamp()
      where id = (p->>'id')::uuid;
  exception when unique_violation then
    raise exception 'phone_taken';
  end;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_group_void (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from group_sessions where id = v_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  -- greatest(): never end a row before it started, whatever the device clock said.
  update group_assignments set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'group_session', v_group, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_session_void (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_status text;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  update session_segments set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where session_id = v_session and ended_at is null;
  update sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'session', v_session, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
end;
$function$;

create or replace function public.op_staff_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  -- money / reports make a member "owner level" (app_is_owner, and the app's
  -- AppUser.isOwner). Only an owner-level member may hand them out or take them away.
  c_owner_perms constant text[] := array['money', 'reports'];
  v_user   uuid    := (p->>'user_id')::uuid;
  v_perms  text[]  := array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb)));
  v_active boolean := coalesce((p->>'active')::boolean, true);
  v_role   text;
  v_old_perms  text[];
  v_old_active boolean;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  perform _assert_known_perms(v_perms);
  select role, perms, active into v_role, v_old_perms, v_old_active from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;

  if v_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
    end if;
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    v_adj := not (v_perms @> _known_perms()) or not v_active;
    v_perms := _known_perms();
    v_active := true;
  else
    -- Nobody changes their own access: a Settings holder could otherwise grant
    -- themselves money/reports and become owner level.
    if v_user = auth.uid()
       and (not (v_perms @> v_old_perms and v_old_perms @> v_perms) or v_active <> v_old_active) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'you cannot change your own permissions';
    end if;
    -- Owner-level perms, and owner-level members, are managed by owners only.
    if not private.app_is_owner(p_arena)
       and (v_old_perms && c_owner_perms
            or ('money' = any(v_perms)) <> ('money' = any(v_old_perms))
            or ('reports' = any(v_perms)) <> ('reports' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports, or change an owner-level member';
    end if;
  end if;

  update staff_profiles set name = p->>'name', perms = v_perms, active = v_active,
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then '{"adjusted": true}'::jsonb else '{}'::jsonb end;
end;
$function$;

create or replace function public.sync_fetch_entity (
  p_arena uuid,
  p_refs  jsonb
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.sync_fetch_entity(p_arena, p_refs);
$function$;

revoke all on function "public"."sync_fetch_entity"(uuid, jsonb) from public, "anon";

create or replace function public.sync_pull (
  p_arena  uuid,
  p_cursor text    default '0'::text,
  p_limit  integer default 2000
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.sync_pull(p_arena, p_cursor, p_limit);
$function$;

revoke all on function "public"."sync_pull"(uuid, text, integer) from public, "anon";

create or replace function public.sync_push (
  p_arena  uuid,
  p_ops    jsonb,
  p_device text  default null::text
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.sync_push(p_arena, p_ops, p_device);
$function$;

revoke all on function "public"."sync_push"(uuid, jsonb, text) from public, "anon";

create policy "p_sel_activities" on "public"."activities"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_arenas" on "public"."arenas"
  for select
  to "authenticated"
  using ((id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_audit_log" on "public"."audit_log"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_billing_policies" on "public"."billing_policies"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_bookings" on "public"."bookings"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_controller_allocations" on "public"."controller_allocations"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_controller_moves" on "public"."controller_moves"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_controllers" on "public"."controllers"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_customers" on "public"."customers"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_game_categories" on "public"."game_categories"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_game_controls" on "public"."game_controls"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_game_resources" on "public"."game_resources"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_games" on "public"."games"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_assignments" on "public"."group_assignments"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_charges" on "public"."group_charges"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_extensions" on "public"."group_extensions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_payments" on "public"."group_payments"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_group_sessions" on "public"."group_sessions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_holidays" on "public"."holidays"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_payments" on "public"."payments"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_rate_bands" on "public"."rate_bands"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_rate_cards" on "public"."rate_cards"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_rates" on "public"."rates"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_resource_activities" on "public"."resource_activities"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_resources" on "public"."resources"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_session_charges" on "public"."session_charges"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_session_extensions" on "public"."session_extensions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_session_segments" on "public"."session_segments"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_sessions" on "public"."sessions"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_settings" on "public"."settings"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_staff" on "public"."staff_profiles"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

comment on function "private"."add_member_by_email"(uuid, text, text, text, text[]) is
  'Client API: link an existing login to the arena as staff (owner level caller; perms as given) or as a co-owner (owner caller; every permission; promotes an existing staff profile). Refuses existing owners, the caller themselves, unknown permissions and leaving nobody with Settings.';

comment on function "private"."add_staff_by_email"(uuid, text, text, text[]) is
  'Client API (owner level): link an existing login to the arena as a staff profile with the given permissions, reactivating and overwriting an existing staff profile. Refuses owners'' profiles, unknown permissions, and leaving nobody with Settings.';

comment on function "private"."app_arena_ids"() is 'Arena ids where the signed-in user has an active staff profile; the membership test used by RLS policies and the sync RPCs.';

comment on function "private"."app_has_perm"(uuid, text) is 'True when the signed-in user is an active member of the arena and is an owner or holds the given permission.';

comment on function "private"."app_is_owner"(uuid) is 'True when the signed-in user is owner level in the arena: an active profile with role owner, or holding the money or reports permission.';

comment on function "private"."arena_pricing"(uuid) is 'Client API (owner level): the arena''s station types with station counts, active rates and business/happy hours, for the admin dashboard''s Pricing screen.';

comment on function "private"."arena_sale"(uuid, uuid) is 'Client API (owner level): one closed bill with its charge lines, extensions, payments ledger and void record, for the admin dashboard''s Sales detail.';

comment on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp
  with time zone) is 'Client API (owner level): the arena''s closed bills (sessions and groups, completed or voided) that closed in [from, to), newest first, for the admin dashboard''s Sales screen. At most 93 days.';

comment on function "private"."arena_staff"(uuid) is 'Client API (owner level): the arena''s staff with login e-mail, never-signed-in flag and 30-day bills, net takings and refunds they recorded, for the admin dashboard''s Staff screen.';

comment on function "private"."create_my_arena"(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

comment on function "private"."my_arenas"() is 'Client API: the signed-in user''s staff profiles across arenas (including inactive ones) as a jsonb array of {arena_id, arena_name, name, role, perms, active}.';

comment on function "private"."sync_fetch_entity"(uuid, jsonb) is 'Client API (sync): for each {type, id} ref, return the server''s current rows for that whole entity (session, group, controller, customer or booking) so a device can replace its copy after a refused op.';

comment on function "private"."sync_pull"(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

comment on function "private"."sync_push"(uuid, jsonb, text) is 'Client API (sync): apply a batch of device ops in order, each at most once per op_id (recorded in sync_ops), and return each op''s status: applied, rejected (with error code) or retry.';

comment on function "public"."add_member_by_email"(uuid, text, text, text, text[]) is
  'Client API: link an existing login to the arena as staff (owner level caller; perms as given) or as a co-owner (owner caller; every permission; promotes an existing staff profile). Refuses existing owners, the caller themselves, unknown permissions and leaving nobody with Settings.';

comment on function "public"."arena_pricing"(uuid) is 'Client API (owner level): the arena''s station types with station counts, active rates and business/happy hours, for the admin dashboard''s Pricing screen.';

comment on function "public"."arena_sale"(uuid, uuid) is 'Client API (owner level): one closed bill with its charge lines, extensions, payments ledger and void record, for the admin dashboard''s Sales detail.';

comment on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp
  with time zone) is 'Client API (owner level): the arena''s closed bills (sessions and groups, completed or voided) that closed in [from, to), newest first, for the admin dashboard''s Sales screen. At most 93 days.';

comment on function "public"."arena_staff"(uuid) is 'Client API (owner level): the arena''s staff with login e-mail, never-signed-in flag and 30-day bills, net takings and refunds they recorded, for the admin dashboard''s Staff screen.';

comment on function "public"."create_my_arena"(text, text) is 'Client API (self-serve sign-up): a confirmed login creates one arena with the default catalog and becomes its owner. Refuses unconfirmed logins, blank or over-long names, and a login that already owns an arena (arena_limit).';

comment on function "public"."sync_fetch_entity"(uuid, jsonb) is 'Client API (sync): for each {type, id} ref, return the server''s current rows for that whole entity (session, group, controller, customer or booking) so a device can replace its copy after a refused op.';

comment on function "public"."sync_pull"(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

comment on function "public"."sync_push"(uuid, jsonb, text) is 'Client API (sync): apply a batch of device ops in order, each at most once per op_id (recorded in sync_ops), and return each op''s status: applied, rejected (with error code) or retry.';

comment on schema "private" is 'SECURITY DEFINER bodies of the client API and the RLS helpers; not exposed over the Data API.';

revoke all on function "private"."add_member_by_email"(uuid, text, text, text, text[]) from public;

grant execute
  on function "private"."add_member_by_email"(uuid, text, text, text, text[])
  to "authenticated";

revoke all
  on function "private"."add_member_by_email"(uuid, text, text, text, text[])
  from "postgres";

grant execute
  on function "private"."add_member_by_email"(uuid, text, text, text, text[])
  to "postgres";

grant execute
  on function "private"."add_member_by_email"(uuid, text, text, text, text[])
  to "service_role";

revoke all on function "private"."add_staff_by_email"(uuid, text, text, text[]) from public;

grant execute
  on function "private"."add_staff_by_email"(uuid, text, text, text[])
  to "authenticated";

revoke all on function "private"."add_staff_by_email"(uuid, text, text, text[]) from "postgres";

grant execute on function "private"."add_staff_by_email"(uuid, text, text, text[]) to "postgres";

grant execute on function "private"."add_staff_by_email"(uuid, text, text, text[]) to "service_role";

revoke all on function "private"."app_arena_ids"() from public;

grant execute on function "private"."app_arena_ids"() to "authenticated";

revoke all on function "private"."app_arena_ids"() from "postgres";

grant execute on function "private"."app_arena_ids"() to "postgres";

grant execute on function "private"."app_arena_ids"() to "service_role";

revoke all on function "private"."app_has_perm"(uuid, text) from public;

grant execute on function "private"."app_has_perm"(uuid, text) to "authenticated";

revoke all on function "private"."app_has_perm"(uuid, text) from "postgres";

grant execute on function "private"."app_has_perm"(uuid, text) to "postgres";

grant execute on function "private"."app_has_perm"(uuid, text) to "service_role";

revoke all on function "private"."app_is_owner"(uuid) from public;

grant execute on function "private"."app_is_owner"(uuid) to "authenticated";

revoke all on function "private"."app_is_owner"(uuid) from "postgres";

grant execute on function "private"."app_is_owner"(uuid) to "postgres";

grant execute on function "private"."app_is_owner"(uuid) to "service_role";

revoke all on function "private"."arena_pricing"(uuid) from public;

grant execute on function "private"."arena_pricing"(uuid) to "authenticated";

revoke all on function "private"."arena_pricing"(uuid) from "postgres";

grant execute on function "private"."arena_pricing"(uuid) to "postgres";

grant execute on function "private"."arena_pricing"(uuid) to "service_role";

revoke all on function "private"."arena_sale"(uuid, uuid) from public;

grant execute on function "private"."arena_sale"(uuid, uuid) to "authenticated";

revoke all on function "private"."arena_sale"(uuid, uuid) from "postgres";

grant execute on function "private"."arena_sale"(uuid, uuid) to "postgres";

grant execute on function "private"."arena_sale"(uuid, uuid) to "service_role";

revoke all
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  from public;

grant execute
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "authenticated";

revoke all
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  from "postgres";

grant execute
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "postgres";

grant execute
  on function "private"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "service_role";

revoke all on function "private"."arena_staff"(uuid) from public;

grant execute on function "private"."arena_staff"(uuid) to "authenticated";

revoke all on function "private"."arena_staff"(uuid) from "postgres";

grant execute on function "private"."arena_staff"(uuid) to "postgres";

grant execute on function "private"."arena_staff"(uuid) to "service_role";

revoke all on function "private"."create_my_arena"(text, text) from public;

grant execute on function "private"."create_my_arena"(text, text) to "authenticated";

revoke all on function "private"."create_my_arena"(text, text) from "postgres";

grant execute on function "private"."create_my_arena"(text, text) to "postgres";

grant execute on function "private"."create_my_arena"(text, text) to "service_role";

revoke all on function "private"."my_arenas"() from public;

grant execute on function "private"."my_arenas"() to "authenticated";

revoke all on function "private"."my_arenas"() from "postgres";

grant execute on function "private"."my_arenas"() to "postgres";

grant execute on function "private"."my_arenas"() to "service_role";

revoke all on function "private"."sync_fetch_entity"(uuid, jsonb) from public;

grant execute on function "private"."sync_fetch_entity"(uuid, jsonb) to "authenticated";

revoke all on function "private"."sync_fetch_entity"(uuid, jsonb) from "postgres";

grant execute on function "private"."sync_fetch_entity"(uuid, jsonb) to "postgres";

grant execute on function "private"."sync_fetch_entity"(uuid, jsonb) to "service_role";

revoke all on function "private"."sync_pull"(uuid, text, integer) from public;

grant execute on function "private"."sync_pull"(uuid, text, integer) to "authenticated";

revoke all on function "private"."sync_pull"(uuid, text, integer) from "postgres";

grant execute on function "private"."sync_pull"(uuid, text, integer) to "postgres";

grant execute on function "private"."sync_pull"(uuid, text, integer) to "service_role";

revoke all on function "private"."sync_push"(uuid, jsonb, text) from public;

grant execute on function "private"."sync_push"(uuid, jsonb, text) to "authenticated";

revoke all on function "private"."sync_push"(uuid, jsonb, text) from "postgres";

grant execute on function "private"."sync_push"(uuid, jsonb, text) to "postgres";

grant execute on function "private"."sync_push"(uuid, jsonb, text) to "service_role";

grant execute
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  to "authenticated";

revoke all
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  from "postgres";

grant execute
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  to "postgres";

grant execute
  on function "public"."add_member_by_email"(uuid, text, text, text, text[])
  to "service_role";

grant execute on function "public"."arena_pricing"(uuid) to "authenticated";

revoke all on function "public"."arena_pricing"(uuid) from "postgres";

grant execute on function "public"."arena_pricing"(uuid) to "postgres";

grant execute on function "public"."arena_pricing"(uuid) to "service_role";

grant execute on function "public"."arena_sale"(uuid, uuid) to "authenticated";

revoke all on function "public"."arena_sale"(uuid, uuid) from "postgres";

grant execute on function "public"."arena_sale"(uuid, uuid) to "postgres";

grant execute on function "public"."arena_sale"(uuid, uuid) to "service_role";

grant execute
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "authenticated";

revoke all
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  from "postgres";

grant execute
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "postgres";

grant execute
  on function "public"."arena_sales"(uuid, timestamp with time zone, timestamp with time zone)
  to "service_role";

grant execute on function "public"."arena_staff"(uuid) to "authenticated";

revoke all on function "public"."arena_staff"(uuid) from "postgres";

grant execute on function "public"."arena_staff"(uuid) to "postgres";

grant execute on function "public"."arena_staff"(uuid) to "service_role";

grant execute on function "public"."create_my_arena"(text, text) to "authenticated";

revoke all on function "public"."create_my_arena"(text, text) from "postgres";

grant execute on function "public"."create_my_arena"(text, text) to "postgres";

grant execute on function "public"."create_my_arena"(text, text) to "service_role";

grant execute on function "public"."sync_fetch_entity"(uuid, jsonb) to "authenticated";

revoke all on function "public"."sync_fetch_entity"(uuid, jsonb) from "postgres";

grant execute on function "public"."sync_fetch_entity"(uuid, jsonb) to "postgres";

grant execute on function "public"."sync_fetch_entity"(uuid, jsonb) to "service_role";

grant execute on function "public"."sync_pull"(uuid, text, integer) to "authenticated";

revoke all on function "public"."sync_pull"(uuid, text, integer) from "postgres";

grant execute on function "public"."sync_pull"(uuid, text, integer) to "postgres";

grant execute on function "public"."sync_pull"(uuid, text, integer) to "service_role";

grant execute on function "public"."sync_push"(uuid, jsonb, text) to "authenticated";

revoke all on function "public"."sync_push"(uuid, jsonb, text) from "postgres";

grant execute on function "public"."sync_push"(uuid, jsonb, text) to "postgres";

grant execute on function "public"."sync_push"(uuid, jsonb, text) to "service_role";

grant usage on schema "private" to "authenticated", "service_role";

alter default privileges for role "postgres" in schema "private" revoke all on FUNCTIONS from public;

alter default privileges for role "postgres" in schema "private" grant execute
  on FUNCTIONS to "service_role";
