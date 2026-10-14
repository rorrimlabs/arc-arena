set local check_function_bodies = off;

create or replace function public._pr_rule (
  s     jsonb,
  p_act text,
  p_at  timestamp with time zone
)
  returns jsonb
  language sql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
  with t as (
    select _pr_ist_date(p_at) as d,
           floor(extract(epoch from (p_at at time zone 'UTC') + interval '330 minutes'
              - _pr_ist_date(p_at)::timestamp) / 60)::int as m
  )
  select r from t, jsonb_array_elements(coalesce(s->'rules', '[]'::jsonb)) r
   where r->'days' @> to_jsonb(extract(isodow from t.d)::int)
     and t.m >= (r->>'start_min')::int and t.m < (r->>'end_min')::int
     and (r->>'valid_from' is null or t.d >= (r->>'valid_from')::date)
     and (r->>'valid_until' is null or t.d <= (r->>'valid_until')::date)
     and case r->>'holiday_mode'
           when 'only' then coalesce(s->'holidays', '[]'::jsonb) ? t.d::text
           when 'skip' then not coalesce(s->'holidays', '[]'::jsonb) ? t.d::text
           else true end
     and (jsonb_array_length(coalesce(r->'activity_codes', '[]'::jsonb)) = 0
          or r->'activity_codes' ? p_act)
   order by (r->>'priority')::int, r->>'name' collate "C", r->>'id' collate "C"
   limit 1;
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
        'model', a->>'duration_model')
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
        'price_paise', price_paise)) from sync_v_rates where arena_id = p_arena), '[]'::jsonb),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('code', code,
        'duration_model', duration_model))
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
