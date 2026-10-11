-- arena_ops — group-session RPCs (spec §9 group world).
--
-- Same contract as the single-session RPCs (0003): membership/role gate inside
-- the SECURITY DEFINER body, resource row lock + trigger for the one-open rule,
-- request_id idempotency, append-only history, one fixed statement_timestamp.
-- Group sessions are in sync v1 because the one-open-per-resource invariant
-- spans single segments AND group assignments; covering only one would let two
-- devices double-book a station.

-- Co-location legality (the richer rule the trigger cannot express) ------------
-- The trigger (0004) only guarantees cross-type / cross-group exclusion. Within
-- ONE group, several players may share a station, but only when the activity
-- uses controllers, everyone on it is the SAME activity + game, the summed
-- controller count is within port capacity (4), and there are enough physically
-- usable pads. Callers take the resource FOR UPDATE lock first (done in each RPC).
create or replace function assert_group_colocation_ok(
  p_arena          uuid,
  p_group          uuid,
  p_resource       uuid,
  p_activity_code  text,
  p_game           uuid,
  p_controller_count int,
  p_exclude        uuid default null
) returns void as $$
declare
  v_colocated int;
  v_diff      int;
  v_sum       int;
  v_uses_ctrl boolean;
  v_usable    int;
begin
  select count(*),
         count(*) filter (where activity_code is distinct from p_activity_code
                             or game_id is distinct from p_game),
         coalesce(sum(coalesce(controller_count, 0)), 0)
    into v_colocated, v_diff, v_sum
    from group_assignments
   where group_id = p_group and resource_id = p_resource and ended_at is null
     and (p_exclude is null or id <> p_exclude);

  if v_colocated = 0 then return; end if;  -- nothing to share with here

  select uses_controllers into v_uses_ctrl from activities
    where arena_id = p_arena and code = p_activity_code;
  if not coalesce(v_uses_ctrl, false) then
    raise exception 'colocation_not_allowed' using hint = 'activity does not share a station';
  end if;
  if v_diff > 0 then
    raise exception 'colocation_mismatch' using hint = 'same game required to share a station';
  end if;
  v_sum := v_sum + coalesce(p_controller_count, 0);
  if v_sum > 4 then
    raise exception 'capacity_exceeded' using hint = 'more than 4 controllers on one station';
  end if;
  select count(*) into v_usable from controllers
    where current_resource_id = p_resource and status = 'usable';
  if v_sum > v_usable then
    raise exception 'not_enough_pads' using hint = 'not enough usable controllers at that station';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

