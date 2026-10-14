set local check_function_bodies = off;

create table "public"."bill_discounts" (
  "id"           uuid                     not null default gen_random_uuid(),
  "arena_id"     uuid                     not null,
  "session_id"   uuid,
  "group_id"     uuid,
  "discount_id"  uuid,
  "source"       text                     not null,
  "name"         text                     not null,
  "code"         text,
  "value_kind"   text                     not null,
  "value"        bigint                   not null,
  "base_paise"   bigint                   not null,
  "amount_paise" bigint                   not null,
  "reason"       text,
  "applied_by"   uuid,
  "applied_at"   timestamp with time zone not null,
  "created_at"   timestamp with time zone not null default now(),
  "sync_xid"     xid8                     not null default pg_current_xact_id(),
  constraint "bill_discounts_amount_check"
    check (((amount_paise >= 0) AND (amount_paise <= base_paise))),
  constraint "bill_discounts_manual_check"
    check (((source = 'manual'::text) = (discount_id IS NULL))),
  constraint "bill_discounts_one_bill_check" check (((session_id IS NULL) <> (group_id IS NULL))),
  constraint "bill_discounts_pkey" primary key (id),
  constraint "bill_discounts_source_check"
    check ((source = ANY (ARRAY['preset'::text, 'coupon'::text, 'manual'::text]))),
  constraint "bill_discounts_value_kind_check"
    check ((value_kind = ANY (ARRAY['percent'::text, 'flat'::text])))
);

alter table "public"."bill_discounts"
  enable row level security;

create table "public"."discounts" (
  "id"                 uuid                     not null default gen_random_uuid(),
  "arena_id"           uuid                     not null,
  "kind"               text                     not null,
  "name"               text                     not null,
  "code"               text,
  "value_kind"         text                     not null,
  "value"              bigint                   not null,
  "max_discount_paise" bigint,
  "min_bill_paise"     bigint,
  "activity_codes"     text[]                   not null default '{}'::text[],
  "valid_from"         timestamp with time zone,
  "valid_until"        timestamp with time zone,
  "max_uses"           integer,
  "active"             boolean                  not null default true,
  "created_at"         timestamp with time zone not null default now(),
  "updated_at"         timestamp with time zone not null default now(),
  "sync_xid"           xid8                     not null default pg_current_xact_id(),
  constraint "discounts_code_check"
    check
    ((((kind = 'coupon'::text) AND (code ~ '^[A-Z0-9_-]{3,20}$'::text)) OR ((kind = 'preset'::text)
    AND (code IS NULL)))),
  constraint "discounts_kind_check" check ((kind = ANY (ARRAY['preset'::text, 'coupon'::text]))),
  constraint "discounts_max_discount_check"
    check (((max_discount_paise IS NULL) OR (max_discount_paise >= 1))),
  constraint "discounts_max_uses_check" check (((max_uses IS NULL) OR (max_uses >= 1))),
  constraint "discounts_min_bill_check" check (((min_bill_paise IS NULL) OR (min_bill_paise >= 0))),
  constraint "discounts_name_check"
    check (((char_length(name) >= 1) AND (char_length(name) <= 40))),
  constraint "discounts_pkey" primary key (id),
  constraint "discounts_valid_check"
    check (((valid_from IS NULL) OR (valid_until IS NULL) OR (valid_from < valid_until))),
  constraint "discounts_value_check"
    check
    ((((value_kind = 'percent'::text) AND (value >= 1) AND (value <= 100)) OR ((value_kind =
    'flat'::text) AND (value >= 1) AND (value <= 100000000))))
);

alter table "public"."discounts"
  enable row level security;

create or replace function private.arena_discount_usage (
  p_arena    uuid,
  p_discount uuid,
  p_limit    integer                  default 40,
  p_before   timestamp with time zone default null::timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_limit int := least(greatest(coalesce(p_limit, 40), 1), 100);
  v_rows  jsonb;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read sales';
  end if;
  if not exists (select 1 from discounts where id = p_discount and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'discount';
  end if;

  select coalesce(jsonb_agg(x.j order by x.at desc, x.id desc), '[]'::jsonb) into v_rows
    from (select d.id, d.applied_at as at, jsonb_build_object(
              'bill_id', coalesce(d.session_id, d.group_id),
              'kind', case when d.session_id is not null then 'single' else 'group' end,
              'at', d.applied_at, 'customer', c.name,
              'billed_paise', coalesce(s.billed_amount_paise, g.billed_amount_paise),
              'amount_paise', d.amount_paise, 'base_paise', d.base_paise,
              'status', coalesce(s.status, g.status), 'by', sp.name) as j
            from bill_discounts d
            left join sessions s on s.id = d.session_id
            left join group_sessions g on g.id = d.group_id
            left join customers c on c.id = coalesce(s.customer_id, g.primary_customer_id)
            left join staff_profiles sp on sp.arena_id = d.arena_id and sp.user_id = d.applied_by
           where d.arena_id = p_arena and d.discount_id = p_discount
             and (p_before is null or d.applied_at < p_before)
           order by d.applied_at desc, d.id desc
           limit v_limit + 1) x;

  return jsonb_build_object(
    'uses', (select count(*) from bill_discounts where discount_id = p_discount),
    'active_uses', (select count(*) from bill_discounts d
                      left join sessions s on s.id = d.session_id
                      left join group_sessions g on g.id = d.group_id
                     where d.discount_id = p_discount and coalesce(s.status, g.status) <> 'voided'),
    'rows', case when jsonb_array_length(v_rows) > v_limit then v_rows - v_limit else v_rows end,
    'next', case when jsonb_array_length(v_rows) > v_limit
                 then v_rows->(v_limit - 1)->'at' end);
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
      'rule', (
        select _pr_rule(s.pricing_snapshot, g.activity_code, s.started_at)
          from sessions s
          join lateral (select activity_code from session_segments
                         where session_id = s.id order by idx limit 1) g on true
         where s.id = p_id));
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
      'rule', (
        select _pr_rule(gs.pricing_snapshot, g.activity_code, gs.started_at)
          from group_sessions gs
          join lateral (select activity_code from group_assignments
                         where group_id = gs.id order by player_number, idx limit 1) g on true
         where gs.id = p_id));
  end if;

  return v_bill || jsonb_build_object(
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('at', l.created_at, 'action', l.action, 'by', sp.name,
          'reason', l.reason, 'before', l.before, 'after', l.after)
        order by l.created_at, l.id)
        from audit_log l
        left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
       where l.arena_id = p_arena and l.entity_id = p_id
         and l.entity_type = case when v_bill->>'kind' = 'group' then 'group_session' else 'session' end),
      '[]'::jsonb),
    'voided', (
      select jsonb_build_object('at', l.created_at, 'by', sp.name, 'reason', l.reason)
        from audit_log l
        left join staff_profiles sp on sp.arena_id = l.arena_id and sp.user_id = l.created_by
       where l.arena_id = p_arena and l.entity_id = p_id and l.action = 'void'
       order by l.created_at limit 1));
