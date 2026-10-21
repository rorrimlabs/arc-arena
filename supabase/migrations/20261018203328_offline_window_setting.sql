set local check_function_bodies = off;

drop function "public"."_client_time"(timestamp with time zone, text);

create or replace function public._client_time (
  p_arena uuid,
  p_at    timestamp with time zone,
  p_field text
)
  returns void
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
declare v_hours int;
begin
  if p_at > statement_timestamp() + interval '2 minutes' then
    raise exception 'time_in_future' using hint = p_field || ' is after the server''s time';
  end if;
  select coalesce((json->>'max_offline_hours')::int, 24) into v_hours
    from settings where arena_id = p_arena and key = 'offline_rules';
  v_hours := coalesce(v_hours, 24);
  if p_at < statement_timestamp() - make_interval(hours => v_hours) then
    raise exception 'time_too_old' using hint = p_field || ' is more than ' || v_hours || ' hours old';
  end if;
end;
$function$;

create or replace function public._offline_rules (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare v numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k where k <> 'max_offline_hours')
     or jsonb_typeof(p->'max_offline_hours') is distinct from 'number' then
    raise exception 'invalid_offline_rules' using hint = 'an object of max_offline_hours';
  end if;
  v := (p->>'max_offline_hours')::numeric;
  if v % 1 <> 0 or v < 1 or v > 720 then
    raise exception 'invalid_offline_rules' using hint = 'max_offline_hours: 1–720';
  end if;
  return jsonb_build_object('max_offline_hours', v::int);
end;
$function$;

create or replace function public.op_group_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  a jsonb := p->'assignment';
  v_player int := (p->'assignment'->>'player_number')::int;
  v_idx int; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  perform _group_active(p_arena, v_group);
  if exists (select 1 from group_assignments
              where group_id = v_group and player_number = v_player and ended_at is null) then
    raise exception 'player_busy';
  end if;
  perform _group_lock(p_arena, jsonb_build_array(a));
  -- Next index in this player's assignment history (a re-added player continues it).
  select coalesce(max(idx), -1) + 1 into v_idx from group_assignments
    where group_id = v_group and player_number = v_player;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx, null);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
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
  perform _client_time(p_arena, v_started, 'started_at');
  if jsonb_array_length(coalesce(p->'assignments', '[]'::jsonb)) = 0 then
    raise exception 'no_assignments';
  end if;
  -- Every target station and borrowed-pad origin, then the pads, in uuid order.
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
  v_bill jsonb; v_keys text[]; v_disc bigint := 0; v_total bigint; pol jsonb;
begin
  perform _need(p_arena, 'bill');
  perform _client_time(p_arena, v_ended, 'ended_at');
  if v_waive then
    perform _need(p_arena, 'discount');
    if nullif(btrim(coalesce(p->>'waive_reason', '')), '') is null then
      raise exception 'waive_reason_required';
    end if;
  end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
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
  -- Payments may already have been taken against the running bill.
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now,
      ended_recorded_at = v_now
    where id = v_group;
  -- A waive writes off what was not paid: audited with the amount and the staff reason
  -- (waive_reason, required: waive_reason_required).
  if v_waive then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after,
        created_by, created_at)
      values (p_arena, 'group_session', v_group, 'waive',
        nullif(btrim(coalesce(p->>'waive_reason', '')), ''),
        jsonb_build_object('billed_paise', v_billed, 'paid_paise', v_paid),
        jsonb_build_object('written_off_paise', greatest(coalesce(v_billed, 0) - v_paid, 0)),
        auth.uid(), v_now);
  end if;

  -- Server-side pricing (0013): re-price the bill from the stored assignments
  -- and refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  v_bill := _pr_group_bill(v_group, v_ended);
  v_total := (v_bill->>'total')::bigint;
  -- A discount (preset, coupon or manual) comes off the subtotal before cash rounding.
  if jsonb_typeof(p->'discount') = 'object' then
    if v_waive then raise exception 'invalid_discount' using hint = 'a waived bill takes no discount'; end if;
    v_disc := _discount_apply(p_arena, p->'discount', v_bill, v_ended,
      null, v_group);
    select _pr_policy(pricing_snapshot) into pol from group_sessions where id = v_group;
    v_total := _pr_money((v_bill->>'subtotal')::bigint - v_disc, (pol->>'money_rounding_paise')::int,
      pol->>'money_rounding_dir');
  end if;
  if v_total is distinct from v_billed then
    perform _price_mismatch('bill', v_total, v_billed);
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

