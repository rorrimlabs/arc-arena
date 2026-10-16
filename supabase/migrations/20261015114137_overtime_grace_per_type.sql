set local check_function_bodies = off;

alter table "public"."billing_policies"
  drop constraint "billing_policies_overtime_grace_minutes_check";

alter table "public"."billing_policies"
  drop column "overtime_grace_minutes";

alter table "public"."activities"
  add column "overtime_grace_minutes" integer not null default 0;

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
          'duration_model', a.duration_model, 'overtime_grace_minutes', a.overtime_grace_minutes,
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
        from sync_v_rates v where v.arena_id = p_arena and v.band = 'standard'), '[]'::jsonb),
    'hours', jsonb_build_object('open', _pricing_snapshot(p_arena)->'hours'->'open'));
end;
$function$;

create or replace function public._pr_policy (
  s jsonb
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select '{"billing_unit":"per_minute","block_rounding":"up","grace_minutes":0,
    "minimum_charge_minutes":0,"early_exit":"actual","rounding_scope":"session",
    "late_arrival":"actual","vr_unit_rounding":"up","money_rounding_paise":100,
    "money_rounding_dir":"nearest","payment_timing":"either","allow_extend_past_close":false,
    "cleaning_gap_minutes":0,"group_billing_mode":"per_system"}'::jsonb
    || coalesce(s->'policy', '{}'::jsonb);
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
  v_sched timestamptz; v_last timestamptz; v_until timestamptz; v_end timestamptz;
  v_grace int;
begin
  select pricing_snapshot, started_at, scheduled_end_at into v_snap, v_started, v_sched
    from sessions where id = p_session;
  pol := _pr_policy(v_snap);
  select max(coalesce(ended_at, p_open_end)) into v_last
    from session_segments where session_id = p_session;
  -- The grace of the type the session ends on (absent from an older snapshot: none).
  select coalesce((a->>'overtime_grace_minutes')::int, 0) into v_grace
    from session_segments sg
    cross join lateral jsonb_array_elements(coalesce(v_snap->'activities', '[]'::jsonb)) a
   where sg.session_id = p_session and a->>'code' = sg.activity_code
   order by sg.idx desc limit 1;
  -- Ended within the overtime grace: bill to the booked end only.
  if coalesce(v_grace, 0) > 0 and v_last > v_sched
     and v_last - v_sched <= make_interval(mins => v_grace) then
    v_until := v_sched;
  end if;
  for seg in select * from session_segments where session_id = p_session order by idx loop
    v_end := coalesce(seg.ended_at, p_open_end);
    if v_until is not null then
      continue when seg.started_at >= v_until;   -- wholly inside the forgiven overtime
      v_end := least(v_end, v_until);
    end if;
    q := _pr_quote(v_snap, seg.activity_code, seg.controller_count, seg.started_at,
      v_end, v_started);   -- pricing rule judged at the session start
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

create or replace function public._pricing_canon (
  s jsonb
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  select jsonb_build_object(
    'rates', coalesce((select jsonb_agg(jsonb_build_object('a', r->>'activity_code',
        'b', r->>'band', 'c', (r->>'controller_count')::int, 'u', (r->>'unit_minutes')::int,
        'p', (r->>'price_paise')::bigint)
        order by r->>'activity_code', r->>'band', coalesce((r->>'controller_count')::int, -1),
                 (r->>'unit_minutes')::int, (r->>'price_paise')::bigint)
        from jsonb_array_elements(coalesce(s->'rates', '[]'::jsonb)) r), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', a->>'code',
        'model', a->>'duration_model',
        -- Absent (an older device or snapshot) = no grace.
        'grace', coalesce((a->>'overtime_grace_minutes')::int, 0))
        order by a->>'code', a->>'duration_model')
        from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a), '[]'::jsonb),
    'policy', _pr_policy(s),
    'hours', (select jsonb_object_agg(kind, (select jsonb_object_agg(d::text,
        case when jsonb_typeof(s->'hours'->kind->(d::text)) = 'object'
             then jsonb_build_object('start', (s->'hours'->kind->(d::text)->>'start')::int,
                                     'end', (s->'hours'->kind->(d::text)->>'end')::int)
             else 'null'::jsonb end) from generate_series(1, 7) d))
        from unnest(array['open']) kind),
    'holidays', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'holidays', '[]'::jsonb)) x), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'closed_days', '[]'::jsonb)) x), '[]'::jsonb))
  -- Rules only when the snapshot has any, so a rule-free canon is unchanged.
  || coalesce((select jsonb_build_object('rules', jsonb_agg(jsonb_build_object(
        'id', r->>'id', 'name', r->>'name', 'priority', (r->>'priority')::int,
        'days', (select jsonb_agg(distinct d::int order by d::int)
                   from jsonb_array_elements_text(r->'days') d),
        'start_min', (r->>'start_min')::int, 'end_min', (r->>'end_min')::int,
        'holiday_mode', r->>'holiday_mode', 'valid_from', r->>'valid_from',
        'valid_until', r->>'valid_until',
        'activity_codes', coalesce((select jsonb_agg(distinct c order by c)
                   from jsonb_array_elements_text(r->'activity_codes') c), '[]'::jsonb),
        'adjust_kind', r->>'adjust_kind', 'adjust_value', (r->>'adjust_value')::int)
        order by (r->>'priority')::int, r->>'name' collate "C", r->>'id' collate "C"))
        from jsonb_array_elements(coalesce(s->'rules', '[]'::jsonb)) r
        having count(*) > 0), '{}'::jsonb);
