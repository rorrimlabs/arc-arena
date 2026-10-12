-- _pricing_canon(s) — reduce a pricing snapshot to what pricing depends on, in a fixed order.
--
-- Builds {rates, activities, policy, hours, holidays, closed_days}: rates and activities sorted,
-- policy filled from _pr_policy defaults, open / happy hours for ISO days 1-7 (non-object -> null),
-- holidays and closed_days de-duplicated and sorted. Card name and list order are dropped.
-- Used by _assert_snapshot and by _sync_apply (records a replaced list in pricing_catalog_history).
-- Server-only: not executable by anon/authenticated.
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
        'model', a->>'duration_model', 'happy', (a->>'happy_eligible')::boolean)
        order by a->>'code', a->>'duration_model')
        from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a), '[]'::jsonb),
    'policy', _pr_policy(s),
    'hours', (select jsonb_object_agg(kind, (select jsonb_object_agg(d::text,
        case when jsonb_typeof(s->'hours'->kind->(d::text)) = 'object'
             then jsonb_build_object('start', (s->'hours'->kind->(d::text)->>'start')::int,
                                     'end', (s->'hours'->kind->(d::text)->>'end')::int)
             else 'null'::jsonb end) from generate_series(1, 7) d))
        from unnest(array['open', 'happy']) kind),
    'holidays', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'holidays', '[]'::jsonb)) x), '[]'::jsonb),
    'closed_days', coalesce((select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(coalesce(s->'closed_days', '[]'::jsonb)) x), '[]'::jsonb));
$function$;

comment on function public._pricing_canon(jsonb) is 'Pricing: canonical form of a snapshot (sorted, defaults filled, card name dropped) for equality checks.';

grant execute on function "public"."_pricing_canon"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_pricing_canon"(jsonb) from public;

revoke all on function "public"._pricing_canon(s jsonb) from anon;

revoke all on function "public"._pricing_canon(s jsonb) from authenticated;