create or replace function public.op_group_end_player (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_open uuid; v_start timestamptz;
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  perform _group_active(p_arena, v_group);
  select id, started_at into v_open, v_start from group_assignments
   where group_id = v_group and player_number = (p->>'player_number')::int and ended_at is null
   for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_group_switch (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_group uuid := (p->>'group_id')::uuid;
  v_at timestamptz := (p->>'at')::timestamptz;
  v_player int := (p->>'player_number')::int;
  a jsonb := p->'assignment';
  v_open uuid; v_open_res uuid; v_start timestamptz; v_idx int; v_label text; v_skipped int;
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  perform _group_active(p_arena, v_group);
  select id, resource_id, started_at, idx, player_label
    into v_open, v_open_res, v_start, v_idx, v_label
    from group_assignments
   where group_id = v_group and player_number = v_player and ended_at is null for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if v_open is distinct from nullif(p->>'expected_assignment_id','')::uuid then
    raise exception 'stale' using hint = 'the player was moved on another device';
  end if;
  if v_at < v_start then raise exception 'invalid_time'; end if;
  -- Also lock the station the player is leaving.
  perform _group_lock(p_arena, jsonb_build_array(a), array[v_open_res]);
  -- The player keeps their label across a switch (as on the device).
  a := a || jsonb_build_object('player_number', v_player, 'player_label', v_label);
  update group_assignments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where assignment_id = v_open and ended_at is null;
  v_skipped := _group_place(p_arena, v_group, a, v_at, v_idx + 1, v_player);
  update group_sessions set updated_at = statement_timestamp() where id = v_group;
  return jsonb_build_object('assignment_id', a->>'id', 'adjusted', v_skipped > 0);
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
begin
  perform _need(p_arena, 'bill');
  perform _client_time(p_arena, v_ended, 'ended_at');
  if v_waive then
    perform _need(p_arena, 'discount');
    if nullif(btrim(coalesce(p->>'waive_reason', '')), '') is null then
      raise exception 'waive_reason_required';
    end if;
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

  -- Server-side pricing (0013): re-price the bill from the stored segments and
  -- refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from session_segments where session_id = v_session and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before the current segment started';
  end if;
  v_bill := _pr_session_bill(v_session, v_ended);
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

create or replace function public.op_session_reconfigure (
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
  v_at timestamptz := (p->>'at')::timestamptz;
  v_resource uuid := (p->>'resource_id')::uuid;
  v_game uuid := nullif(p->>'game_id','')::uuid;
  v_act text := p->>'activity_code';
  v_cc int := nullif(p->>'controller_count','')::int;
  v_new uuid := (p->>'new_segment_id')::uuid;
  v_borrow uuid[] := _pad_ids(p->'moves');
  v_pads uuid[] := _pad_ids(p->'allocations');
  v_status text; v_open uuid; v_open_res uuid; v_open_start timestamptz; v_idx int; v_open_cc int;
  v_skipped int;
  v_origins uuid[];
begin
  perform _need(p_arena, 'start');
  perform _client_time(p_arena, v_at, 'at');
  select status into v_status from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  select id, resource_id, started_at, idx, controller_count
    into v_open, v_open_res, v_open_start, v_idx, v_open_cc
    from session_segments where session_id = v_session and ended_at is null;
  if not found then raise exception 'no_open_segment'; end if;
  if v_open is distinct from nullif(p->>'expected_segment_id','')::uuid then
    raise exception 'stale' using hint = 'the session was changed on another device';
  end if;
  if v_at < v_open_start then raise exception 'invalid_time'; end if;

  v_origins := _pad_origins(p_arena, v_borrow);
  perform _lock_resources(p_arena, array[v_resource, v_open_res] || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  if not (_pad_origins(p_arena, v_borrow) <@ (array[v_resource, v_open_res] || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;

  if v_resource <> v_open_res then
    perform _station_usable(p_arena, v_resource);
    perform _station_free_for_single(v_resource);
  end if;
  perform _game_playable(v_game, v_resource);
  perform _single_supply(p_arena, v_resource, v_act, v_game,
    coalesce(array_length(v_pads, 1), 0), v_cc, v_open_res, v_open_cc);
  perform _seg_priced(p_arena, v_resource,
    (select pricing_snapshot from sessions where id = v_session), v_act, v_cc);

  update session_segments set ended_at = v_at where id = v_open;
  update controller_allocations set ended_at = v_at where segment_id = v_open and ended_at is null;
  insert into session_segments(id, arena_id, session_id, idx, resource_id, activity_code,
      game_id, controller_count, started_at, created_at)
    values (v_new, p_arena, v_session, v_idx + 1, v_resource, v_act, v_game, v_cc, v_at, v_now);
  v_skipped := _pad_borrow(p_arena, p->'moves', v_resource, 's:' || v_session::text, v_at);
  perform _pad_allocate(p_arena, p->'allocations', 'single', v_session, null, v_new, null,
    null, null, v_resource, v_act, v_game, v_at);
  update sessions set updated_at = v_now where id = v_session;
  if v_game is not null then
    update games set last_played_at = v_at, updated_at = v_now where id = v_game and arena_id = p_arena;
  end if;
  return jsonb_build_object('segment_id', v_new, 'adjusted', v_skipped > 0);
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
  perform _client_time(p_arena, v_started, 'started_at');
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
  perform _seg_priced(p_arena, v_resource, p->'pricing_snapshot', v_act, v_cc);

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

create or replace function public.op_settings_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_json jsonb := p->'json';
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours', 'floor_options', 'discount_options', 'venue_profile',
                         'attendance', 'work_hours', 'leave_rules', 'offline_rules') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  elsif p->>'key' = 'discount_options' then
    v_json := _discount_options(p->'json');
  elsif p->>'key' = 'venue_profile' then
    v_json := _venue_profile(p->'json');
  elsif p->>'key' = 'attendance' then
    v_json := _attendance_settings(p->'json');
  elsif p->>'key' = 'work_hours' then
    v_json := _work_hours_settings(p->'json');
  elsif p->>'key' = 'leave_rules' then
    v_json := _leave_rules_settings(p->'json');
  elsif p->>'key' = 'offline_rules' then
    v_json := _offline_rules(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

comment on function "public"."_client_time"(uuid, timestamp
  with time zone, text) is 'Internal: raise time_in_future (> now + 2 min) or time_too_old (older than the arena''s offline window, default 24 h) for a device-stamped billing instant.';

comment on function "public"."_offline_rules"(jsonb) is 'Internal: validate settings key offline_rules ({max_offline_hours: 1–720}); raises invalid_offline_rules.';

revoke all on function "public"."_client_time"(uuid, timestamp with time zone, text) from public;

grant execute
  on function "public"."_client_time"(uuid, timestamp with time zone, text)
  to "postgres", "service_role";

revoke all on function "public"."_offline_rules"(jsonb) from public;

grant execute on function "public"."_offline_rules"(jsonb) to "postgres", "service_role";
