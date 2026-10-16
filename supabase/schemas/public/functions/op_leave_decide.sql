-- op_leave_decide — sync op 'leave.decide': approve or reject a request, or its cancellation
--
-- Permission: leave_approve; never your own request unless role owner (own_record).
-- Payload: id, approve (bool), paid_days (optional, 0–days in halves), note (optional).
--   pending + approve → approved: paid_days (default: min(days, the available balance in the
--     leave year of from_date, rounded down to a half day)) and lop_days = days − paid_days;
--     day_split pins them to dates (_leave_working_days, paid filling the earliest days).
--   pending + reject → rejected.
--   cancel_pending + approve → cancelled (the leave no longer counts); + reject → approved.
-- Checks / errors: forbidden; not_found; own_record; invalid_state; invalid_paid_days;
--   period_finalised.
-- Writes: leave_requests; audit_log (entity leave_request, action approve / reject /
--   cancel_approved / cancel_rejected, after {paid_days, lop_days}). Returns: {status,
--   paid_days, lop_days}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_leave_decide (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_r       leave_requests;
  v_approve boolean := (p->>'approve')::boolean;
  v_note    text := nullif(btrim(coalesce(p->>'note', '')), '');
  v_paid    numeric;
  v_left    numeric;
  v_split   jsonb;
  v_status  text;
  v_action  text;
begin
  perform _need(p_arena, 'leave_approve');
  if v_approve is null then raise exception 'invalid_payload' using hint = 'approve'; end if;
  select * into v_r from leave_requests
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'leave request'; end if;
  perform _own_record(p_arena, v_r.staff_id);
  if v_r.status not in ('pending', 'cancel_pending') then raise exception 'invalid_state'; end if;
  if _period_finalised(p_arena, v_r.from_date, v_r.to_date) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;

  if v_r.status = 'pending' and v_approve then
    if p ? 'paid_days' and p->'paid_days' <> 'null'::jsonb then
      v_paid := (p->>'paid_days')::numeric;
      if v_paid < 0 or v_paid > v_r.days or (v_paid * 2) % 1 <> 0 then
        raise exception 'invalid_paid_days' using hint = '0 to ' || v_r.days || ', in halves';
      end if;
    else
      v_left := greatest(0, (_leave_balance(v_r.staff_id, v_r.from_date)->>'balance')::numeric);
      v_paid := least(v_r.days, floor(v_left * 2) / 2);
    end if;
    -- Pin the paid days to the earliest working days, the rest is LOP.
    select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'units', d.units,
             'paid_units', greatest(0, least(d.units, v_paid - d.before))) order by d.day), '[]'::jsonb)
      into v_split
      from (select w.day, w.units,
                   coalesce(sum(w.units) over (order by w.day rows between unbounded preceding and 1 preceding), 0) as before
              from _leave_working_days(v_r.staff_id, v_r.from_date, v_r.to_date, v_r.half_day) w) d;
    v_status := 'approved'; v_action := 'approve';
    update leave_requests set status = v_status, paid_days = v_paid, lop_days = days - v_paid,
        day_split = v_split, decided_by = auth.uid(), decided_at = statement_timestamp(),
        decision_note = v_note
     where id = v_r.id;
  elsif v_r.status = 'pending' then
    v_status := 'rejected'; v_action := 'reject';
    update leave_requests set status = v_status, decided_by = auth.uid(),
        decided_at = statement_timestamp(), decision_note = v_note
     where id = v_r.id;
  elsif v_approve then
    v_status := 'cancelled'; v_action := 'cancel_approved';
    update leave_requests set status = v_status, paid_days = null, lop_days = null,
        decided_by = auth.uid(), decided_at = statement_timestamp(), decision_note = v_note
     where id = v_r.id;
  else
    v_status := 'approved'; v_action := 'cancel_rejected';
    update leave_requests set status = v_status, decided_by = auth.uid(),
        decided_at = statement_timestamp(), decision_note = v_note
     where id = v_r.id;
  end if;
  select * into v_r from leave_requests where id = v_r.id;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
    values (p_arena, 'leave_request', v_r.id, v_action, v_note,
            jsonb_build_object('paid_days', v_r.paid_days, 'lop_days', v_r.lop_days),
            auth.uid(), statement_timestamp());
  return jsonb_build_object('status', v_status, 'paid_days', v_r.paid_days, 'lop_days', v_r.lop_days);
end;
$function$;

comment on function public.op_leave_decide(uuid, jsonb) is 'Sync op leave.decide: approve (with the paid / LOP split pinned to dates) or reject a leave request, or its cancellation.';

grant execute on function "public"."op_leave_decide"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_decide"(uuid, jsonb) from public;

revoke all on function "public"."op_leave_decide"(uuid, jsonb) from anon;

revoke all on function "public"."op_leave_decide"(uuid, jsonb) from authenticated;