end;
$function$;

create or replace function public._discount_apply (
  p_arena   uuid,
  p_disc    jsonb,
  p_bill    jsonb,
  p_at      timestamp with time zone,
  p_session uuid,
  p_group   uuid
)
  returns bigint
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_sub    bigint := (p_bill->>'subtotal')::bigint;
  v_d      discounts%rowtype;
  v_manual jsonb := p_disc->'manual';
  v_reason text := nullif(btrim(coalesce(p_disc->>'reason', '')), '');
  v_opts   jsonb;
  v_source text; v_name text; v_code text; v_vkind text; v_value bigint;
  v_base   bigint; v_amount bigint; v_max int; v_uses int;
begin
  if v_manual is not null then
    perform _need(p_arena, 'discount');
    v_vkind := v_manual->>'value_kind';
    v_value := (v_manual->>'value')::bigint;
    if v_value is null or not ((v_vkind = 'percent' and v_value between 1 and 100)
                               or (v_vkind = 'flat' and v_value >= 1)) then
      raise exception 'invalid_discount';
    end if;
    v_source := 'manual'; v_name := 'Manual discount'; v_base := v_sub;
  else
    if p_disc ? 'code' then
      select * into v_d from discounts
       where arena_id = p_arena and kind = 'coupon' and code = upper(btrim(p_disc->>'code')) for update;
      if not found then raise exception 'coupon_unknown'; end if;
    else
      select * into v_d from discounts
       where arena_id = p_arena and id = (p_disc->>'discount_id')::uuid for update;
      if not found then raise exception 'not_found' using hint = 'discount'; end if;
    end if;
    if not v_d.active then raise exception 'discount_inactive'; end if;
    if v_d.valid_from is not null and p_at < v_d.valid_from then
      raise exception 'discount_not_started' using hint = v_d.valid_from::text;
    end if;
    if v_d.valid_until is not null and p_at > v_d.valid_until then
      raise exception 'coupon_expired' using hint = v_d.valid_until::text;
    end if;
    if v_d.max_uses is not null then
      select count(*) into v_uses from bill_discounts b
        left join sessions s on s.id = b.session_id
        left join group_sessions g on g.id = b.group_id
       where b.discount_id = v_d.id and coalesce(s.status, g.status) <> 'voided';
      if v_uses >= v_d.max_uses then raise exception 'coupon_used_up'; end if;
    end if;
    if v_d.min_bill_paise is not null and v_sub < v_d.min_bill_paise then
      raise exception 'discount_min_bill' using hint = v_d.min_bill_paise::text;
    end if;
    v_base := case when cardinality(v_d.activity_codes) = 0 then v_sub
                   else coalesce((select sum(value::bigint) from jsonb_each_text(p_bill->'by_activity')
                                   where key = any(v_d.activity_codes)), 0) end;
    if v_base <= 0 and cardinality(v_d.activity_codes) > 0 then
      raise exception 'discount_scope';
    end if;
    v_source := v_d.kind; v_name := v_d.name; v_code := v_d.code;
    v_vkind := v_d.value_kind; v_value := v_d.value;
  end if;

  v_amount := case when v_vkind = 'percent' then _pr_div(v_base * v_value, 100) else v_value end;
  if v_d.max_discount_paise is not null then v_amount := least(v_amount, v_d.max_discount_paise); end if;
  v_amount := greatest(0, least(v_amount, v_base));

  if v_source = 'manual' then
    select json into v_opts from settings where arena_id = p_arena and key = 'discount_options';
    if not private.app_has_perm(p_arena, 'settings') then
      v_max := coalesce((v_opts->>'manual_max_percent')::int, 0);
      if v_amount > _pr_div(v_sub * v_max, 100) then
        raise exception 'discount_over_limit' using hint = v_max::text || '%';
      end if;
    end if;
    if coalesce((v_opts->>'reason_required')::boolean, false) and v_reason is null then
      raise exception 'discount_reason_required';
    end if;
  end if;

  if (p_disc->>'amount_paise')::bigint is distinct from v_amount then
    perform _price_mismatch('discount', v_amount, (p_disc->>'amount_paise')::bigint);
  end if;

  insert into bill_discounts(id, arena_id, session_id, group_id, discount_id, source, name, code,
      value_kind, value, base_paise, amount_paise, reason, applied_by, applied_at)
    values (coalesce(nullif(p_disc->>'id', '')::uuid, gen_random_uuid()), p_arena, p_session, p_group,
      v_d.id, v_source, v_name, v_code, v_vkind, v_value, v_base, v_amount, v_reason, auth.uid(), p_at);
  return v_amount;
