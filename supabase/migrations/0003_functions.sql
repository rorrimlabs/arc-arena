-- Critical server operations as RPCs (spec §32), single-session world.
--
-- DESIGN. The pure-Dart domain engine stays the single source of truth for
-- pricing and availability: the client computes the price/charges and passes
-- them in. Each RPC enforces the STRUCTURAL guarantees the client cannot:
--   * arena membership + role (SECURITY DEFINER bypasses RLS, so the function
--     body is the only gate — it must check auth.uid() membership itself),
--   * one open segment per resource (resource row FOR UPDATE + the trigger),
--   * idempotency: a repeated request_id returns the first result, never a
--     second row (works for at-least-once sync retries),
--   * append-only history + the money sign rule (payment_rules),
--   * one fixed statement_timestamp() per call for created_at/updated_at (no
--     double-now drift), and that timestamp survives the set_updated_at trigger.
-- Row ids are client-generated (Drift uses Uuid().v4()); the RPC uses the id in
-- the payload so the local row and the server row share identity for sync.

-- start_session ----------------------------------------------------------------
create or replace function start_session(
  p_arena       uuid,
  p_payload     jsonb,   -- id, segment_id, customer_id, booking_id, started_at,
                         -- scheduled_end_at, pricing_snapshot (policy nested),
                         -- resource_id, activity_code, game_id, controller_count
  p_request_id  text default null
) returns uuid as $$
declare
  v_now      timestamptz := statement_timestamp();
  v_session  uuid;
  v_segment  uuid;
  v_existing uuid;
  v_resource uuid;
  v_game     uuid;
  v_started  timestamptz;
  v_customer uuid;
  v_rstatus  text;
  v_gstatus  text;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'Not a member of this arena.';
  end if;

  -- Idempotency: a repeated request_id returns the first session, no new work.
  if p_request_id is not null then
    select id into v_existing from sessions
      where arena_id = p_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;

  v_session  := coalesce(nullif(p_payload->>'id',''), gen_random_uuid()::text)::uuid;
  v_segment  := coalesce(nullif(p_payload->>'segment_id',''), gen_random_uuid()::text)::uuid;
  v_resource := (p_payload->>'resource_id')::uuid;
  v_game     := nullif(p_payload->>'game_id','')::uuid;
  v_started  := (p_payload->>'started_at')::timestamptz;
  v_customer := (p_payload->>'customer_id')::uuid;

  -- Serialise claims on this resource against a racing start.
  perform 1 from resources where id = v_resource and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'resource'; end if;
  select status into v_rstatus from resources where id = v_resource;
  if v_rstatus <> 'available' then
    raise exception 'resource_unusable' using hint = v_rstatus;
  end if;

  -- The game must be playable on this resource (absent row = not installed).
  if v_game is not null then
    select status into v_gstatus from game_resources
      where game_id = v_game and resource_id = v_resource;
    if not found or v_gstatus <> 'playable' then
      raise exception 'not_playable' using hint = coalesce(v_gstatus, 'not_installed');
    end if;
  end if;

  insert into sessions(id, arena_id, booking_id, customer_id, status,
      payment_status, started_at, scheduled_end_at, pricing_snapshot,
      policy_snapshot, request_id, created_by, created_at, updated_at)
    values (v_session, p_arena, nullif(p_payload->>'booking_id','')::uuid,
      v_customer, 'active', 'unpaid', v_started,
      (p_payload->>'scheduled_end_at')::timestamptz,
      p_payload->'pricing_snapshot',
      coalesce(p_payload->'pricing_snapshot'->'policy', '{}'::jsonb),
      p_request_id, auth.uid(), v_now, v_now);

  -- First segment (idx 0, open). The trigger re-checks resource-free + locks.
  insert into session_segments(id, arena_id, session_id, idx, resource_id,
      activity_code, game_id, controller_count, started_at, created_at)
    values (v_segment, p_arena, v_session, 0, v_resource,
      p_payload->>'activity_code', v_game,
      nullif(p_payload->>'controller_count','')::int, v_started, v_now);

  update customers set last_visit_at = v_started, updated_at = v_now
    where id = v_customer and arena_id = p_arena;
  if v_game is not null then
    update games set last_played_at = v_started, updated_at = v_now
      where id = v_game and arena_id = p_arena;
  end if;

  return v_session;
