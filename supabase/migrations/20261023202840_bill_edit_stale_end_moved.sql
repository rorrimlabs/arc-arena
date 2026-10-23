set local check_function_bodies = off;

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
  v_by     uuid;
  v_money  boolean := private.app_has_perm(p_arena, 'money');
begin
  if not v_money then perform _need(p_arena, 'bill_edit'); end if;
  if v_reason is null then
    raise exception 'reason_required' using hint = 'say why the bill changes';
  end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long' using hint = 'at most 500 characters'; end if;
  if v_new is null or v_new < 0 then
    raise exception 'invalid_total' using hint = 'the new total in whole paise, 0 or more';
  end if;

  -- Lock the bill (as op_payment does), so payments on it queue behind the change.
  if v_group then
    select status, payment_status, billed_amount_paise, created_by into v_status, v_pay, v_old, v_by
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
  else
    select status, payment_status, billed_amount_paise, created_by into v_status, v_pay, v_old, v_by
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
  end if;
  if not v_money and v_by is distinct from auth.uid() then
    raise exception 'forbidden' using errcode = '42501', hint = 'not your bill';
  end if;
  if v_status = 'voided' then raise exception 'voided' using hint = 'a voided bill has no total'; end if;
  if v_status <> 'completed' or v_old is null then
    raise exception 'not_ended' using hint = 'end the session first';
  end if;
  if v_pay = 'waived' then raise exception 'waived' using hint = 'a waived bill owes nothing'; end if;
  -- The difference is settled against what the caller saw, never against a payment or edit
  -- that landed since (it would turn into a refund nobody gave, or refuse real money).
  if v_old is distinct from (p->>'expected_billed_paise')::bigint
     or v_paid is distinct from (p->>'expected_paid_paise')::bigint then
    raise exception 'stale' using hint = 'the bill changed since it was loaded: reload it';
  end if;
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
  v_moved boolean := jsonb_typeof(p->'end_moved') = 'object';
  v_from timestamptz := (p->'end_moved'->>'from')::timestamptz;
  v_end_reason text := nullif(btrim(coalesce(p->'end_moved'->>'reason', '')), '');
  v_from_bill bigint;
begin
  perform _need(p_arena, 'bill');
  perform _client_time(p_arena, v_ended, 'ended_at');
  if v_waive then
    perform _need(p_arena, 'discount');
    if nullif(btrim(coalesce(p->>'waive_reason', '')), '') is null then
      raise exception 'waive_reason_required';
    end if;
  end if;
  -- An end set earlier than when staff ended it lowers the bill: it needs a reason and is audited.
  if v_moved then
    if v_end_reason is null then
      raise exception 'end_reason_required' using hint = 'say why the end was moved earlier';
    end if;
    if length(v_end_reason) > 500 then
      raise exception 'reason_too_long' using hint = 'at most 500 characters';
    end if;
    if v_from is null or v_from <= v_ended then
      raise exception 'invalid_time' using hint = 'end_moved.from must be after ended_at';
    end if;
    perform _client_time(p_arena, v_from, 'end_moved.from');
  end if;
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select coalesce(array_agg(id), '{}') into v_segs from session_segments where session_id = v_session;
  if not _same_ids(v_segs, _jsonb_uuids(p->'expected_segment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;
  -- What the bill would have been at the original end (segments are still open here).
  if v_moved then
    v_from_bill := (_pr_session_bill(v_session, v_from,
      coalesce((p->>'charge_overtime')::boolean, false))->>'total')::bigint;
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
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now,
      ended_recorded_at = v_now
    where id = v_session;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason, required: waive_reason_required).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'session', v_session, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;
  if v_moved then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'session', v_session, 'end_moved', v_end_reason,
        jsonb_build_object('ended_at', v_from, 'billed_paise', v_from_bill),
        jsonb_build_object('ended_at', v_ended, 'billed_paise', v_billed),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored segments and
  -- refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended, coalesce((p->>'charge_overtime')::boolean, false));
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
  -- Below owner level a waive is capped like a manual discount.
  if v_waive then perform _waive_check(p_arena, v_billed, v_paid); end if;
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
