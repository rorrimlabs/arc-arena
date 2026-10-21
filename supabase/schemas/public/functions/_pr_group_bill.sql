-- _pr_group_bill(p_group, p_open_end) — the server's bill for a group session.
--
-- Port of GroupBilling.bill (domain/services/group_billing.dart) on the group's frozen snapshot.
-- Default (per_system): every station is swept with _pr_sweep. shared_controller_pool: the purchased
-- controllers are quoted once over [started_at, p_open_end] with the first controller assignment's
-- activity, plus a sweep of assignments without controllers. Returns {subtotal, total (cash-rounded),
-- keys (sorted), by_activity {code: subtotal}}. Used by op_group_end (bill and charge rows) and op_group_extend (subtotal delta).
-- Server-only: not executable by anon/authenticated.
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

comment on function public._pr_group_bill(uuid, timestamp with time zone) is 'Pricing: server-side bill of a group session (per-system sweeps or a shared controller pool); port of GroupBilling.bill.';

grant execute
  on function "public"."_pr_group_bill"(uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_group_bill"(uuid, timestamp with time zone) from public;

revoke all on function "public"._pr_group_bill(p_group uuid, p_open_end timestamp with time zone) from anon;

revoke all on function "public"._pr_group_bill(p_group uuid, p_open_end timestamp with time zone) from authenticated;