exception when unique_violation then
  -- A racing duplicate request_id: return the row the winner inserted.
  if p_request_id is not null then
    select id into v_existing from sessions
      where arena_id = p_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- reconfigure_session (switch system / change game / change controllers) --------
-- Closes the open segment at p_at and opens the next one. Not a reprice: the
-- parent pricing_snapshot is reused. request_id makes a sync retry a no-op.
create or replace function reconfigure_session(
  p_session          uuid,
  p_at               timestamptz,
  p_resource         uuid,
  p_activity_code    text,
  p_game             uuid default null,
  p_controller_count int  default null,
  p_new_segment_id   uuid default null,
  p_request_id       text default null
) returns jsonb as $$
declare
  v_now      timestamptz := statement_timestamp();
  v_arena    uuid;
  v_status   text;
  v_open     uuid;
  v_open_res uuid;
  v_started  timestamptz;
  v_idx      int;
  v_rstatus  text;
  v_gstatus  text;
  v_seg      uuid;
begin
  select arena_id, status into v_arena, v_status from sessions where id = p_session for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_request_id is not null then
    select id into v_seg from session_segments
      where arena_id = v_arena and request_id = p_request_id;
    if found then return jsonb_build_object('segment_id', v_seg, 'applied', false); end if;
  end if;

  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;

  select id, resource_id, started_at, idx
    into v_open, v_open_res, v_started, v_idx
    from session_segments
    where session_id = p_session and ended_at is null
    for update;
  if not found then raise exception 'no_open_segment'; end if;
  if p_at < v_started then raise exception 'invalid_time'; end if;

  -- Moving to a different resource: it must be free (trigger) + usable.
  if p_resource <> v_open_res then
    perform 1 from resources where id = p_resource and arena_id = v_arena for update;
    if not found then raise exception 'not_found' using hint = 'resource'; end if;
    select status into v_rstatus from resources where id = p_resource;
    if v_rstatus <> 'available' then raise exception 'resource_unusable' using hint = v_rstatus; end if;
  end if;
  if p_game is not null then
    select status into v_gstatus from game_resources
      where game_id = p_game and resource_id = p_resource;
    if not found or v_gstatus <> 'playable' then
      raise exception 'not_playable' using hint = coalesce(v_gstatus, 'not_installed');
    end if;
  end if;

  update session_segments set ended_at = p_at where id = v_open;
  v_seg := coalesce(p_new_segment_id, gen_random_uuid());
  insert into session_segments(id, arena_id, session_id, idx, resource_id,
      activity_code, game_id, controller_count, started_at, request_id, created_at)
    values (v_seg, v_arena, p_session, v_idx + 1, p_resource, p_activity_code,
      p_game, p_controller_count, p_at, p_request_id, v_now);

  update sessions set updated_at = v_now where id = p_session;
  if p_game is not null then
    update games set last_played_at = p_at, updated_at = v_now
      where id = p_game and arena_id = v_arena;
  end if;
  return jsonb_build_object('segment_id', v_seg, 'applied', true);
exception when unique_violation then
  -- Racing duplicate request_id (ux_segments_request): return the existing one.
  if p_request_id is not null then
    select id into v_seg from session_segments where arena_id = v_arena and request_id = p_request_id;
    if found then return jsonb_build_object('segment_id', v_seg, 'applied', false); end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- extend_session ---------------------------------------------------------------
create or replace function extend_session(
  p_session            uuid,
  p_added_minutes      int,
  p_new_end_at         timestamptz,
  p_added_amount_paise bigint,
  p_request_id         text default null,
  p_extension_id       uuid default null,
  p_reason             text default null
) returns jsonb as $$
declare
  v_now      timestamptz := statement_timestamp();
  v_arena    uuid;
  v_status   text;
  v_old_end  timestamptz;
  v_ext      uuid;
  v_existing uuid;
