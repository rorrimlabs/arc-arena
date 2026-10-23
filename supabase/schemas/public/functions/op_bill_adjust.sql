-- op_bill_adjust — sync op 'bill.adjust': set a closed bill's total and make what was collected
--   match it, audited.
--
-- Permission: money (an owner passes). Floor staff cannot change a closed bill.
-- Payload: scope ('single' default | 'group'), parent_id (session or group id),
--   billed_amount_paise (the new total: whole paise, 0 or more), reason (required: 1–500
--   characters after trimming), method (cash | upi | card | other: how the difference was paid
--   or given back; needed when collected differs from the new total), payment_id? (id of that
--   row; generated when absent).
-- Checks / errors: forbidden; reason_required; reason_too_long; invalid_total (missing or
--   negative); invalid_method; not_found (hint session / group); not_ended (still running);
--   voided; waived (a waived bill owes nothing); same_total (that total, already collected).
-- Writes, in one transaction: billed_amount_paise; when collected ≠ the new total, one ledger row
--   for the difference (a payment, or a refund carrying the reason; note 'Bill edited'); payment
--   status 'paid'; an audit_log row (action bill_adjust, before {billed_paise, paid_paise}, after
--   {billed_paise, paid_paise}). The priced charge rows and earlier payments are never touched.
--   Returns: {payment_status}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_bill_adjust (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now    timestamptz := statement_timestamp();
  v_group  boolean := coalesce(p->>'scope', 'single') = 'group';
  v_parent uuid := (p->>'parent_id')::uuid;
  v_new    bigint := (p->>'billed_amount_paise')::bigint;
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_method text := p->>'method';
  v_pay_id uuid := coalesce(nullif(p->>'payment_id', '')::uuid, gen_random_uuid());
  v_entity text := case when coalesce(p->>'scope', 'single') = 'group' then 'group_session'
                        else 'session' end;
  v_status text; v_pay text; v_old bigint; v_paid bigint; v_diff bigint;
begin
  perform _need(p_arena, 'money');
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say why the bill changes';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_new is null or v_new < 0 then
    raise exception 'invalid_total' using hint = 'the new total in whole paise, 0 or more';
  end if;

  -- Lock the bill (as op_payment does), so payments on it queue behind the change.
  if v_group then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_old
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_old
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
  end if;
  if v_status = 'voided' then raise exception 'voided' using hint = 'a voided bill has no total'; end if;
  if v_status <> 'completed' or v_old is null then
    raise exception 'not_ended' using hint = 'end the session first';
  end if;
  if v_pay = 'waived' then raise exception 'waived' using hint = 'a waived bill owes nothing'; end if;
  if v_new = v_old and v_paid = v_new then
    raise exception 'same_total' using hint = 'the bill is already that amount and paid';
  end if;

  -- What the bill says is what was collected: the difference goes in (or back) now.
  v_diff := v_new - v_paid;
  if v_diff <> 0 then
    if v_method is null or v_method not in ('cash', 'upi', 'card', 'other') then
      raise exception 'invalid_method' using hint = 'how the difference was paid or given back';
    end if;
    if v_group then
      insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
          reason, created_by, created_at)
        values (v_pay_id, p_arena, v_parent, v_diff, v_method, v_diff < 0, 'Bill edited',
          v_reason, auth.uid(), v_now);
    else
      insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
          created_by, created_at)
        values (v_pay_id, p_arena, v_parent, v_diff, v_method,
          case when v_diff < 0 then 'refund' else 'payment' end, 'Bill edited',
          v_reason, auth.uid(), v_now);
    end if;
  end if;
  if v_group then
    update group_sessions set billed_amount_paise = v_new, payment_status = 'paid', updated_at = v_now
      where id = v_parent;
  else
    update sessions set billed_amount_paise = v_new, payment_status = 'paid', updated_at = v_now
      where id = v_parent;
  end if;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
      created_by, created_at)
    values (p_arena, v_entity, v_parent, 'bill_adjust', v_reason,
      jsonb_build_object('billed_paise', v_old, 'paid_paise', v_paid),
      jsonb_build_object('billed_paise', v_new, 'paid_paise', v_new), auth.uid(), v_now);
  return jsonb_build_object('payment_status', 'paid');
end;
$function$;

comment on function public.op_bill_adjust(uuid, jsonb) is
  'Sync op bill.adjust: sets a closed bill''s total (money permission, reason required) and records the difference as a payment or refund so collected matches it; audited; charges untouched.';

grant execute on function "public"."op_bill_adjust"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_bill_adjust"(uuid, jsonb) from public;

revoke all on function "public".op_bill_adjust(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_bill_adjust(p_arena uuid, p jsonb) from authenticated;