-- create_group -----------------------------------------------------------------
create or replace function create_group(
  p_arena uuid, p_payload jsonb, p_request_id text default null
) returns uuid as $$
declare
  v_now timestamptz := statement_timestamp();
  v_group uuid; v_existing uuid; v_started timestamptz; v_customer uuid;
  v_a jsonb; v_res uuid; v_game uuid; v_act text; v_cc int; v_aid uuid;
  v_rstatus text; v_gstatus text;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_request_id is not null then
    select id into v_existing from group_sessions where arena_id = p_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  if jsonb_array_length(coalesce(p_payload->'assignments', '[]'::jsonb)) = 0 then
    raise exception 'no_assignments';
  end if;

  v_group    := coalesce(nullif(p_payload->>'id','')::uuid, gen_random_uuid());
  v_started  := (p_payload->>'started_at')::timestamptz;
  v_customer := (p_payload->>'primary_customer_id')::uuid;

  insert into group_sessions(id, arena_id, primary_customer_id, player_count,
      purchased_controller_count, status, payment_status, started_at, scheduled_end_at,
      pricing_snapshot, policy_snapshot, billing_mode, request_id, created_by, created_at, updated_at)
    values (v_group, p_arena, v_customer, (p_payload->>'player_count')::int,
      coalesce((p_payload->>'purchased_controller_count')::int, 0), 'active', 'unpaid',
      v_started, (p_payload->>'scheduled_end_at')::timestamptz,
      p_payload->'pricing_snapshot', p_payload->'pricing_snapshot'->'policy',
      coalesce(nullif(p_payload->>'billing_mode',''), 'per_system'),
      p_request_id, auth.uid(), v_now, v_now);

  -- Deterministic resource order avoids deadlocks between concurrent groups.
  for v_a in select value from jsonb_array_elements(p_payload->'assignments')
             order by value->>'resource_id' loop
    v_res  := (v_a->>'resource_id')::uuid;
    v_game := nullif(v_a->>'game_id','')::uuid;
    v_act  := v_a->>'activity_code';
    v_cc   := nullif(v_a->>'controller_count','')::int;
    v_aid  := coalesce(nullif(v_a->>'id','')::uuid, gen_random_uuid());

    perform 1 from resources where id = v_res and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'resource'; end if;
    select status into v_rstatus from resources where id = v_res;
    if v_rstatus <> 'available' then raise exception 'resource_unusable' using hint = v_rstatus; end if;
    if v_game is not null then
      select status into v_gstatus from game_resources where game_id = v_game and resource_id = v_res;
      if not found or v_gstatus <> 'playable' then
        raise exception 'not_playable' using hint = coalesce(v_gstatus, 'not_installed');
      end if;
    end if;
    perform assert_group_colocation_ok(p_arena, v_group, v_res, v_act, v_game, v_cc);

    insert into group_assignments(id, arena_id, group_id, player_number, player_label,
        idx, resource_id, activity_code, game_id, controller_count, started_at, created_at)
      values (v_aid, p_arena, v_group, (v_a->>'player_number')::int, v_a->>'player_label',
        coalesce((v_a->>'idx')::int, 0), v_res, v_act, v_game, v_cc, v_started, v_now);
    if v_game is not null then
      update games set last_played_at = v_started, updated_at = v_now
        where id = v_game and arena_id = p_arena;
    end if;
  end loop;

  update customers set last_visit_at = v_started, updated_at = v_now
    where id = v_customer and arena_id = p_arena;
  return v_group;
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from group_sessions where arena_id = p_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- group arena + active guard, reused by the assignment ops ---------------------
create or replace function _group_arena_active(p_group uuid) returns uuid as $$
declare v_arena uuid; v_status text;
begin
  select arena_id, status into v_arena, v_status from group_sessions where id = p_group for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_arena not in (select app_arena_ids()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  return v_arena;
end;
$$ language plpgsql security definer set search_path = public;

-- add_assignment (a player joins / starts on a station) ------------------------
create or replace function add_assignment(
  p_group uuid, p_at timestamptz, p_player_number int, p_player_label text,
  p_resource uuid, p_activity_code text, p_game uuid, p_controller_count int,
  p_assignment_id uuid default null, p_request_id text default null
) returns uuid as $$
declare
  v_now timestamptz := statement_timestamp();
  v_arena uuid; v_existing uuid; v_idx int; v_rstatus text; v_gstatus text; v_aid uuid;
begin
  v_arena := _group_arena_active(p_group);
  if p_request_id is not null then
    select id into v_existing from group_assignments where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  if exists (select 1 from group_assignments
               where group_id = p_group and player_number = p_player_number and ended_at is null) then
    raise exception 'player_busy';
  end if;

  perform 1 from resources where id = p_resource and arena_id = v_arena for update;
  if not found then raise exception 'not_found' using hint = 'resource'; end if;
  select status into v_rstatus from resources where id = p_resource;
  if v_rstatus <> 'available' then raise exception 'resource_unusable' using hint = v_rstatus; end if;
  if p_game is not null then
    select status into v_gstatus from game_resources where game_id = p_game and resource_id = p_resource;
    if not found or v_gstatus <> 'playable' then raise exception 'not_playable' using hint = coalesce(v_gstatus, 'not_installed'); end if;
  end if;
  perform assert_group_colocation_ok(v_arena, p_group, p_resource, p_activity_code, p_game, p_controller_count);

  select coalesce(max(idx), -1) + 1 into v_idx from group_assignments
    where group_id = p_group and player_number = p_player_number;
  v_aid := coalesce(p_assignment_id, gen_random_uuid());
  insert into group_assignments(id, arena_id, group_id, player_number, player_label,
      idx, resource_id, activity_code, game_id, controller_count, started_at, request_id, created_at)
    values (v_aid, v_arena, p_group, p_player_number, p_player_label, v_idx, p_resource,
      p_activity_code, p_game, p_controller_count, p_at, p_request_id, v_now);
  update group_sessions set updated_at = v_now where id = p_group;
  if p_game is not null then update games set last_played_at = p_at, updated_at = v_now where id = p_game and arena_id = v_arena; end if;
  return v_aid;
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from group_assignments where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- switch_assignment (a player moves station / changes game or controllers) -----
create or replace function switch_assignment(
  p_group uuid, p_at timestamptz, p_player_number int,
  p_resource uuid, p_activity_code text, p_game uuid, p_controller_count int,
  p_new_assignment_id uuid default null, p_request_id text default null
) returns uuid as $$
declare
  v_now timestamptz := statement_timestamp();
  v_arena uuid; v_existing uuid; v_open uuid; v_started timestamptz; v_idx int;
  v_rstatus text; v_gstatus text; v_aid uuid;
begin
  v_arena := _group_arena_active(p_group);
  if p_request_id is not null then
    select id into v_existing from group_assignments where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;

  select id, started_at, idx into v_open, v_started, v_idx from group_assignments
    where group_id = p_group and player_number = p_player_number and ended_at is null
    for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if p_at < v_started then raise exception 'invalid_time'; end if;

  perform 1 from resources where id = p_resource and arena_id = v_arena for update;
  if not found then raise exception 'not_found' using hint = 'resource'; end if;
  select status into v_rstatus from resources where id = p_resource;
  if v_rstatus <> 'available' then raise exception 'resource_unusable' using hint = v_rstatus; end if;
  if p_game is not null then
    select status into v_gstatus from game_resources where game_id = p_game and resource_id = p_resource;
    if not found or v_gstatus <> 'playable' then raise exception 'not_playable' using hint = coalesce(v_gstatus, 'not_installed'); end if;
  end if;
  -- Legality excludes this player's own open row (they are moving off it).
  perform assert_group_colocation_ok(v_arena, p_group, p_resource, p_activity_code, p_game, p_controller_count, v_open);

  update group_assignments set ended_at = p_at where id = v_open;
  v_aid := coalesce(p_new_assignment_id, gen_random_uuid());
  insert into group_assignments(id, arena_id, group_id, player_number, player_label,
      idx, resource_id, activity_code, game_id, controller_count, started_at, request_id, created_at)
    select v_aid, v_arena, p_group, p_player_number, player_label, v_idx + 1, p_resource,
      p_activity_code, p_game, p_controller_count, p_at, p_request_id, v_now
    from group_assignments where id = v_open;
  update group_sessions set updated_at = v_now where id = p_group;
  if p_game is not null then update games set last_played_at = p_at, updated_at = v_now where id = p_game and arena_id = v_arena; end if;
  return v_aid;
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from group_assignments where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- end_assignment (a player leaves) ---------------------------------------------
create or replace function end_assignment(
  p_group uuid, p_player_number int, p_at timestamptz
) returns void as $$
declare v_now timestamptz := statement_timestamp(); v_arena uuid; v_open uuid; v_started timestamptz;
begin
  v_arena := _group_arena_active(p_group);
  select id, started_at into v_open, v_started from group_assignments
    where group_id = p_group and player_number = p_player_number and ended_at is null for update;
  if not found then raise exception 'no_open_assignment'; end if;
  if p_at < v_started then raise exception 'invalid_time'; end if;
  update group_assignments set ended_at = p_at where id = v_open;
  update group_sessions set updated_at = v_now where id = p_group;
end;
$$ language plpgsql security definer set search_path = public;

-- extend_group -----------------------------------------------------------------
create or replace function extend_group(
  p_group uuid, p_added_minutes int, p_new_end_at timestamptz,
  p_added_amount_paise bigint, p_request_id text default null,
  p_extension_id uuid default null, p_reason text default null
) returns jsonb as $$
declare v_now timestamptz := statement_timestamp(); v_arena uuid; v_status text; v_old_end timestamptz; v_ext uuid; v_existing uuid;
begin
  -- Dedup BEFORE the active-status guard (like extend_session) so a retry after
  -- the group has ended still returns the prior extension instead of not_active.
  select arena_id, status, scheduled_end_at into v_arena, v_status, v_old_end
    from group_sessions where id = p_group for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_arena not in (select app_arena_ids()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_request_id is not null then
    select id into v_existing from group_extensions where arena_id = v_arena and request_id = p_request_id;
    if found then return jsonb_build_object('extension_id', v_existing,
      'new_end_at', (select scheduled_end_at from group_sessions where id = p_group), 'applied', false); end if;
  end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  v_ext := coalesce(p_extension_id, gen_random_uuid());
  insert into group_extensions(id, arena_id, group_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, request_id, created_by, created_at)
    values (v_ext, v_arena, p_group, p_added_minutes, v_old_end, p_new_end_at,
      coalesce(p_added_amount_paise, 0), p_reason, p_request_id, auth.uid(), v_now);
  update group_sessions set scheduled_end_at = p_new_end_at, updated_at = v_now where id = p_group;
  return jsonb_build_object('extension_id', v_ext, 'new_end_at', p_new_end_at, 'applied', true);
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from group_extensions where arena_id = v_arena and request_id = p_request_id;
    if found then return jsonb_build_object('extension_id', v_existing,
      'new_end_at', (select scheduled_end_at from group_sessions where id = p_group), 'applied', false); end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- end_group --------------------------------------------------------------------
create or replace function end_group(
  p_group uuid, p_ended_at timestamptz, p_charges jsonb,
  p_billed_amount_paise bigint, p_mark_waived boolean default false
) returns jsonb as $$
declare
  v_now timestamptz := statement_timestamp(); v_arena uuid; v_status text; v_pay text;
  v_paid bigint; v_newpay text; v_charge jsonb;
begin
  select arena_id, status, payment_status into v_arena, v_status, v_pay
    from group_sessions where id = p_group for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_arena not in (select app_arena_ids()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_mark_waived and not (app_is_owner(v_arena) or app_has_perm(v_arena, 'discount')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'waive needs discount';
  end if;
  if v_status = 'voided' then raise exception 'voided'; end if;
  if v_status = 'completed' then
    return jsonb_build_object('status', 'completed', 'payment_status', v_pay,
      'billed_amount_paise', (select billed_amount_paise from group_sessions where id = p_group), 'applied', false);
  end if;

  update group_assignments set ended_at = p_ended_at where group_id = p_group and ended_at is null;

  for v_charge in select jsonb_array_elements(coalesce(p_charges, '[]'::jsonb)) loop
    insert into group_charges(id, arena_id, group_id, assignment_id, player_number, charge_index,
        band_code, activity_code, resource_id, controller_count, segment_start, segment_end,
        played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values (coalesce(nullif(v_charge->>'id','')::uuid, gen_random_uuid()), v_arena, p_group,
        nullif(v_charge->>'assignment_id','')::uuid, nullif(v_charge->>'player_number','')::int,
        (v_charge->>'charge_index')::int, v_charge->>'band_code', v_charge->>'activity_code',
        nullif(v_charge->>'resource_id','')::uuid, nullif(v_charge->>'controller_count','')::int,
        (v_charge->>'segment_start')::timestamptz, (v_charge->>'segment_end')::timestamptz,
        (v_charge->>'played_minutes')::int, (v_charge->>'billed_minutes')::int,
        (v_charge->>'unit_minutes')::int, (v_charge->>'unit_price_paise')::bigint,
        (v_charge->>'amount_paise')::bigint, v_now);
  end loop;

  if p_mark_waived then
    v_newpay := 'waived';
  else
    select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = p_group;
    v_newpay := case
      when p_billed_amount_paise is null then (case when v_paid > 0 then 'partial' else 'unpaid' end)
      when v_paid >= p_billed_amount_paise then 'paid'
      when v_paid > 0 then 'partial'
      else 'unpaid' end;
  end if;
  update group_sessions set status = 'completed', actual_ended_at = p_ended_at,
      billed_amount_paise = p_billed_amount_paise, payment_status = v_newpay, updated_at = v_now
    where id = p_group;
  return jsonb_build_object('status', 'completed', 'payment_status', v_newpay,
    'billed_amount_paise', p_billed_amount_paise, 'applied', true);
end;
$$ language plpgsql security definer set search_path = public;

-- record_group_payment ---------------------------------------------------------
create or replace function record_group_payment(
  p_group uuid, p_amount_paise bigint, p_method text, p_is_refund boolean default false,
  p_note text default null, p_reason text default null, p_request_id text default null,
  p_payment_id uuid default null
) returns uuid as $$
declare
  v_now timestamptz := statement_timestamp(); v_arena uuid; v_pay text; v_billed bigint;
  v_signed bigint; v_paid bigint; v_pid uuid; v_existing uuid;
begin
  select arena_id, payment_status, billed_amount_paise into v_arena, v_pay, v_billed
    from group_sessions where id = p_group for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_arena not in (select app_arena_ids()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_is_refund and not (app_is_owner(v_arena) or app_has_perm(v_arena, 'discount')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'refund needs discount';
  end if;
  if p_request_id is not null then
    select id into v_existing from group_payments where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;

  if p_amount_paise = 0 then raise exception 'amount_zero'; end if;
  if p_is_refund then
    if p_reason is null or btrim(p_reason) = '' then raise exception 'refund_reason_required'; end if;
    v_signed := -abs(p_amount_paise);
  else
    if p_amount_paise < 0 then raise exception 'amount_negative'; end if;
    v_signed := p_amount_paise;
  end if;

  v_pid := coalesce(p_payment_id, gen_random_uuid());
  insert into group_payments(id, arena_id, group_id, amount_paise, method, is_refund,
      note, reason, request_id, created_by, created_at)
    values (v_pid, v_arena, p_group, v_signed, p_method, p_is_refund, p_note, p_reason,
      p_request_id, auth.uid(), v_now);
  if v_pay <> 'waived' then
    select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = p_group;
    update group_sessions set payment_status = case
        when v_billed is null then (case when v_paid > 0 then 'partial' else 'unpaid' end)
        when v_paid >= v_billed then 'paid'
        when v_paid > 0 then 'partial'
        else 'unpaid' end,
        updated_at = v_now
      where id = p_group;
  end if;
  return v_pid;
exception when unique_violation then
  if p_request_id is not null then
    select id into v_existing from group_payments where arena_id = v_arena and request_id = p_request_id;
    if found then return v_existing; end if;
  end if;
  raise;
end;
$$ language plpgsql security definer set search_path = public;

-- void_group (owner-only correction) -------------------------------------------
create or replace function void_group(p_group uuid, p_reason text) returns void as $$
declare v_now timestamptz := statement_timestamp(); v_arena uuid; v_status text;
begin
  select arena_id, status into v_arena, v_status from group_sessions where id = p_group for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if not app_is_owner(v_arena) then raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only'; end if;
  if v_status = 'voided' then return; end if;
  update group_assignments set ended_at = v_now where group_id = p_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = p_reason, updated_at = v_now where id = p_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (v_arena, 'group_session', p_group, 'void', p_reason, auth.uid(), v_now);
end;
$$ language plpgsql security definer set search_path = public;

-- Execute surface: signed-in users only (bodies gate on membership / role).
revoke execute on function
  create_group(uuid, jsonb, text),
  add_assignment(uuid, timestamptz, int, text, uuid, text, uuid, int, uuid, text),
  switch_assignment(uuid, timestamptz, int, uuid, text, uuid, int, uuid, text),
  end_assignment(uuid, int, timestamptz),
  extend_group(uuid, int, timestamptz, bigint, text, uuid, text),
  end_group(uuid, timestamptz, jsonb, bigint, boolean),
  record_group_payment(uuid, bigint, text, boolean, text, text, text, uuid),
  void_group(uuid, text)
  from anon, public;
grant execute on function
  create_group(uuid, jsonb, text),
  add_assignment(uuid, timestamptz, int, text, uuid, text, uuid, int, uuid, text),
  switch_assignment(uuid, timestamptz, int, uuid, text, uuid, int, uuid, text),
  end_assignment(uuid, int, timestamptz),
  extend_group(uuid, int, timestamptz, bigint, text, uuid, text),
  end_group(uuid, timestamptz, jsonb, bigint, boolean),
  record_group_payment(uuid, bigint, text, boolean, text, text, text, uuid),
  void_group(uuid, text)
  to authenticated;

-- Internal helpers run only inside the SECURITY DEFINER RPC bodies above (as the
-- function owner), so no client role needs direct EXECUTE on them.
revoke execute on function
  assert_group_colocation_ok(uuid, uuid, uuid, text, uuid, int, uuid),
  _group_arena_active(uuid)
  from anon, public, authenticated;