end;
$function$;

create or replace function public._discount_options (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('manual_max_percent', 'reason_required')) then
    raise exception 'invalid_discount_options'
      using hint = 'an object of manual_max_percent and reason_required';
  end if;
  if jsonb_typeof(p->'manual_max_percent') is distinct from 'number'
     or (p->>'manual_max_percent')::numeric % 1 <> 0
     or (p->>'manual_max_percent')::numeric not between 0 and 100 then
    raise exception 'invalid_discount_options' using hint = 'manual_max_percent: whole 0–100';
  end if;
  if jsonb_typeof(p->'reason_required') is distinct from 'boolean' then
    raise exception 'invalid_discount_options' using hint = 'reason_required: true or false';
  end if;
  return jsonb_build_object('manual_max_percent', (p->>'manual_max_percent')::int,
    'reason_required', (p->>'reason_required')::boolean);
end;
$function$;

create or replace function public._pr_group_bill (
  p_group    uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  g group_sessions; v_snap jsonb; pol jsonb; r uuid; part jsonb; q jsonb; v_act text;
  v_sub bigint := 0; v_keys text[] := '{}'; v_by jsonb := '{}'::jsonb; v_k text;
begin
  select * into g from group_sessions where id = p_group;
  v_snap := g.pricing_snapshot;
  pol := _pr_policy(v_snap);
  if g.billing_mode = 'shared_controller_pool' then
    -- The purchased controllers, once, over the whole group window.
    select activity_code into v_act from group_assignments
     where group_id = p_group and controller_count is not null
     order by player_number, idx limit 1;
    if g.purchased_controller_count > 0 and v_act is not null and p_open_end > g.started_at then
      q := _pr_quote(v_snap, v_act, g.purchased_controller_count, g.started_at, p_open_end,
        g.started_at);
      if q is not null then
        v_sub := v_sub + (q->>'subtotal')::bigint;
        v_by := jsonb_set(v_by, array[v_act], to_jsonb(coalesce((v_by->>v_act)::bigint, 0) + (q->>'subtotal')::bigint));
        v_keys := v_keys || _pr_keys(q, v_act, null, g.purchased_controller_count);
      end if;
    end if;
  end if;
  for r in select distinct resource_id from group_assignments where group_id = p_group loop
    part := _pr_sweep(v_snap, p_group, r, p_open_end, g.billing_mode = 'shared_controller_pool');
    v_sub := v_sub + (part->>'subtotal')::bigint;
    v_keys := v_keys || array(select jsonb_array_elements_text(part->'keys'));
    for v_k in select jsonb_object_keys(part->'by_activity') loop
      v_by := jsonb_set(v_by, array[v_k], to_jsonb(coalesce((v_by->>v_k)::bigint, 0) + (part->'by_activity'->>v_k)::bigint));
    end loop;
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')),
    'by_activity', v_by);
end;
$function$;

create or replace function public._pr_session_bill (
  p_session  uuid,
  p_open_end timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; v_started timestamptz; seg record; q jsonb;
  v_sub bigint := 0; v_keys text[] := '{}'; pol jsonb; v_by jsonb := '{}'::jsonb;
begin
  select pricing_snapshot, started_at into v_snap, v_started from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  for seg in select * from session_segments where session_id = p_session order by idx loop
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      coalesce(seg.ended_at, p_open_end), v_started);   -- pricing rule judged at the session start
    continue when q is null;     -- no rate: contributes nothing (device warns)
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_by := jsonb_set(v_by, array[seg.activity_code], to_jsonb(coalesce((v_by->>seg.activity_code)::bigint, 0) + (q->>'subtotal')::bigint));
    v_keys := v_keys || _pr_keys(q, seg.activity_code, seg.resource_id, seg.controller_count);
  end loop;
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'keys', to_jsonb(coalesce((select array_agg(k order by k) from unnest(v_keys) k), '{}')),
    'by_activity', v_by);
end;
$function$;

