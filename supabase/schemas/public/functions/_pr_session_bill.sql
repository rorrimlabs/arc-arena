-- _pr_session_bill(p_session, p_open_end) — the server's bill for a single session.
--
-- Port of SegmentBilling.bill (domain/services/segment_billing.dart): quotes every segment in idx
-- order on the session's frozen pricing_snapshot (an open segment up to p_open_end) and sums the
-- quote subtotals; a segment with no rate contributes nothing. Returns {subtotal, total (cash-rounded
-- once), keys (sorted), by_activity {code: subtotal} (the base of a type-scoped discount)}. Used by op_session_end, which raises price_mismatch on any difference.
-- Server-only: not executable by anon/authenticated.
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

comment on function public._pr_session_bill(uuid, timestamp with time zone) is 'Pricing: server-side bill of a single session over all its segments on its frozen snapshot; port of SegmentBilling.bill.';

grant execute
  on function "public"."_pr_session_bill"(uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_session_bill"(uuid, timestamp with time zone) from public;

revoke all on function "public"._pr_session_bill(p_session uuid, p_open_end timestamp with time zone) from anon;

revoke all on function "public"._pr_session_bill(p_session uuid, p_open_end timestamp with time zone) from authenticated;