$function$;

create or replace function public._pricing_snapshot (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select jsonb_build_object(
    'rate_card_name', 'Current',
    'rates', coalesce((select jsonb_agg(jsonb_build_object('activity_code', activity_code,
        'band', band, 'controller_count', controller_count, 'unit_minutes', unit_minutes,
        'price_paise', price_paise)) from sync_v_rates
        where arena_id = p_arena and band = 'standard'), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', code,
        'duration_model', duration_model, 'overtime_grace_minutes', overtime_grace_minutes))
        from activities where arena_id = p_arena), '[]'::jsonb),
    'policy', coalesce((select jsonb_build_object('billing_unit', billing_unit,
        'block_rounding', block_rounding, 'grace_minutes', grace_minutes,
        'minimum_charge_minutes', minimum_charge_minutes, 'early_exit', early_exit,
        'rounding_scope', rounding_scope, 'late_arrival', late_arrival,
        'vr_unit_rounding', vr_unit_rounding, 'money_rounding_paise', money_rounding_paise,
        'money_rounding_dir', money_rounding_dir, 'payment_timing', payment_timing,
        'allow_extend_past_close', allow_extend_past_close,
        'cleaning_gap_minutes', cleaning_gap_minutes, 'group_billing_mode', group_billing_mode)
        from billing_policies where arena_id = p_arena and active order by created_at limit 1),
        _pr_policy('{}'::jsonb)),
    -- BusinessHours.current() when the owner never saved hours.
    'hours', coalesce((select json from settings where arena_id = p_arena and key = 'business_hours'),
      '{"open":{"1":null,"2":{"start":840,"end":1380},"3":{"start":840,"end":1380},
                "4":{"start":840,"end":1380},"5":{"start":840,"end":1380},
                "6":{"start":840,"end":1380},"7":{"start":840,"end":1380}}}'::jsonb),
    'holidays', coalesce((select jsonb_agg(day::text) from holidays where arena_id = p_arena), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(day::text) from holidays
        where arena_id = p_arena and closed), '[]'::jsonb))
  -- Active pricing rules, only when there are any: an arena without rules keeps
  -- exactly the snapshot (and canon) floor apps built before rules produce.
  || coalesce((select jsonb_build_object('rules', jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'priority', r.priority, 'days', to_jsonb(r.days),
        'start_min', r.start_min, 'end_min', r.end_min, 'holiday_mode', r.holiday_mode,
        'valid_from', r.valid_from, 'valid_until', r.valid_until,
        'activity_codes', to_jsonb(r.activity_codes), 'adjust_kind', r.adjust_kind,
        'adjust_value', r.adjust_value)
        order by r.priority, r.name collate "C", r.id::text collate "C"))
        from pricing_rules r where r.arena_id = p_arena and r.active
        having count(*) > 0), '{}'::jsonb);
$function$;