create or replace function public._pr_sweep (
  v_snap           jsonb,
  p_group          uuid,
  p_res            uuid,
  p_open_end       timestamp with time zone,
  p_no_controllers boolean
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  ws timestamptz[]; we timestamptz[]; wc int[]; wa text[];
  v_pts timestamptz[]; i int; j int; s timestamptz; e timestamptz;
  v_cc int; v_act text; v_n int; q jsonb; v_started timestamptz;
  v_sub bigint := 0; v_keys text[] := '{}'; v_by jsonb := '{}'::jsonb;
begin
  select started_at into v_started from group_sessions where id = p_group;
  -- Windows in the device's list order (player, then index); empty ones dropped.
  select coalesce(array_agg(started_at order by player_number, idx), '{}'),
         coalesce(array_agg(coalesce(ended_at, p_open_end) order by player_number, idx), '{}'),
         coalesce(array_agg(controller_count order by player_number, idx), '{}'),
         coalesce(array_agg(activity_code order by player_number, idx), '{}')
    into ws, we, wc, wa
    from group_assignments
   where group_id = p_group and resource_id = p_res
     and (not p_no_controllers or controller_count is null)
     and coalesce(ended_at, p_open_end) > started_at;
  select array_agg(distinct x order by x) into v_pts
    from (select unnest(ws) as x union all select unnest(we)) t;
  for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
    s := v_pts[i]; e := v_pts[i + 1];
    continue when e <= s;
    v_n := 0; v_cc := 0; v_act := null;
    for j in 1 .. coalesce(array_length(ws, 1), 0) loop
      if ws[j] <= s and we[j] >= e then
        v_n := v_n + 1;
        v_cc := v_cc + coalesce(wc[j], 0);
        v_act := coalesce(v_act, wa[j]);
      end if;
    end loop;
    continue when v_n = 0;
    q := _pr_quote(v_snap, v_act, nullif(v_cc, 0), s, e, v_started);   -- rule judged at the group start
    continue when q is null;     -- misconfigured rate: excluded, as on the device
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_by := jsonb_set(v_by, array[v_act], to_jsonb(coalesce((v_by->>v_act)::bigint, 0) + (q->>'subtotal')::bigint));
    v_keys := v_keys || _pr_keys(q, v_act, p_res, nullif(v_cc, 0));
  end loop;
  return jsonb_build_object('subtotal', v_sub, 'keys', to_jsonb(v_keys), 'by_activity', v_by);
end;
$function$;

create or replace function public._sales (
  p_arena uuid,
  p_from  timestamp with time zone,
  p_to    timestamp with time zone,
  p_id    uuid                     default null::uuid
)
  returns SETOF jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
      'kind', 'single', 'id', s.id, 'at', b.at,
      'started_at', s.started_at, 'ended_at', s.actual_ended_at, 'recorded_at', s.created_at,
      'status', s.status, 'payment_status', s.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = s.customer_id and o.arena_id = s.arena_id
                   and o.id <> s.id and o.status = 'completed' and o.started_at < s.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = s.customer_id and o.arena_id = s.arena_id
                      and o.status = 'completed' and o.started_at < s.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', seg.players, 'player_minutes', seg.player_minutes,
      'billed_paise', s.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', s.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by,
      'discount_paise', coalesce(dsc.amount, 0), 'discount', dsc.j)
    from sessions s
    cross join lateral (select coalesce(s.actual_ended_at, s.updated_at) as at) b
    join customers c on c.id = s.customer_id
    left join staff_profiles sp on sp.arena_id = s.arena_id and sp.user_id = s.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.idx) as first
                                 from session_segments g join resources r on r.id = g.resource_id
                                where g.session_id = s.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.idx) as first
                                 from session_segments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.session_id = s.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.idx) as first
                                 from session_segments g join games gm on gm.id = g.game_id
                                where g.session_id = s.id group by gm.name) x), '[]'::jsonb) as games,
             coalesce((select max(g.controller_count) from session_segments g
                        where g.session_id = s.id), 1) as players,
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0 * coalesce(g.controller_count, 1)))::int
                         from session_segments g where g.session_id = s.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from payments
                                where session_id = s.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.kind = 'refund', 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.session_id = s.id), '[]'::jsonb) as ledger
        from payments p where p.session_id = s.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = s.arena_id and l.entity_type = 'session' and l.entity_id = s.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
    left join lateral (
      select d.amount_paise as amount,
             jsonb_build_object('source', d.source, 'name', d.name, 'code', d.code,
               'discount_id', d.discount_id, 'value_kind', d.value_kind, 'value', d.value,
               'base_paise', d.base_paise, 'amount_paise', d.amount_paise, 'reason', d.reason,
               'by', sd.name) as j
        from bill_discounts d
        left join staff_profiles sd on sd.arena_id = d.arena_id and sd.user_id = d.applied_by
       where d.session_id = s.id
    ) dsc on true
   where s.arena_id = p_arena and s.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else s.id = p_id end)
  union all
  select jsonb_build_object(
      'kind', 'group', 'id', gs.id, 'at', b.at,
      'started_at', gs.started_at, 'ended_at', gs.actual_ended_at, 'recorded_at', gs.created_at,
      'status', gs.status, 'payment_status', gs.payment_status,
      'customer', c.name, 'guest', c.is_guest,
      'returning', not c.is_guest and (
        exists (select 1 from sessions o
                 where o.customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                   and o.status = 'completed' and o.started_at < gs.started_at)
        or exists (select 1 from group_sessions o
                    where o.primary_customer_id = gs.primary_customer_id and o.arena_id = gs.arena_id
                      and o.id <> gs.id and o.status = 'completed' and o.started_at < gs.started_at)),
      'stations', seg.stations, 'activities', seg.activities, 'games', seg.games,
      'players', gs.player_count, 'player_minutes', seg.player_minutes,
      'billed_paise', gs.billed_amount_paise, 'paid_paise', pay.net,
      'refunded_paise', pay.refunded, 'methods', pay.methods, 'payments', pay.ledger,
      'started_by', sp.name, 'void_reason', gs.void_reason,
      'voided_at', vd.at, 'voided_by', vd.by,
      'discount_paise', coalesce(dsc.amount, 0), 'discount', dsc.j)
    from group_sessions gs
    cross join lateral (select coalesce(gs.actual_ended_at, gs.updated_at) as at) b
    join customers c on c.id = gs.primary_customer_id
    left join staff_profiles sp on sp.arena_id = gs.arena_id and sp.user_id = gs.created_by
    cross join lateral (
      select coalesce((select jsonb_agg(x.name order by x.first)
                         from (select r.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join resources r on r.id = g.resource_id
                                where g.group_id = gs.id group by r.name) x), '[]'::jsonb) as stations,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select a.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g
                                 join activities a on a.arena_id = g.arena_id and a.code = g.activity_code
                                where g.group_id = gs.id group by a.name) x), '[]'::jsonb) as activities,
             coalesce((select jsonb_agg(x.name order by x.first)
                         from (select gm.name, min(g.player_number * 1000 + g.idx) as first
                                 from group_assignments g join games gm on gm.id = g.game_id
                                where g.group_id = gs.id group by gm.name) x), '[]'::jsonb) as games,
             -- Each assignment is one player's stretch on one station.
             coalesce((select round(sum(extract(epoch from (coalesce(g.ended_at, b.at) - g.started_at))
                                        / 60.0))::int
                         from group_assignments g where g.group_id = gs.id), 0) as player_minutes
    ) seg
    cross join lateral (
      select coalesce(array_agg(x.id), '{}'::uuid[]) as ids
        from audit_log l
        cross join lateral (values ((l.after->>'refund_id')::uuid), ((l.after->>'payment_id')::uuid)) x(id)
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'payment_correct'
    ) corr
    cross join lateral (
      select coalesce(sum(p.amount_paise), 0) as net,
             coalesce(-sum(p.amount_paise) filter (where p.amount_paise < 0
                                                    and p.id <> all (corr.ids)), 0) as refunded,
             coalesce((select jsonb_object_agg(m.method, m.net)
                         from (select method, sum(amount_paise) as net from group_payments
                                where group_id = gs.id group by method) m), '{}'::jsonb) as methods,
             coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at', q.created_at,
                                 'amount_paise', q.amount_paise, 'method', q.method,
                                 'refund', q.is_refund, 'correction', q.id = any (corr.ids),
                                 'reason', q.reason, 'note', q.note, 'by', sq.name)
                               order by q.created_at, q.id)
                         from group_payments q
                         left join staff_profiles sq on sq.arena_id = q.arena_id and sq.user_id = q.created_by
                        where q.group_id = gs.id), '[]'::jsonb) as ledger
        from group_payments p where p.group_id = gs.id
    ) pay
    left join lateral (
      select l.created_at as at, sv.name as by
        from audit_log l
        left join staff_profiles sv on sv.arena_id = l.arena_id and sv.user_id = l.created_by
       where l.arena_id = gs.arena_id and l.entity_type = 'group_session' and l.entity_id = gs.id
         and l.action = 'void'
       order by l.created_at limit 1
    ) vd on true
    left join lateral (
      select d.amount_paise as amount,
             jsonb_build_object('source', d.source, 'name', d.name, 'code', d.code,
               'discount_id', d.discount_id, 'value_kind', d.value_kind, 'value', d.value,
               'base_paise', d.base_paise, 'amount_paise', d.amount_paise, 'reason', d.reason,
               'by', sd.name) as j
        from bill_discounts d
        left join staff_profiles sd on sd.arena_id = d.arena_id and sd.user_id = d.applied_by
       where d.group_id = gs.id
    ) dsc on true
   where gs.arena_id = p_arena and gs.status <> 'active'
     and (case when p_id is null then b.at >= p_from and b.at < p_to else gs.id = p_id end);