begin
  select arena_id, status, scheduled_end_at
    into v_arena, v_status, v_old_end
    from sessions where id = p_session for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_request_id is not null then
    select id into v_existing from session_extensions
      where arena_id = v_arena and request_id = p_request_id;
    if found then
      return jsonb_build_object('extension_id', v_existing,
        'new_end_at', (select scheduled_end_at from sessions where id = p_session),
        'applied', false);
    end if;
  end if;

  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;

  v_ext := coalesce(p_extension_id, gen_random_uuid());
  insert into session_extensions(id, arena_id, session_id, added_minutes,
      old_end_at, new_end_at, added_amount_paise, reason, request_id,
      created_by, created_at)
    values (v_ext, v_arena, p_session, p_added_minutes, v_old_end, p_new_end_at,
      coalesce(p_added_amount_paise, 0), p_reason, p_request_id, auth.uid(), v_now);
  update sessions set scheduled_end_at = p_new_end_at, updated_at = v_now
    where id = p_session;
  return jsonb_build_object('extension_id', v_ext, 'new_end_at', p_new_end_at, 'applied', true);
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from session_extensions
      where arena_id = v_arena and request_id = p_request_id;
    if found then
      return jsonb_build_object('extension_id', v_existing,
        'new_end_at', (select scheduled_end_at from sessions where id = p_session),
        'applied', false);
    end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- end_session ------------------------------------------------------------------
-- Idempotent by state: ending a completed session writes charges once and
-- returns the existing result; a voided session raises.
create or replace function end_session(
  p_session             uuid,
  p_ended_at            timestamptz,
  p_charges             jsonb,   -- array of immutable session_charge segments
  p_billed_amount_paise bigint,
  p_mark_waived         boolean default false
) returns jsonb as $$
declare
  v_now      timestamptz := statement_timestamp();
  v_arena    uuid;
  v_status   text;
  v_pay      text;
  v_paid     bigint;
  v_newpay   text;
  v_charge   jsonb;
