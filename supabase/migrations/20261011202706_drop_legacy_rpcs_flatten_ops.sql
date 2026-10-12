set local check_function_bodies = off;

drop function "public"."_op_controller_move_v1"(uuid, jsonb);

drop function "public"."_op_group_create_v1"(uuid, jsonb);

drop function "public"."_op_group_end_v1"(uuid, jsonb);

drop function "public"."_op_group_extend_v1"(uuid, jsonb);

drop function "public"."_op_payment_v1"(uuid, jsonb);

drop function "public"."_op_resource_upsert_v1"(uuid, jsonb);

drop function "public"."_op_session_end_v1"(uuid, jsonb);

drop function "public"."_op_session_extend_v1"(uuid, jsonb);

drop function "public"."_op_session_start_v1"(uuid, jsonb);

drop function "public"."_op_staff_update_v1"(uuid, jsonb);

drop function "public"."_sync_apply_v1"(uuid, text, jsonb);

drop function "public"."add_assignment"(uuid, timestamp
  with time zone, integer, text, uuid, text, uuid, integer, uuid, text);

drop function "public"."allocate_controllers"(uuid, text, uuid[], uuid, text, timestamp
  with time zone, uuid, uuid, uuid, uuid, integer, text, uuid, text, boolean, text);

drop function "public"."assert_group_colocation_ok"(uuid, uuid, uuid, text, uuid, integer, uuid);

drop function "public"."borrow_controllers"(uuid, uuid[], uuid, text, timestamp with time zone);

drop function "public"."claim_arena"(uuid, text);

drop function "public"."create_arena"(text, text);

drop function "public"."create_group"(uuid, jsonb, text);

drop function "public"."end_assignment"(uuid, integer, timestamp with time zone);

drop function "public"."end_group"(uuid, timestamp with time zone, jsonb, bigint, boolean);

drop function "public"."end_session"(uuid, timestamp with time zone, jsonb, bigint, boolean);

drop function "public"."extend_group"(uuid, integer, timestamp
  with time zone, bigint, text, uuid, text);

drop function "public"."extend_session"(uuid, integer, timestamp
  with time zone, bigint, text, uuid, text);

drop function "public"."move_controller"(uuid, uuid, text, uuid, text, timestamp with time zone);

drop function "public"."reconfigure_session"(uuid, timestamp
  with time zone, uuid, text, uuid, integer, uuid, text);

drop function "public"."record_group_payment"(uuid, bigint, text, boolean, text, text, text, uuid);

drop function "public"."record_payment"(uuid, bigint, text, text, text, text, text, uuid);

drop function "public"."release_controllers"(uuid, uuid[], timestamp with time zone);

drop function "public"."start_session"(uuid, jsonb, text);

drop function "public"."switch_assignment"(uuid, timestamp
  with time zone, integer, uuid, text, uuid, integer, uuid, text);

drop function "public"."void_group"(uuid, text);