$function$;

create or replace function public._sync_apply (
  p_arena uuid,
  p_kind  text,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_before jsonb; v_res jsonb;
begin
  -- A price-list change retires the previous catalog into
  -- pricing_catalog_history, so a session priced on it still validates.
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove',
                'rule.upsert', 'rule.delete', 'rule.reorder') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;

  -- Dispatch: one op kind -> one op_* function. Unknown kinds return null and
  -- sync_push rejects them.
  v_res := case p_kind
      when 'session.start'        then op_session_start(p_arena, p)
      when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
      when 'session.extend'       then op_session_extend(p_arena, p)
      when 'session.end'          then op_session_end(p_arena, p)
      when 'session.void'         then op_session_void(p_arena, p)
      when 'payment.record'       then op_payment(p_arena, p)
      when 'payment.correct'      then op_payment_correct(p_arena, p)
      when 'group.create'         then op_group_create(p_arena, p)
      when 'group.add'            then op_group_add(p_arena, p)
      when 'group.switch'         then op_group_switch(p_arena, p)
      when 'group.end_player'     then op_group_end_player(p_arena, p)
      when 'group.extend'         then op_group_extend(p_arena, p)
      when 'group.end'            then op_group_end(p_arena, p)
      when 'group.void'           then op_group_void(p_arena, p)
      when 'controller.move'      then op_controller_move(p_arena, p)
      when 'controller.upsert'    then op_controller_upsert(p_arena, p)
      when 'controller.set_status' then op_controller_set_status(p_arena, p)
      when 'accessory_kind.upsert' then op_accessory_kind_upsert(p_arena, p)
      when 'accessory_kind.remove' then op_accessory_kind_remove(p_arena, p)
      when 'customer.create'      then op_customer_create(p_arena, p)
      when 'customer.update'      then op_customer_update(p_arena, p)
      when 'booking.create'       then op_booking_create(p_arena, p)
      when 'booking.update'       then op_booking_update(p_arena, p)
      when 'booking.set_status'   then op_booking_set_status(p_arena, p)
      when 'game.upsert'          then op_game_upsert(p_arena, p)
      when 'game.set_active'      then op_game_set_active(p_arena, p)
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'rule.upsert'          then op_rule_upsert(p_arena, p)
      when 'rule.delete'          then op_rule_delete(p_arena, p)
      when 'rule.reorder'         then op_rule_reorder(p_arena, p)
      when 'discount.upsert'      then op_discount_upsert(p_arena, p)
      when 'discount.set_active'  then op_discount_set_active(p_arena, p)
      when 'discount.delete'      then op_discount_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      else null
    end;

  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$function$;