create or replace function public.op_activity_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_code text := upper(btrim(coalesce(p->>'code', '')));
  v_name text := btrim(coalesce(p->>'name', ''));
  v_pads boolean := coalesce((p->>'uses_controllers')::boolean, false);
  v_old  activities%rowtype;
  v_base text;
  v_n    int := 1;
begin
  perform _need(p_arena, 'settings');
  if v_code = '' then
    select code into v_code from activities where id = v_id and arena_id = p_arena;
    if v_code is null then
      v_base := left(btrim(regexp_replace(upper(v_name), '[^A-Z0-9]+', '_', 'g'), '_'), 12);
      if v_base = '' then v_base := 'TYPE'; end if;
      v_code := v_base;
      while exists (select 1 from activities where arena_id = p_arena and code = v_code) loop
        v_n := v_n + 1;
        v_code := left(v_base, 12 - char_length(v_n::text) - 1) || '_' || v_n;
      end loop;
    end if;
  end if;
  if v_code !~ '^[A-Z0-9_]{1,12}$' then
    raise exception 'invalid_code' using hint = 'A–Z, 0–9 or _, up to 12';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if exists (select 1 from activities where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'activity';
  end if;

  select * into v_old from activities where id = v_id and arena_id = p_arena for update;
  if found then
    if v_old.code <> v_code then
      raise exception 'code_locked' using hint = v_old.code;
    end if;
    if v_old.uses_controllers <> v_pads and (
         exists (select 1 from session_segments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)
      or exists (select 1 from group_assignments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)) then
      raise exception 'activity_busy' using hint = v_code;
    end if;
  end if;

  insert into activities(id, arena_id, code, name, uses_controllers, uses_games, duration_model,
      sort_order, active, overtime_grace_minutes)
    values (v_id, p_arena, v_code, v_name, v_pads,
      coalesce((p->>'uses_games')::boolean, false),
      coalesce(p->>'duration_model', 'hourly'),
      coalesce((p->>'sort_order')::int, 0),
      coalesce((p->>'active')::boolean, true),
      coalesce((p->>'overtime_grace_minutes')::int, v_old.overtime_grace_minutes, 0))
  on conflict (id) do update set
    name = excluded.name, uses_controllers = excluded.uses_controllers,
    uses_games = excluded.uses_games, duration_model = excluded.duration_model,
    sort_order = excluded.sort_order, overtime_grace_minutes = excluded.overtime_grace_minutes,
    active = excluded.active, updated_at = statement_timestamp()
  where activities.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_policy_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare j jsonb := p->'policy'; v_id uuid;
begin
  perform _need(p_arena, 'settings');
  select id into v_id from billing_policies where arena_id = p_arena and active
    order by created_at limit 1 for update;
  if not found then
    insert into billing_policies(arena_id, name) values (p_arena, 'Default') returning id into v_id;
  end if;
  update billing_policies set
      billing_unit = j->>'billing_unit', block_rounding = j->>'block_rounding',
      grace_minutes = (j->>'grace_minutes')::int,
      minimum_charge_minutes = (j->>'minimum_charge_minutes')::int,
      early_exit = j->>'early_exit', rounding_scope = j->>'rounding_scope',
      late_arrival = j->>'late_arrival', vr_unit_rounding = j->>'vr_unit_rounding',
      money_rounding_paise = (j->>'money_rounding_paise')::int,
      money_rounding_dir = j->>'money_rounding_dir', payment_timing = j->>'payment_timing',
      allow_extend_past_close = (j->>'allow_extend_past_close')::boolean,
      cleaning_gap_minutes = (j->>'cleaning_gap_minutes')::int,
      group_billing_mode = coalesce(j->>'group_billing_mode', 'per_system'),
      updated_at = statement_timestamp()
    where id = v_id;
  return '{}'::jsonb;
end;
$function$;

alter table "public"."activities"
  add constraint "activities_overtime_grace_minutes_check"
    check (((overtime_grace_minutes >= 0) AND (overtime_grace_minutes <= 240)));

comment on column "public"."activities"."overtime_grace_minutes" is 'Overtime allowed free past a single session''s booked end (0–240) when it ends on this type: ended within it, the session is billed to its booked end; past it, the whole actual time. 0 = every overtime minute is billed. Part of the pricing snapshot; applied by _pr_session_bill and SegmentBilling.';