drop function "public"."void_session"(uuid, text);

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
                'holiday.upsert', 'holiday.delete') then
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
      when 'customer.create'      then op_customer_create(p_arena, p)
      when 'customer.update'      then op_customer_update(p_arena, p)
      when 'booking.create'       then op_booking_create(p_arena, p)
      when 'booking.update'       then op_booking_update(p_arena, p)
      when 'booking.set_status'   then op_booking_set_status(p_arena, p)
      when 'game.upsert'          then op_game_upsert(p_arena, p)
      when 'game.set_active'      then op_game_set_active(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
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

create or replace function public.op_controller_move (
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
  v_cid uuid := (p->>'controller_id')::uuid;
  v_kind text := p->>'kind';
  v_to uuid := nullif(p->>'to_resource_id','')::uuid;
  v_loc uuid; v_home uuid;
begin
  if v_kind is null or v_kind not in ('loan','permanent','returnHome') then
    raise exception 'move_kind_invalid';
  end if;
  -- Carrying a pad (loan / return) is floor work: it needs start or settings
  -- (0016). Re-homing it (permanent) changes the inventory: settings.
  if v_kind in ('loan', 'returnHome')
     and not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'settings')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or settings';
  end if;
  if v_kind = 'permanent' then perform _need(p_arena, 'settings'); end if;
  select current_resource_id, home_resource_id into v_loc, v_home
    from controllers where id = v_cid and arena_id = p_arena;
  if not found then raise exception 'controller_missing'; end if;
  if v_kind = 'returnHome' then v_to := v_home; end if;
  if not exists (select 1 from resources where id = v_to and arena_id = p_arena) then
    raise exception 'resource_missing';
  end if;
  perform _lock_resources(p_arena, array[v_loc, v_to]);
  perform _lock_pads(p_arena, array[v_cid]);
  select current_resource_id, home_resource_id into v_loc, v_home from controllers where id = v_cid;
  if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  update controllers
     set current_resource_id = v_to,
         home_resource_id = case when v_kind = 'permanent' then v_to else home_resource_id end,
         loan_return_to   = case when v_kind = 'loan' then v_home::text end,
         loan_session_ref = case when v_kind = 'loan' then p->>'session_ref' end,
         updated_at = v_now
   where id = v_cid;
  if v_to = v_loc then
    -- Nothing physically moved (e.g. a return already done on another device):
    -- the device's history row is not mirrored, so it should refetch.
    return jsonb_build_object('moved', false, 'adjusted', nullif(p->>'move_id','') is not null);
  end if;
  insert into controller_moves(id, arena_id, controller_id, from_resource_id, to_resource_id, kind,
      session_ref, moved_at, created_by, created_at)
    values (coalesce(nullif(p->>'move_id','')::uuid, gen_random_uuid()), p_arena, v_cid, v_loc,
      v_to, v_kind, case when v_kind = 'loan' then p->>'session_ref' end,
      coalesce((p->>'at')::timestamptz, v_now), auth.uid(), v_now);
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$function$;

create or replace function public.op_group_create (
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
  v_group uuid := (p->>'id')::uuid;
  v_started timestamptz := (p->>'started_at')::timestamptz;
  v_skipped int := 0; a jsonb;
begin
  perform _need(p_arena, 'start');
  if jsonb_array_length(coalesce(p->'assignments', '[]'::jsonb)) = 0 then
    raise exception 'no_assignments';
  end if;
  perform _group_lock(p_arena, p->'assignments');
  insert into group_sessions(id, arena_id, primary_customer_id, player_count,
      purchased_controller_count, status, payment_status, started_at, scheduled_end_at,
      pricing_snapshot, policy_snapshot, billing_mode, created_by, created_at, updated_at)
    values (v_group, p_arena, (p->>'primary_customer_id')::uuid, (p->>'player_count')::int,
      coalesce((p->>'purchased_controller_count')::int, 0), 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      p->'pricing_snapshot'->'policy', coalesce(nullif(p->>'billing_mode',''), 'per_system'),
      auth.uid(), v_now, v_now);
  -- Device order: each check sees the players placed before it (as on device).
  for a in select value from jsonb_array_elements(p->'assignments') loop
    v_skipped := v_skipped + _group_place(p_arena, v_group, a, v_started,
      coalesce((a->>'idx')::int, 0), null);
  end loop;
  update customers set last_visit_at = v_started, updated_at = v_now
    where id = (p->>'primary_customer_id')::uuid and arena_id = p_arena;

  -- The frozen price list must be this arena's current one, and the group's
  -- billing mode must be the one that price list prescribes (0013).
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  if coalesce(nullif(p->>'billing_mode', ''), 'per_system')
     <> _pr_policy(p->'pricing_snapshot')->>'group_billing_mode' then
    raise exception 'pricing_snapshot_mismatch'
      using hint = 'billing_mode differs from the price list''s group billing mode';
  end if;
  return jsonb_build_object('group_id', v_group, 'adjusted', v_skipped > 0);
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
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end <> (p->>'expected_scheduled_end_at')::timestamptz then
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
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_group;

  -- Server-side pricing (0013): re-price the bill from the stored assignments
  -- and refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  v_bill := _pr_group_bill(v_group, v_ended);
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
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

create or replace function public.op_group_extend (
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
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_end timestamptz; v_added bigint;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  if v_end <> v_old then
    raise exception 'stale' using hint = 'the group was extended on another device';
  end if;
  insert into group_extensions(id, arena_id, group_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_group, (p->>'added_minutes')::int, v_end,
      v_new, coalesce((p->>'added_amount_paise')::bigint, 0), p->>'reason', auth.uid(), v_now);
  update group_sessions set scheduled_end_at = v_new, updated_at = v_now where id = v_group;

  -- Server-side pricing (0013): the extension costs the difference between the
  -- group's subtotal at the new end and at the old end.
  v_added := (_pr_group_bill(v_group, v_new)->>'subtotal')::bigint
           - (_pr_group_bill(v_group, v_old)->>'subtotal')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_payment (
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
  v_scope  text    := coalesce(p->>'scope', 'single');
  v_parent uuid    := (p->>'parent_id')::uuid;
  v_refund boolean := coalesce((p->>'is_refund')::boolean, false);
  v_amount bigint  := (p->>'amount_paise')::bigint;
  v_status text; v_pay text; v_billed bigint; v_paid bigint;
begin
  -- Permission refusals keep their own code, ahead of any balance check.
  perform _need(p_arena, 'bill');
  if v_refund then perform _need(p_arena, 'discount'); end if;

  -- Balance (0016). Lock the parent so two pushes for the same bill queue here
  -- and the second sees the first one's payment.
  if v_scope = 'group' then
    select payment_status, billed_amount_paise into v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from group_payments where group_id = v_parent;
    end if;
  else
    select payment_status, billed_amount_paise into v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if found then
      select coalesce(sum(amount_paise), 0) into v_paid
        from payments where session_id = v_parent;
    end if;
  end if;

  if v_paid is not null and coalesce(v_amount, 0) <> 0 then
    if v_refund then
      if v_paid - abs(v_amount) < 0 then
        raise exception 'refund_exceeds_paid'
          using hint = 'only ' || _rupees(greatest(v_paid, 0)) || ' was collected';
      end if;
    elsif v_amount > 0 and v_billed is not null and v_pay <> 'waived'
          and v_paid + v_amount > v_billed then
      raise exception 'overpayment'
        using hint = case when v_billed - v_paid <= 0 then 'this bill is already paid'
                          else 'only ' || _rupees(v_billed - v_paid) || ' is due' end;
    end if;
  end if;

  -- Amount, sign, refund reason and method.
  if v_amount is null or v_amount = 0 then raise exception 'amount_zero'; end if;
  if v_refund then
    if coalesce(btrim(p->>'reason'), '') = '' then raise exception 'refund_reason_required'; end if;
    v_amount := -abs(v_amount);
  elsif v_amount < 0 then
    raise exception 'amount_negative';
  end if;
  if (p->>'method') not in ('cash','upi','card','other') then raise exception 'invalid_method'; end if;

  -- Record the payment and recompute the parent's payment status (a waived bill
  -- keeps 'waived').
  if v_scope = 'group' then
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from group_sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'group'; end if;
    if v_status = 'voided' then raise exception 'voided'; end if;
    insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund, note,
        reason, created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method', v_refund,
        p->>'note', p->>'reason', auth.uid(), v_now);
    if v_pay <> 'waived' then
      select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update group_sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  else
    select status, payment_status, billed_amount_paise into v_status, v_pay, v_billed
      from sessions where id = v_parent and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'session'; end if;
    if v_status = 'voided' then raise exception 'voided'; end if;
    insert into payments(id, arena_id, session_id, amount_paise, method, kind, note, reason,
        created_by, created_at)
      values ((p->>'payment_id')::uuid, p_arena, v_parent, v_amount, p->>'method',
        case when v_refund then 'refund' else 'payment' end, p->>'note', p->>'reason',
        auth.uid(), v_now);
    if v_pay <> 'waived' then
      select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = v_parent;
      v_pay := _payment_status(v_billed, v_paid);
      update sessions set payment_status = v_pay, updated_at = v_now where id = v_parent;
    end if;
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

create or replace function public.op_resource_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_code text;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never overwritten.
  if exists (select 1 from resources where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'resource';
  end if;
  insert into resources(id, arena_id, name, kind, status, sort_order)
    values (v_id, p_arena, p->>'name', p->>'kind', coalesce(p->>'status', 'available'),
      coalesce((p->>'sort_order')::int, 0))
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      status = excluded.status, sort_order = excluded.sort_order, updated_at = statement_timestamp()
    where resources.arena_id = p_arena;
  -- The station supports exactly the listed activities.
  delete from resource_activities ra using activities a
   where ra.resource_id = v_id and a.id = ra.activity_id
     and not (a.code = any(array(select jsonb_array_elements_text(coalesce(p->'activity_codes','[]'::jsonb)))));
  for v_code in select jsonb_array_elements_text(coalesce(p->'activity_codes', '[]'::jsonb)) loop
    insert into resource_activities(arena_id, resource_id, activity_id)
      values (p_arena, v_id, _activity_id(p_arena, v_code))
    on conflict (resource_id, activity_id) do nothing;
  end loop;
  return '{}'::jsonb;
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
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select coalesce(array_agg(id), '{}') into v_segs from session_segments where session_id = v_session;
  if not _same_ids(v_segs, _jsonb_uuids(p->'expected_segment_ids'))
     or v_end <> (p->>'expected_scheduled_end_at')::timestamptz then
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

  -- Server-side pricing (0013): re-price the bill from the stored segments and
  -- refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended);
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
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

create or replace function public.op_session_extend (
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
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_status text; v_end timestamptz;
  v_snap jsonb; v_start timestamptz; v_act text; v_cc int; q_old jsonb; q_new jsonb; v_added bigint;
begin
  perform _need(p_arena, 'start');
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  if v_end <> v_old then
    raise exception 'stale' using hint = 'the session was extended on another device';
  end if;
  insert into session_extensions(id, arena_id, session_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_session, (p->>'added_minutes')::int, v_end,
      v_new, coalesce((p->>'added_amount_paise')::bigint, 0), p->>'reason', auth.uid(), v_now);
  update sessions set scheduled_end_at = v_new, updated_at = v_now where id = v_session;

  -- Server-side pricing (0013): the extension costs the difference between the
  -- bill at the new end and at the old end, on the session's frozen price list.
  select pricing_snapshot, started_at into v_snap, v_start from sessions where id = v_session;
  select activity_code, controller_count into v_act, v_cc from session_segments
   where session_id = v_session order by (ended_at is null) desc, idx desc limit 1;
  q_old := _pr_quote(v_snap, v_act, v_cc, v_start, v_old);
  q_new := _pr_quote(v_snap, v_act, v_cc, v_start, v_new);
  if q_old is null or q_new is null then
    raise exception 'no_rate' using hint = 'the session''s price list has no rate for this extension';
  end if;
  v_added := (q_new->>'amount')::bigint - (q_old->>'amount')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return jsonb_build_object('new_end_at', p->>'new_end_at');
end;
$function$;

create or replace function public.op_session_start (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now      timestamptz := statement_timestamp();
  v_session  uuid := (p->>'id')::uuid;
  v_segment  uuid := (p->>'segment_id')::uuid;
  v_resource uuid := (p->>'resource_id')::uuid;
  v_game     uuid := nullif(p->>'game_id','')::uuid;
  v_started  timestamptz := (p->>'started_at')::timestamptz;
  v_customer uuid := (p->>'customer_id')::uuid;
  v_booking  uuid := nullif(p->>'booking_id','')::uuid;
  v_act      text := p->>'activity_code';
  v_cc       int  := nullif(p->>'controller_count','')::int;
  v_borrow   uuid[] := _pad_ids(p->'moves');
  v_pads     uuid[] := _pad_ids(p->'allocations');
  v_bstatus  text;
  v_skipped  int;
  v_origins  uuid[];
begin
  perform _need(p_arena, 'start');
  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, array[v_resource] || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  -- A pad that moved between the read and the lock sits at a station we do not
  -- hold: retry rather than check it unlocked.
  if not (_pad_origins(p_arena, v_borrow) <@ (array[v_resource] || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;

  perform _station_usable(p_arena, v_resource);
  perform _game_playable(v_game, v_resource);
  perform _single_supply(p_arena, v_resource, v_act, v_game,
    coalesce(array_length(v_pads, 1), 0), v_cc);
  perform _station_free_for_single(v_resource);

  if v_booking is not null then
    select status into v_bstatus from bookings
      where id = v_booking and arena_id = p_arena for update;
    if not found then raise exception 'booking_missing'; end if;
    if v_bstatus <> 'booked' then raise exception 'booking_not_open' using hint = v_bstatus; end if;
    update bookings set status = 'checked_in', updated_at = v_now where id = v_booking;
  end if;

  insert into sessions(id, arena_id, booking_id, customer_id, status, payment_status,
      started_at, scheduled_end_at, pricing_snapshot, policy_snapshot, request_id,
      created_by, created_at, updated_at)
    values (v_session, p_arena, v_booking, v_customer, 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      coalesce(p->'pricing_snapshot'->'policy', '{}'::jsonb), null, auth.uid(), v_now, v_now);
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
      game_id, controller_count, started_at, created_at)
    values (v_segment, p_arena, v_session, 0, v_resource, v_act, v_game, v_cc, v_started, v_now);

  v_skipped := _pad_borrow(p_arena, p->'moves', v_resource, 's:' || v_session::text, v_started);
  perform _pad_allocate(p_arena, p->'allocations', 'single', v_session, null, v_segment, null,
    null, null, v_resource, v_act, v_game, v_started);

  update customers set last_visit_at = v_started, updated_at = v_now
    where id = v_customer and arena_id = p_arena;
  if v_game is not null then
    update games set last_played_at = v_started, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;

  -- The price list the device froze into the session must be this arena's
  -- current one (0013); checked last so earlier errors keep their precedence.
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  return jsonb_build_object('session_id', v_session, 'adjusted', v_skipped > 0);
end;
$function$;

create or replace function public.op_staff_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_user   uuid    := (p->>'user_id')::uuid;
  v_perms  text[]  := array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb)));
  v_active boolean := coalesce((p->>'active')::boolean, true);
  v_role   text;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  perform _assert_known_perms(v_perms);
  select role into v_role from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
    end if;
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    v_adj := not (v_perms @> _known_perms()) or not v_active;
    v_perms := _known_perms();
    v_active := true;
  end if;
  update staff_profiles set name = p->>'name', perms = v_perms, active = v_active,
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then '{"adjusted": true}'::jsonb else '{}'::jsonb end;
end;
$function$;