begin
  select arena_id, status, payment_status into v_arena, v_status, v_pay
    from sessions where id = p_session for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  -- Waiving a bill is discount-gated in the app; mirror that server-side.
  if p_mark_waived and not (app_is_owner(v_arena) or app_has_perm(v_arena, 'discount')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'waive needs discount';
  end if;

  if v_status = 'voided' then raise exception 'voided'; end if;
  if v_status = 'completed' then
    return jsonb_build_object('status', 'completed', 'payment_status', v_pay,
      'billed_amount_paise', (select billed_amount_paise from sessions where id = p_session),
      'applied', false);
  end if;

  -- Close the open segment (frees the resource; trigger early-returns).
  update session_segments set ended_at = p_ended_at
    where session_id = p_session and ended_at is null;

  for v_charge in select jsonb_array_elements(coalesce(p_charges, '[]'::jsonb)) loop
    insert into session_charges(id, arena_id, session_id, segment_id, segment_index,
        band_code, activity_code, resource_id, controller_count, segment_start,
        segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise,
        amount_paise, created_at)
      values (coalesce(nullif(v_charge->>'id','')::uuid, gen_random_uuid()),
        v_arena, p_session, nullif(v_charge->>'segment_id','')::uuid,
        (v_charge->>'segment_index')::int, v_charge->>'band_code',
        v_charge->>'activity_code', nullif(v_charge->>'resource_id','')::uuid,
        nullif(v_charge->>'controller_count','')::int,
        (v_charge->>'segment_start')::timestamptz, (v_charge->>'segment_end')::timestamptz,
        (v_charge->>'played_minutes')::int, (v_charge->>'billed_minutes')::int,
        (v_charge->>'unit_minutes')::int, (v_charge->>'unit_price_paise')::bigint,
        (v_charge->>'amount_paise')::bigint, v_now);
  end loop;

  if p_mark_waived then
    v_newpay := 'waived';
  else
    select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = p_session;
    v_newpay := case
      when p_billed_amount_paise is null then (case when v_paid > 0 then 'partial' else 'unpaid' end)
      when v_paid >= p_billed_amount_paise then 'paid'
      when v_paid > 0 then 'partial'
      else 'unpaid' end;
  end if;

  update sessions set status = 'completed', actual_ended_at = p_ended_at,
      billed_amount_paise = p_billed_amount_paise, payment_status = v_newpay, updated_at = v_now
    where id = p_session;
  return jsonb_build_object('status', 'completed', 'payment_status', v_newpay,
    'billed_amount_paise', p_billed_amount_paise, 'applied', true);
end;
$$ language plpgsql security definer set search_path = public;

-- record_payment ---------------------------------------------------------------
create or replace function record_payment(
  p_session    uuid,
  p_amount_paise bigint,
  p_method     text,
  p_kind       text default 'payment',
  p_note       text default null,
  p_reason     text default null,
  p_request_id text default null,
  p_payment_id uuid default null
) returns uuid as $$
declare
  v_now       timestamptz := statement_timestamp();
  v_arena     uuid;
  v_pay       text;
  v_billed    bigint;
  v_signed    bigint;
  v_paid      bigint;
  v_pid       uuid;
  v_existing  uuid;
  v_is_refund boolean := (p_kind = 'refund');
begin
  select arena_id, payment_status, billed_amount_paise
    into v_arena, v_pay, v_billed
    from sessions where id = p_session for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  -- Refund is discount-gated in the app; mirror that server-side.
  if v_is_refund and not (app_is_owner(v_arena) or app_has_perm(v_arena, 'discount')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'refund needs discount';
  end if;

  if p_request_id is not null then
    select id into v_existing from payments
      where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;

  -- Money sign rules (payment_rules.signedPaymentAmount).
  if p_amount_paise = 0 then raise exception 'amount_zero'; end if;
  if v_is_refund then
    if p_reason is null or btrim(p_reason) = '' then raise exception 'refund_reason_required'; end if;
    v_signed := -abs(p_amount_paise);
  else
    if p_amount_paise < 0 then raise exception 'amount_negative'; end if;
    v_signed := p_amount_paise;
  end if;

  v_pid := coalesce(p_payment_id, gen_random_uuid());
  insert into payments(id, arena_id, session_id, amount_paise, method, kind,
      note, reason, request_id, created_by, created_at)
    values (v_pid, v_arena, p_session, v_signed, p_method, p_kind, p_note,
      p_reason, p_request_id, auth.uid(), v_now);

  -- Waived is sticky: a later payment never un-waives.
  if v_pay <> 'waived' then
    select coalesce(sum(amount_paise), 0) into v_paid from payments where session_id = p_session;
    update sessions set payment_status = case
        when v_billed is null then (case when v_paid > 0 then 'partial' else 'unpaid' end)
        when v_paid >= v_billed then 'paid'
        when v_paid > 0 then 'partial'
        else 'unpaid' end,
        updated_at = v_now
      where id = p_session;
  end if;
  return v_pid;
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from payments
      where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- void_session (owner-only correction) -----------------------------------------
create or replace function void_session(
  p_session uuid,
  p_reason  text
) returns void as $$
declare
  v_now    timestamptz := statement_timestamp();
  v_arena  uuid;
  v_status text;
begin
  select arena_id, status into v_arena, v_status from sessions where id = p_session for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if not app_is_owner(v_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  if v_status = 'voided' then return; end if;  -- idempotent
  update session_segments set ended_at = v_now where session_id = p_session and ended_at is null;
  update sessions set status = 'voided', void_reason = p_reason, updated_at = v_now
    where id = p_session;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (v_arena, 'session', p_session, 'void', p_reason, auth.uid(), v_now);
end;
$$ language plpgsql security definer set search_path = public;
