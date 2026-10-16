-- _pr_session_bill(p_session, p_open_end) — the server's bill for a single session.
--
-- Port of SegmentBilling.bill (domain/services/segment_billing.dart): quotes every segment in idx
-- order on the session's frozen pricing_snapshot (an open segment up to p_open_end) and sums the
-- quote subtotals; a segment with no rate contributes nothing.
-- Overtime grace (port of overtimeBillUntil): the grace is the snapshot's overtime_grace_minutes
-- of the type the session ends on (its last segment). When the session's last moment
-- (p_open_end, or its last segment end) is past scheduled_end_at by no more than that, every
-- segment is billed only up to scheduled_end_at (a segment starting at or after it bills
-- nothing); past the grace, or with no grace, the whole actual time is billed. Returns {subtotal, total (cash-rounded
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

comment on function public._pr_session_bill(uuid, timestamp with time zone) is 'Pricing: server-side bill of a single session over all its segments on its frozen snapshot; port of SegmentBilling.bill.';

grant execute
  on function "public"."_pr_session_bill"(uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_pr_session_bill"(uuid, timestamp with time zone) from public;

revoke all on function "public"._pr_session_bill(p_session uuid, p_open_end timestamp with time zone) from anon;

revoke all on function "public"._pr_session_bill(p_session uuid, p_open_end timestamp with time zone) from authenticated;