create or replace function public._sync_sources()
  returns table (
    name text,
    rel  text
  )
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
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
    ('controller_moves','controller_moves'), ('settings','settings'),
    ('accessory_kinds','accessory_kinds'), ('pricing_rules','pricing_rules'),
    ('discounts','discounts'), ('bill_discounts','bill_discounts')
$function$;

create or replace function public.arena_discount_usage (
  p_arena    uuid,
  p_discount uuid,
  p_limit    integer                  default 40,
  p_before   timestamp with time zone default null::timestamp with time zone
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_discount_usage(p_arena, p_discount, p_limit, p_before);
$function$;

create or replace function public.op_discount_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_used int;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from discounts where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'discount';
  end if;
  perform 1 from discounts where id = v_id and arena_id = p_arena for update;
  if not found then return '{}'::jsonb; end if;
  select count(*) into v_used from bill_discounts where discount_id = v_id;
  if v_used > 0 then raise exception 'discount_used' using hint = v_used::text; end if;
  delete from discounts where id = v_id;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_discount_set_active (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  update discounts set active = coalesce((p->>'active')::boolean, false),
      updated_at = statement_timestamp()
   where id = (p->>'id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'discount'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_discount_upsert (
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
  v_kind  text := p->>'kind';
  v_name  text := btrim(coalesce(p->>'name', ''));
  v_code  text := nullif(upper(btrim(coalesce(p->>'code', ''))), '');
  v_vkind text := p->>'value_kind';
  v_value bigint := (p->>'value')::bigint;
  v_cap   bigint := nullif(p->>'max_discount_paise', '')::bigint;
  v_min   bigint := nullif(p->>'min_bill_paise', '')::bigint;
  v_uses  int := nullif(p->>'max_uses', '')::int;
  v_from  timestamptz := nullif(p->>'valid_from', '')::timestamptz;
  v_until timestamptz := nullif(p->>'valid_until', '')::timestamptz;
  v_codes text[] := array(select distinct upper(btrim(x)) from jsonb_array_elements_text(
                          coalesce(p->'activity_codes', '[]'::jsonb)) x order by 1);
  v_old   discounts%rowtype;
  v_bad   text;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from discounts where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'discount';
  end if;
  if v_kind is null or v_kind not in ('preset', 'coupon') then
    raise exception 'invalid_discount' using hint = 'kind';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if v_kind = 'coupon' and (v_code is null or v_code !~ '^[A-Z0-9_-]{3,20}$') then
    raise exception 'invalid_code' using hint = '3–20 of A–Z, 0–9, - or _';
  end if;
  if v_kind = 'preset' then v_code := null; end if;
  if v_value is null or not ((v_vkind = 'percent' and v_value between 1 and 100)
                             or (v_vkind = 'flat' and v_value between 1 and 100000000))
     or coalesce(v_cap, 1) < 1 or coalesce(v_min, 0) < 0 or coalesce(v_uses, 1) < 1
     or (v_from is not null and v_until is not null and v_from >= v_until) then
    raise exception 'invalid_discount';
  end if;
  select c into v_bad from unnest(v_codes) c
   where not exists (select 1 from activities where arena_id = p_arena and code = c) limit 1;
  if v_bad is not null then raise exception 'unknown_type' using hint = v_bad; end if;

  select * into v_old from discounts where id = v_id and arena_id = p_arena for update;
  if found and v_old.kind <> v_kind and exists (select 1 from bill_discounts where discount_id = v_id) then
    raise exception 'kind_locked' using hint = v_old.kind;
  end if;

  insert into discounts(id, arena_id, kind, name, code, value_kind, value, max_discount_paise,
      min_bill_paise, activity_codes, valid_from, valid_until, max_uses, active)
    values (v_id, p_arena, v_kind, v_name, v_code, v_vkind, v_value,
      case when v_vkind = 'percent' then v_cap end, v_min, v_codes, v_from, v_until, v_uses,
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    kind = excluded.kind, name = excluded.name, code = excluded.code,
    value_kind = excluded.value_kind, value = excluded.value,
    max_discount_paise = excluded.max_discount_paise, min_bill_paise = excluded.min_bill_paise,
    activity_codes = excluded.activity_codes, valid_from = excluded.valid_from,
    valid_until = excluded.valid_until, max_uses = excluded.max_uses, active = excluded.active,
    updated_at = statement_timestamp()
  where discounts.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_group_end (
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
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_end timestamptz; v_ids uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[]; v_disc bigint := 0; v_total bigint; pol jsonb;
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the group was changed on another device';
  end if;
  update group_assignments set ended_at = v_ended where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = v_ended where group_id = v_group and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into group_charges(id, arena_id, group_id, assignment_id, player_number, charge_index,
        band_code, activity_code, resource_id, controller_count, segment_start, segment_end,
        played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_group, nullif(v_c->>'assignment_id','')::uuid,
        nullif(v_c->>'player_number','')::int, (v_c->>'charge_index')::int, v_c->>'band_code',
        v_c->>'activity_code', nullif(v_c->>'resource_id','')::uuid,
        nullif(v_c->>'controller_count','')::int, (v_c->>'segment_start')::timestamptz,
        (v_c->>'segment_end')::timestamptz, (v_c->>'played_minutes')::int,
        (v_c->>'billed_minutes')::int, (v_c->>'unit_minutes')::int,
        (v_c->>'unit_price_paise')::bigint, (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_group;
  -- Payments may already have been taken against the running bill.
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_group;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason; optional here so floor builds that do not send it still end the group).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'group_session', v_group, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored assignments
  -- and refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  v_bill := _pr_group_bill(v_group, v_ended);
  v_total := (v_bill->>'total')::bigint;
  -- A discount (preset, coupon or manual) comes off the subtotal before cash rounding.
  if jsonb_typeof(p->'discount') = 'object' then
    if v_waive then raise exception 'invalid_discount' using hint = 'a waived bill takes no discount'; end if;
    v_disc := _discount_apply(p_arena, p->'discount', v_bill, v_ended,
      null, v_group);
    select _pr_policy(pricing_snapshot) into pol from group_sessions where id = v_group;
    v_total := _pr_money((v_bill->>'subtotal')::bigint - v_disc, (pol->>'money_rounding_paise')::int,
      pol->>'money_rounding_dir');
  end if;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from group_charges where group_id = v_group) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_session_end (
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
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_status text; v_end timestamptz; v_segs uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[]; v_disc bigint := 0; v_total bigint; pol jsonb;
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select coalesce(array_agg(id), '{}') into v_segs from session_segments where session_id = v_session;
  if not _same_ids(v_segs, _jsonb_uuids(p->'expected_segment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;

  update session_segments set ended_at = v_ended where session_id = v_session and ended_at is null;
  update controller_allocations set ended_at = v_ended where session_id = v_session and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into session_charges(id, arena_id, session_id, segment_id, segment_index, band_code,
        activity_code, resource_id, controller_count, segment_start, segment_end, played_minutes,
        billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_session, nullif(v_c->>'segment_id','')::uuid,
        (v_c->>'segment_index')::int, v_c->>'band_code', v_c->>'activity_code',
        nullif(v_c->>'resource_id','')::uuid, nullif(v_c->>'controller_count','')::int,
        (v_c->>'segment_start')::timestamptz, (v_c->>'segment_end')::timestamptz,
        (v_c->>'played_minutes')::int, (v_c->>'billed_minutes')::int,
        (v_c->>'unit_minutes')::int, (v_c->>'unit_price_paise')::bigint,
        (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_session;
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_session;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason; optional here so floor builds that do not send it still end the session).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'session', v_session, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored segments and
  -- refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended);
  v_total := (v_bill->>'total')::bigint;
  -- A discount (preset, coupon or manual) comes off the subtotal before cash rounding.
  if jsonb_typeof(p->'discount') = 'object' then
    if v_waive then raise exception 'invalid_discount' using hint = 'a waived bill takes no discount'; end if;
    v_disc := _discount_apply(p_arena, p->'discount', v_bill, v_ended,
      v_session, null);
    select _pr_policy(pricing_snapshot) into pol from sessions where id = v_session;
    v_total := _pr_money((v_bill->>'subtotal')::bigint - v_disc, (pol->>'money_rounding_paise')::int,
      pol->>'money_rounding_dir');
  end if;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from session_charges where session_id = v_session) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_settings_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_json jsonb := p->'json';
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours', 'floor_options', 'discount_options') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  elsif p->>'key' = 'discount_options' then
    v_json := _discount_options(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

alter table "public"."bill_discounts"
  add constraint "bill_discounts_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."bill_discounts"
  add constraint "bill_discounts_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade;

alter table "public"."bill_discounts"
  add constraint "bill_discounts_session_id_fkey" foreign key (session_id)
    references public.sessions(id) on delete cascade;

alter table "public"."discounts"
  add constraint "discounts_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."bill_discounts"
  add constraint "bill_discounts_discount_id_fkey" foreign key (discount_id)
    references public.discounts(id);

create index ix_bill_discounts_discount on public.bill_discounts
  using btree (discount_id, applied_at);

create index ix_bill_discounts_sync on public.bill_discounts using btree (arena_id, sync_xid);

create index ix_discounts_sync on public.discounts using btree (arena_id, sync_xid);

create unique index ux_bill_discounts_group on public.bill_discounts using btree (group_id)
  where (group_id is not null);

create unique index ux_bill_discounts_session on public.bill_discounts using btree (session_id)
  where (session_id is not null);

create unique index ux_discounts_code on public.discounts using btree (arena_id, code)
  where (code is not null);

create trigger t_bill_discounts_sync
  before insert or update on public.bill_discounts
  for each row
  execute function public.sync_stamp();

create trigger t_bill_discounts_tomb
  after delete on public.bill_discounts
  for each row
  execute function public.sync_record_delete();

create trigger t_same_arena
  before insert or update on public.bill_discounts
  for each row
  execute function
    public._assert_same_arena('session_id', 'sessions', 'group_id', 'group_sessions', 'discount_id',
    'discounts');

create trigger t_discounts_sync
  before insert or update on public.discounts
  for each row
  execute function public.sync_stamp();

create trigger t_discounts_tomb
  after delete on public.discounts
  for each row
  execute function public.sync_record_delete();

create trigger t_discounts_updated
  before update on public.discounts
  for each row
  execute function public.set_updated_at();

create policy "p_sel_bill_discounts" on "public"."bill_discounts"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_discounts" on "public"."discounts"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

comment on column "public"."bill_discounts"."amount_paise" is 'Paise taken off the subtotal before cash rounding.';

comment on column "public"."bill_discounts"."applied_at" is 'When the bill ended (device-reported end instant): the moment validity is judged at.';

comment on column "public"."bill_discounts"."arena_id" is 'Owning arena (tenant). RLS limits reads to members holding bill, money or reports.';

comment on column "public"."bill_discounts"."base_paise" is 'The part of the bill subtotal the discount applied to (its station types; the whole subtotal when unscoped).';

comment on column "public"."bill_discounts"."code" is 'Coupon code used; null otherwise.';

comment on column "public"."bill_discounts"."discount_id" is 'The preset or coupon used; null for a manual discount.';

comment on column "public"."bill_discounts"."name" is 'Discount name at the time (manual: "Manual discount").';

comment on column "public"."bill_discounts"."reason" is 'Why it was given (required for manual discounts when Settings ask for a reason).';

comment on column "public"."bill_discounts"."source" is 'preset, coupon or manual (typed in by staff with the discount permission).';

comment on column "public"."bill_discounts"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."discounts"."activity_codes" is 'Station types (activities.code) whose charges the discount applies to; empty = the whole bill.';

comment on column "public"."discounts"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."discounts"."code" is 'Coupon code, upper-case A–Z, 0–9, - or _ (3–20), unique per arena; null for a preset.';

comment on column "public"."discounts"."kind" is 'preset: picked by staff from a list; coupon: entered by its code.';

comment on column "public"."discounts"."max_discount_paise" is 'Upper limit of a percent discount in paise; null = no limit.';

comment on column "public"."discounts"."max_uses" is 'How many bills (voided ones excluded) may use it; null = unlimited.';

comment on column "public"."discounts"."min_bill_paise" is 'Smallest bill subtotal (before discount) the discount may be used on; null = any.';

comment on column "public"."discounts"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."discounts"."valid_from" is 'First instant a bill may end with this discount; null = no start.';

comment on column "public"."discounts"."valid_until" is 'Expiry: last instant a bill may end with this discount; null = never expires.';

comment on column "public"."discounts"."value" is 'Percent (1–100) or paise, per value_kind.';

comment on column "public"."discounts"."value_kind" is 'percent (value 1–100 % of the bill part in scope) or flat (value in paise).';

comment on function "private"."arena_discount_usage"(uuid, uuid, integer, timestamp
  with time zone) is 'Client API (owner level): the bills a preset discount or coupon was used on, newest first, paged by applied time, with use counts.';

comment on function "public"."_discount_apply"(uuid, jsonb, jsonb, timestamp
  with time zone, uuid, uuid) is 'Validates a preset, coupon or manual discount against a bill, records it in bill_discounts and returns the paise taken off.';

comment on function "public"."_discount_options"(jsonb) is 'Validates and normalises the discount_options setting (manual_max_percent 0–100, reason_required).';

comment on function "public"."arena_discount_usage"(uuid, uuid, integer, timestamp
  with time zone) is 'Client API (owner level): the bills a preset discount or coupon was used on, newest first, paged by applied time, with use counts.';

comment on function "public"."op_discount_delete"(uuid, jsonb) is 'Sync op discount.delete: deletes a preset or coupon that no bill has used (a used one is turned off instead).';

comment on function "public"."op_discount_set_active"(uuid, jsonb) is 'Sync op discount.set_active: turns a preset discount or coupon on or off.';

comment on function "public"."op_discount_upsert"(uuid, jsonb) is 'Sync op discount.upsert: creates or edits a preset discount or a coupon (value, scope, cap, minimum, validity, use limit).';

comment on table "public"."bill_discounts" is 'The discount applied to a bill (session or group), with a snapshot of the discount, the amount taken off, who applied it and why. Append-only; one per bill.';

comment on table "public"."discounts" is 'Owner-defined discounts: presets staff pick and coupon codes, percent or flat, with type scope, cap, minimum bill, validity window and use limit. Applied ones are recorded in bill_discounts.';

revoke all
  on function "private"."arena_discount_usage"(uuid, uuid, integer, timestamp with time zone)
  from public;

grant execute
  on function "private"."arena_discount_usage"(uuid, uuid, integer, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all
  on function "public"."_discount_apply"(uuid, jsonb, jsonb, timestamp with time zone, uuid, uuid)
  from public;

grant execute
  on function "public"."_discount_apply"(uuid, jsonb, jsonb, timestamp with time zone, uuid, uuid)
  to "postgres", "service_role";

revoke all on function "public"."_discount_options"(jsonb) from public;

grant execute on function "public"."_discount_options"(jsonb) to "postgres", "service_role";

revoke all
  on function "public"."arena_discount_usage"(uuid, uuid, integer, timestamp with time zone)
  from public;

grant execute
  on function "public"."arena_discount_usage"(uuid, uuid, integer, timestamp with time zone)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."op_discount_delete"(uuid, jsonb) from public;

grant execute on function "public"."op_discount_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_discount_set_active"(uuid, jsonb) from public;

grant execute
  on function "public"."op_discount_set_active"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_discount_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_discount_upsert"(uuid, jsonb) to "postgres", "service_role";

grant select on table "public"."bill_discounts" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."bill_discounts"
  to "postgres", "service_role";

grant select on table "public"."discounts" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."discounts"
  to "postgres", "service_role";
