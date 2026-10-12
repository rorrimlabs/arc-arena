set local check_function_bodies = off;

create or replace function public._group_assignable (
  p_arena          uuid,
  p_group          uuid,
  p_resource       uuid,
  p_activity       text,
  p_game           uuid,
  p_cc             integer,
  p_player         integer,
  p_exclude_player integer,
  p_borrowed       integer
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_used int; v_usable int; v_max int; v_others int; v_players int;
begin
  perform _station_usable(p_arena, p_resource);
  perform _mode_ok(p_arena, p_resource, p_activity);
  perform _game_playable(p_game, p_resource);
  if exists (select 1 from session_segments where resource_id = p_resource and ended_at is null) then
    raise exception 'resource_busy';
  end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id <> p_group) then
    raise exception 'resource_busy' using hint = 'another group';
  end if;
  select count(*), coalesce(sum(coalesce(controller_count, 0)), 0)
    into v_others, v_used
    from group_assignments
   where resource_id = p_resource and ended_at is null and group_id = p_group
     and not (p_exclude_player is not null and player_number = p_exclude_player);
  if v_used + p_cc > 4 then raise exception 'controllers_exceeded'; end if;
  if p_game is not null then
    v_max := _game_max_players(p_game);
    if v_used + p_cc > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
  v_usable := _usable_pads_at(p_arena, p_resource) + coalesce(p_borrowed, 0);
  if v_used + p_cc > v_usable then
    raise exception 'controllers_unavailable' using hint = v_usable::text || ' usable';
  end if;
  if v_others = 0 then return; end if;
  -- Sharing a station with this group's other players: controller activities only, same activity and game.
  if not _uses_controllers(p_arena, p_activity) then raise exception 'resource_busy'; end if;
  if exists (select 1 from group_assignments
              where resource_id = p_resource and ended_at is null and group_id = p_group
                and not (p_exclude_player is not null and player_number = p_exclude_player)
                and (activity_code is distinct from p_activity or game_id is distinct from p_game)) then
    raise exception 'game_conflict';
  end if;
  if p_game is not null then
    -- Distinct players on the station after placing p_player (+1 unless already there).
    select count(distinct player_number) + (case when exists (
             select 1 from group_assignments where resource_id = p_resource and ended_at is null
               and group_id = p_group and player_number = p_player
               and not (p_exclude_player is not null and player_number = p_exclude_player))
           then 0 else 1 end)
      into v_players from group_assignments
     where resource_id = p_resource and ended_at is null and group_id = p_group
       and not (p_exclude_player is not null and player_number = p_exclude_player);
    if v_players > v_max then raise exception 'players_exceeded' using hint = v_max::text; end if;
  end if;
end;
$function$;

create or replace function public._group_lock (
  p_arena       uuid,
  p_assignments jsonb,
  p_extra       uuid[] default '{}'::uuid[]
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_res uuid[] := p_extra; v_borrow uuid[] := '{}'; v_pads uuid[] := '{}'; a jsonb;
  v_origins uuid[];
begin
  for a in select value from jsonb_array_elements(p_assignments) loop
    v_res := v_res || (a->>'resource_id')::uuid;
    v_borrow := v_borrow || _pad_ids(a->'moves');
    v_pads := v_pads || _pad_ids(a->'allocations');
  end loop;
  v_origins := _pad_origins(p_arena, v_borrow);
  -- Stations before pads, each in id order (same order as the single-session ops).
  perform _lock_resources(p_arena, v_res || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  -- A pad that moved between the read and the lock sits at a station we do not hold: retry.
  if not (_pad_origins(p_arena, v_borrow) <@ (v_res || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;
end;
$function$;

create or replace function public._pr_happy (
  s jsonb,
  d date
)
  returns tstzrange
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
declare
  w jsonb := s->'hours'->'happy'->(extract(isodow from d)::int::text);
  -- IST midnight of d as an instant: d 00:00 UTC minus 5h30 (fixed offset, no DST).
  midnight timestamptz := (d::timestamp at time zone 'UTC') - interval '330 minutes';
begin
  if coalesce(s->'holidays', '[]'::jsonb) ? d::text
     or coalesce(s->'closed_days', '[]'::jsonb) ? d::text then
    return null;
  end if;
  if w is null or jsonb_typeof(w) <> 'object' then return null; end if;
  return tstzrange(midnight + make_interval(mins => (w->>'start')::int),
                   midnight + make_interval(mins => (w->>'end')::int), '[)');
end;
$function$;

create or replace function public._pr_quote (
  s       jsonb,
  p_act   text,
  p_cc    integer,
  p_start timestamp with time zone,
  p_end   timestamp with time zone
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
declare
  pol jsonb := _pr_policy(s);
  v_act jsonb;
  v_total bigint; v_min bigint; v_bend timestamptz;
  v_pts timestamptz[]; v_d date; v_hw tstzrange; v_mid timestamptz; v_band text;
  bs timestamptz[] := '{}'; be timestamptz[] := '{}'; bb text[] := '{}';
  n int := 0; i int;
  v_rate jsonb; v_price bigint; v_um int; v_us bigint; v_sec bigint; v_played bigint;
  v_num bigint; v_den bigint; v_billed bigint; v_units bigint; v_block int;
  v_sum_num bigint := 0; v_common bigint; v_mixed boolean := false; v_seg_sum bigint := 0;
  v_amount bigint; v_sub bigint;
  v_lines jsonb := '[]'::jsonb;
begin
  if p_end < p_start then return null; end if;
  select a into v_act from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a
   where a->>'code' = p_act limit 1;
  if v_act is null then return null; end if;

  v_total := _pr_secs(p_start, p_end);
  -- Grace: free when under the grace period.
  if v_total <= (pol->>'grace_minutes')::int * 60 then
    return jsonb_build_object('subtotal', 0, 'amount', 0, 'lines', '[]'::jsonb);
  end if;
  -- Minimum charge: bill at least this much by extending the billed interval.
  v_min := (pol->>'minimum_charge_minutes')::int * 60;
  v_bend := case when v_total < v_min then p_start + make_interval(secs => v_min) else p_end end;

  -- Band segments: split at every happy-hour boundary, label by midpoint, merge.
  if not coalesce((v_act->>'happy_eligible')::boolean, false) then
    bs := array[p_start]; be := array[v_bend]; bb := array['standard']; n := 1;
  else
    v_pts := array[p_start, v_bend];
    v_d := _pr_ist_date(p_start);
    while v_d <= _pr_ist_date(v_bend) loop
      v_hw := _pr_happy(s, v_d);
      if v_hw is not null then
        if lower(v_hw) > p_start and lower(v_hw) < v_bend then v_pts := v_pts || lower(v_hw); end if;
        if upper(v_hw) > p_start and upper(v_hw) < v_bend then v_pts := v_pts || upper(v_hw); end if;
      end if;
      v_d := v_d + 1;
    end loop;
    select array_agg(distinct x order by x) into v_pts from unnest(v_pts) x;
    for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
      continue when v_pts[i + 1] <= v_pts[i];
      v_mid := v_pts[i] + (v_pts[i + 1] - v_pts[i]) / 2;
      v_hw := _pr_happy(s, _pr_ist_date(v_mid));
      v_band := case when v_hw is not null and v_hw @> v_mid then 'happy' else 'standard' end;
      if n > 0 and bb[n] = v_band then
        be[n] := v_pts[i + 1];
      else
        n := n + 1; bs[n] := v_pts[i]; be[n] := v_pts[i + 1]; bb[n] := v_band;
      end if;
    end loop;
  end if;

  for i in 1 .. n loop
    v_rate := _pr_rate(s, p_act, bb[i], p_cc);
    if v_rate is null and bb[i] = 'happy' then
      v_rate := _pr_rate(s, p_act, 'standard', p_cc);   -- happy → standard fallback
    end if;
    if v_rate is null then return null; end if;
    v_price := (v_rate->>'price_paise')::bigint;
    v_um := (v_rate->>'unit_minutes')::int;
    v_us := v_um::bigint * 60;
    v_sec := _pr_secs(bs[i], be[i]);
    -- Played time counts only the real [p_start, p_end]; the billed piece may run past p_end.
    v_played := case when least(p_end, be[i]) > greatest(p_start, bs[i])
                     then _pr_secs(greatest(p_start, bs[i]), least(p_end, be[i])) else 0 end;
    v_units := 0;
    if v_act->>'duration_model' = 'unit' then
      case pol->>'vr_unit_rounding'
        when 'prorate' then
          v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
        when 'nearest' then
          v_units := _pr_div(v_sec, v_us);
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
        else -- up
          v_units := (v_sec + v_us - 1) / v_us;
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
      end case;
    elsif pol->>'billing_unit' = 'per_minute' then
      v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
    else
      v_block := case pol->>'billing_unit' when 'block_15' then 15 when 'block_30' then 30 else 60 end;
      v_billed := (v_sec + 59) / 60;   -- whole minutes first
      v_billed := case when pol->>'block_rounding' = 'up' then _pr_ceil_step(v_billed, v_block)
                       else _pr_round_step(v_billed, v_block) end;
      v_num := v_price * v_billed; v_den := v_um;
    end if;

    -- Rounding scope: keep the exact numerator over a common denominator so 'session' scope
    -- rounds once (below); 'segment' scope or mixed denominators sum the per-line paise.
    v_common := coalesce(v_common, v_den);
    if v_den <> v_common then v_mixed := true; end if;
    v_sum_num := v_sum_num + v_num;
    v_amount := _pr_div(v_num, v_den);
    v_seg_sum := v_seg_sum + v_amount;
    v_lines := v_lines || jsonb_build_object('start', bs[i], 'end', be[i], 'band', bb[i],
      'played_seconds', v_played, 'billed_minutes', v_billed, 'units', v_units,
      'unit_minutes', v_um, 'unit_price', v_price, 'amount', v_amount);
  end loop;

  v_sub := case when pol->>'rounding_scope' = 'segment' or v_mixed then v_seg_sum
                else _pr_div(v_sum_num, coalesce(v_common, 1)) end;
  return jsonb_build_object('subtotal', v_sub,
    'amount', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'lines', v_lines);
end;
$function$;

create or replace function public.add_staff_by_email (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_perms text[]
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_user uuid;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can add staff';
  end if;
  perform _assert_known_perms(p_perms);
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if not found then
    raise exception 'no_account'
      using hint = 'create their login first: Authentication → Users → Add user';
  end if;
  -- Nobody changes their own access (same rule as op_staff_update): re-adding
  -- yourself would rewrite your own perms.
  if v_user = auth.uid() then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'you cannot change your own permissions';
  end if;
  if exists (select 1 from staff_profiles
              where arena_id = p_arena and user_id = v_user and role = 'owner') then
    raise exception 'owner_profile'
      using hint = 'that login is an owner of this arena; edit it in Settings → Staff';
  end if;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (p_arena, v_user, coalesce(nullif(btrim(p_name), ''), 'Staff'), 'staff',
      coalesce(p_perms, '{}'), true)
  on conflict (user_id, arena_id) do update
    set name = excluded.name, perms = excluded.perms, active = true,
        updated_at = statement_timestamp();
  -- Re-adding someone with fewer permissions must not strand Settings.
  perform _assert_settings_holder(p_arena);
  return v_user;
end;
$function$;

create or replace function public.assert_resource_free_for_assignment()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
declare
  busy int;
begin
  if new.ended_at is not null then
    return new;
  end if;
  perform 1 from resources where id = new.resource_id for update;

  select count(*) into busy from (
    select 1 from session_segments
      where resource_id = new.resource_id
        and ended_at is null
    union all
    -- Open assignments of the same group may share the station.
    select 1 from group_assignments
      where resource_id = new.resource_id
        and ended_at is null
        and group_id <> new.group_id
        and id <> new.id
  ) t;

  if busy > 0 then
    raise exception 'resource_busy'
      using hint = 'That station already has a session on it.';
  end if;
  return new;
end;
$function$;

create or replace function public.op_booking_set_status (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_status text;
begin
  perform _need(p_arena, 'start');
  if (p->>'status') not in ('cancelled', 'no_show') then
    raise exception 'invalid_status' using hint = coalesce(p->>'status', 'null');
  end if;
  select status into v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  -- Already in that state (a replay, or the other device did it): succeed without writing.
  if v_status = p->>'status' then return '{}'::jsonb; end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  update bookings set status = p->>'status', updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_booking_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_xid xid8; v_status text; v_res uuid := nullif(p->>'resource_id','')::uuid;
begin
  perform _need(p_arena, 'start');
  select sync_xid, status into v_xid, v_status from bookings
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'booking'; end if;
  -- base_version is the row's sync_xid as the device last pulled it; absent/empty skips the check.
  if _stale(v_xid, p->>'base_version') then
    raise exception 'stale' using hint = 'the booking was changed on another device';
  end if;
  if v_status <> 'booked' then raise exception 'booking_not_open' using hint = v_status; end if;
  perform _booking_free(p_arena, (p->>'id')::uuid, v_res,
    (p->>'scheduled_start')::timestamptz, (p->>'scheduled_end')::timestamptz);
  update bookings set customer_id = nullif(p->>'customer_id','')::uuid, resource_id = v_res,
      activity_id = _activity_id(p_arena, p->>'activity_code'), game_id = nullif(p->>'game_id','')::uuid,
      scheduled_start = (p->>'scheduled_start')::timestamptz,
      scheduled_end = (p->>'scheduled_end')::timestamptz,
      players_required = nullif(p->>'players_required','')::int,
      controller_requirement = nullif(p->>'controller_requirement','')::int,
      party_name = p->>'party_name', phone = p->>'phone', notes = p->>'notes',
      updated_at = statement_timestamp()
    where id = (p->>'id')::uuid;
  return '{}'::jsonb;
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
  v_loc uuid; v_home uuid; v_loc2 uuid; v_home2 uuid;
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
  -- Stations are locked before pads (the order every op uses), so the pad was
  -- read unlocked above. If it moved or was re-homed in between, the stations
  -- we hold are the wrong ones: retry rather than move it unlocked.
  select current_resource_id, home_resource_id into v_loc2, v_home2 from controllers where id = v_cid;
  if v_loc2 is distinct from v_loc or v_home2 is distinct from v_home then
    raise exception 'retry' using errcode = '40001';
  end if;
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
  -- adjusted: no move_id was sent, so the server minted the history row id; the device refetches.
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$function$;

create or replace function public.op_customer_create (
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
  v_phone text := nullif(btrim(p->>'phone'), '');
  v_other uuid;
begin
  if not (app_has_perm(p_arena, 'start') or app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  -- A phone already in use (two devices registering the same person offline) must not sink
  -- the sessions that reference this customer: keep the row phone-less and audit the clash.
  if v_phone is not null then
    select id into v_other from customers where arena_id = p_arena and phone = v_phone;
  end if;
  insert into customers(id, arena_id, name, phone, notes, last_visit_at, is_guest, created_at, updated_at)
    values ((p->>'id')::uuid, p_arena, p->>'name', case when v_other is null then v_phone end,
      p->>'notes', (p->>'last_visit_at')::timestamptz, coalesce((p->>'is_guest')::boolean, false),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now);
  if v_other is not null then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
      values (p_arena, 'customer', (p->>'id')::uuid, 'duplicate_phone_on_sync',
        'phone already belongs to another customer', jsonb_build_object('phone', v_phone,
        'existing_customer_id', v_other), auth.uid(), v_now);
    return jsonb_build_object('adjusted', true, 'phone_taken_by', v_other);
  end if;
  return jsonb_build_object('adjusted', false);
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
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
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

create or replace function public.op_group_void (
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
  v_at timestamptz := coalesce((p->>'at')::timestamptz, v_now);
  v_status text;
begin
  if not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'void is owner-only';
  end if;
  select status into v_status from group_sessions where id = v_group and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'group'; end if;
  if v_status = 'voided' then return jsonb_build_object('adjusted', true); end if;
  -- greatest(): never end a row before it started, whatever the device clock said.
  update group_assignments set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = greatest(v_at, started_at)
    where group_id = v_group and ended_at is null;
  update group_sessions set status = 'voided', void_reason = p->>'reason', updated_at = v_now
    where id = v_group;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'group_session', v_group, 'void', p->>'reason', auth.uid(), v_now);
  return jsonb_build_object('adjusted', false);
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

  -- v_paid is null when the parent was not found; not_found is raised further down.
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

create or replace function public.op_rate_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  delete from rates r using rate_bands b, activities a
   where r.arena_id = p_arena and r.rate_card_id = _active_card(p_arena)
     and b.id = r.band_id and b.code = p->>'band'
     and a.id = r.activity_id and a.code = p->>'activity_code'
     -- -1 stands for null so the any-count rate (controller_count null) matches itself.
     and coalesce(r.controller_count, -1) = coalesce(nullif(p->>'controller_count','')::int, -1);
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_rate_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_card uuid := _active_card(p_arena);
  v_act uuid := _activity_id(p_arena, p->>'activity_code');
  v_band uuid := _band_id(p_arena, p->>'band');
  v_cc int := nullif(p->>'controller_count','')::int;
  v_id uuid;
begin
  -- The declare initialisers (_active_card, _activity_id, _band_id) already ran; anything
  -- they inserted rolls back with the op if this refuses.
  perform _need(p_arena, 'settings');
  select id into v_id from rates where rate_card_id = v_card and activity_id = v_act
    and band_id = v_band and coalesce(controller_count, -1) = coalesce(v_cc, -1) for update;
  if found then
    update rates set unit_minutes = (p->>'unit_minutes')::int,
        price_paise = (p->>'price_paise')::bigint, updated_at = statement_timestamp()
      where id = v_id;
  else
    insert into rates(arena_id, rate_card_id, activity_id, band_id, controller_count, unit_minutes, price_paise)
      values (p_arena, v_card, v_act, v_band, v_cc, (p->>'unit_minutes')::int, (p->>'price_paise')::bigint);
  end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.sync_fetch_entity (
  p_arena uuid,
  p_refs  jsonb
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_ref  jsonb;
  v_id   uuid;
  v_rows jsonb;
  v_out  jsonb := '[]'::jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  for v_ref in select value from jsonb_array_elements(coalesce(p_refs, '[]'::jsonb)) loop
    v_id := nullif(v_ref->>'id', '')::uuid;
    -- controller_moves point at their session/group via session_ref
    -- ('s:<session id>' or 'g:<group id>'), not a uuid column.
    v_rows := case v_ref->>'type'
      when 'session' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','sessions','r',to_jsonb(s)) x from sessions s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','session_segments','r',to_jsonb(s)) from session_segments s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','session_extensions','r',to_jsonb(s)) from session_extensions s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','session_charges','r',to_jsonb(s)) from session_charges s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','payments','r',to_jsonb(s)) from payments s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.session_id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.session_ref = 's:' || v_id::text
        ) q)
      when 'group' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','group_sessions','r',to_jsonb(s)) x from group_sessions s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','group_assignments','r',to_jsonb(s)) from group_assignments s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_extensions','r',to_jsonb(s)) from group_extensions s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_charges','r',to_jsonb(s)) from group_charges s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','group_payments','r',to_jsonb(s)) from group_payments s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.group_id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.session_ref = 'g:' || v_id::text
        ) q)
      when 'controller' then (
        select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t','controllers','r',to_jsonb(s)) x from controllers s where s.arena_id = p_arena and s.id = v_id
          union all select jsonb_build_object('t','controller_moves','r',to_jsonb(s)) from controller_moves s where s.arena_id = p_arena and s.controller_id = v_id
          union all select jsonb_build_object('t','controller_allocations','r',to_jsonb(s)) from controller_allocations s where s.arena_id = p_arena and s.controller_id = v_id and s.ended_at is null
        ) q)
      when 'customer' then (
        select coalesce(jsonb_agg(jsonb_build_object('t','customers','r',to_jsonb(s))), '[]'::jsonb)
          from customers s where s.arena_id = p_arena and s.id = v_id)
      when 'booking' then (
        select coalesce(jsonb_agg(jsonb_build_object('t','bookings','r',to_jsonb(s))), '[]'::jsonb)
          from sync_v_bookings s where s.arena_id = p_arena and s.id = v_id)
      else '[]'::jsonb
    end;
    v_out := v_out || jsonb_build_array(jsonb_build_object('ref', v_ref, 'rows', v_rows));
  end loop;
  return v_out;
end;
$function$;

create or replace function public.sync_pull (
  p_arena  uuid,
  p_cursor text    default '0'::text,
  p_limit  integer default 2000
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_union text;
  v_out   jsonb;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if p_arena is null or not exists (select 1 from app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 then p_limit := 2000; end if;

  select string_agg(format(
      'select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s '
      'where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)',
      name, rel), ' union all ')
    into v_union from _sync_sources();

  -- Upper bound is the snapshot's xmin, so a row from a transaction still open
  -- now is never skipped by a later cursor. Pages are cut on a sync_xid
  -- boundary: a transaction's changes never span two pages, and the first
  -- transaction is always included even if it alone exceeds p_limit.
  execute
    'with snap as (select pg_snapshot_xmin(pg_current_snapshot()) as hi), '
    'ch as (' || v_union ||
    ' union all select ''_tombstone'', s.sync_xid, '
    '  jsonb_build_object(''table'', s.table_name, ''row'', s.row_key) '
    '  from sync_tombstones s '
    '  where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)), '
    'g as (select x, count(*) as c from ch group by x), '
    'cum as (select x, c, sum(c) over (order by x) as run from g), '
    'cut as (select coalesce((select min(x) from cum where run - c > 0 and run > $3), '
    '                        (select hi from snap)) as upper) '
    'select jsonb_build_object('
    '  ''cursor'', (select upper from cut)::text, '
    '  ''has_more'', (select upper from cut) < (select hi from snap), '
    '  ''server_time'', clock_timestamp(), '
    '  ''changes'', coalesce((select jsonb_agg(jsonb_build_object(''t'', t, ''r'', r) order by x) '
    '                         from ch where x < (select upper from cut)), ''[]''::jsonb))'
    into v_out
    using p_arena, p_cursor::xid8, p_limit;
  return v_out;
end;
$function$;

create or replace function public.sync_push (
  p_arena  uuid,
  p_ops    jsonb,
  p_device text  default null::text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_op jsonb; v_id uuid; v_kind text; v_prev sync_ops; v_res jsonb;
  v_out jsonb := '[]'::jsonb;
  v_state text; v_msg text; v_hint text; v_code text;
begin
  -- `not in` is NULL (not true) for a null arena, so test membership explicitly.
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  for v_op in select value from jsonb_array_elements(coalesce(p_ops, '[]'::jsonb)) loop
    v_id := (v_op->>'op_id')::uuid;
    v_kind := v_op->>'kind';
    -- Two pushes of the same op (a retry racing the original) queue here.
    perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));
    select * into v_prev from sync_ops where op_id = v_id;
    if found then
      if v_prev.arena_id <> p_arena then raise exception 'op_id_reused'; end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', v_prev.status, 'result', v_prev.result, 'error', v_prev.error_code,
        'detail', v_prev.error_message, 'replayed', true));
      continue;
    end if;
    begin
      v_res := _sync_apply(p_arena, v_kind, coalesce(v_op->'payload', '{}'::jsonb));
      if v_res is null then raise exception 'unknown_op' using hint = coalesce(v_kind, 'null'); end if;
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, result)
        values (v_id, p_arena, auth.uid(), p_device, v_kind, 'applied', v_res);
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'applied', 'result', v_res, 'replayed', false));
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text,
        v_hint = pg_exception_hint;
      -- Transient (serialization failure, deadlock, lock not available, query
      -- cancelled): not recorded, so the device resends this op and the rest later.
      if v_state in ('40001', '40P01', '55P03', '57014') then
        v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
          'status', 'retry', 'error', v_state));
        exit;
      end if;
      -- Stable error code for the device: a plain `raise exception '<code>'`
      -- (P0001) passes its message through; known SQLSTATEs are mapped.
      v_code := case
        when v_state = '42501' then 'forbidden'
        when v_state = '23505' then 'duplicate'
        when v_state = '23503' then 'missing_reference'
        when v_state in ('23514', '23502') then 'invalid'
        when v_state like '22%' then 'invalid_payload'
        when v_state = 'P0001' then v_msg
        else 'server_error' end;
      insert into sync_ops(op_id, arena_id, user_id, device_id, kind, status, error_code, error_message)
        values (v_id, p_arena, auth.uid(), p_device, coalesce(v_kind, '?'), 'rejected', v_code,
          coalesce(v_hint, v_msg));
      v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
        'status', 'rejected', 'error', v_code, 'detail', coalesce(v_hint, v_msg), 'replayed', false));
    end;
  end loop;
  return jsonb_build_object('results', v_out, 'server_time', clock_timestamp());
end;
$function$;

comment on column "public"."activities"."active" is 'App-side flag for retiring an activity without deleting it. Not consulted server-side: the pricing snapshot includes inactive activities.';

comment on column "public"."activities"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."activities"."code" is 'Stable business code, unique per arena (e.g. PS5). Segments, assignments, rates and pricing snapshots reference activities by this code.';

comment on column "public"."activities"."duration_model" is 'How time is billed: hourly (by time, per billing_policies.billing_unit), unit (whole units of rates.unit_minutes, per billing_policies.vr_unit_rounding) or flat_hourly (priced like hourly by the server pricer).';

comment on column "public"."activities"."happy_hour_eligible" is 'When false the happy-hour band never applies; the whole session is priced at the standard band.';

comment on column "public"."activities"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."activities"."uses_controllers" is 'True when sessions of this activity hold physical controllers (pads), so controller counts, allocations and borrowing apply.';

comment on column "public"."activities"."uses_games" is 'True when a game is picked for sessions of this activity (app flag; not checked server-side).';

comment on column "public"."arenas"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."arenas"."timezone" is 'IANA time zone name of the centre. Informational: server pricing uses a fixed Asia/Kolkata +05:30 offset and does not read this column.';

comment on column "public"."audit_log"."action" is 'What happened, e.g. void or duplicate_phone_on_sync.';

comment on column "public"."audit_log"."after" is 'Relevant state after the action, if recorded (e.g. the clashing phone and existing customer id).';

comment on column "public"."audit_log"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."audit_log"."before" is 'Relevant state before the action, if recorded.';

comment on column "public"."audit_log"."created_by" is 'auth.users id of the staff member whose sync op caused the entry.';

comment on column "public"."audit_log"."entity_id" is 'Id of the row acted on (no FK; entity_type names its table).';

comment on column "public"."audit_log"."entity_type" is 'Kind of row acted on, e.g. session, group_session, customer.';

comment on column "public"."audit_log"."reason" is 'Human reason (the owner''s void reason, or a system explanation).';

comment on column "public"."billing_policies"."active" is 'Only active rows are considered; the oldest active one (by created_at) is used.';

comment on column "public"."billing_policies"."allow_extend_past_close" is 'When false an extension stops at closing time (applied by the app''s session planner).';

comment on column "public"."billing_policies"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."billing_policies"."billing_unit" is 'per_minute (prorated by the second), or block_15 / block_30 / block_60 (billed minutes rounded to the block per block_rounding). Ignored for unit-model activities.';

comment on column "public"."billing_policies"."block_rounding" is 'How billed minutes are rounded to a block: up or nearest.';

comment on column "public"."billing_policies"."cleaning_gap_minutes" is 'Minutes a resource is held free after a session ends. Stored setting; not enforced server-side.';

comment on column "public"."billing_policies"."early_exit" is 'If a customer leaves early, bill the time actually played (actual) or the full booked duration (planned). Snapshotted with the policy; not applied by the server pricer.';

comment on column "public"."billing_policies"."grace_minutes" is 'Play of this many minutes or less is free (checked per priced interval).';

comment on column "public"."billing_policies"."group_billing_mode" is 'per_system (each system billed at its own controller count) or shared_controller_pool (the group''s purchased controller count priced once over the group window).';

comment on column "public"."billing_policies"."late_arrival" is 'Bill a late arrival from the actual or the planned start. Snapshotted with the policy; not applied by the server pricer.';

comment on column "public"."billing_policies"."minimum_charge_minutes" is 'Shortest billable time: shorter play is billed as if it lasted this many minutes.';

comment on column "public"."billing_policies"."money_rounding_dir" is 'Direction of the final cash rounding: nearest or up.';

comment on column "public"."billing_policies"."money_rounding_paise" is 'Final cash total is rounded to a multiple of this many paise (100 = 1 rupee); 1 or less means no rounding.';

comment on column "public"."billing_policies"."payment_timing" is 'When payment may be recorded: either, start or end. Snapshotted with the policy; not enforced server-side.';

comment on column "public"."billing_policies"."rounding_scope" is 'Where price math is rounded to whole paise: once on the session total (session) or separately for each segment (segment).';

comment on column "public"."billing_policies"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."billing_policies"."vr_unit_rounding" is 'For unit-model activities: round played time up to whole units, to the nearest unit, or prorate.';

comment on column "public"."bookings"."activity_id" is 'Reserved activity (uuid; ops resolve it from the activity code the device sends).';

comment on column "public"."bookings"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."bookings"."controller_requirement" is 'Number of controllers requested, if stated.';

comment on column "public"."bookings"."customer_id" is 'Registered customer, if any; a walk-in reservation may use party_name / phone instead.';

comment on column "public"."bookings"."party_name" is 'Name for a walk-in reservation with no customer record yet.';

comment on column "public"."bookings"."phone" is 'Contact phone for the reservation.';

comment on column "public"."bookings"."players_required" is 'Number of players expected, if stated.';

comment on column "public"."bookings"."reminder_status" is 'Device reminder state: scheduled, off (silenced), missed (lead time already passed when booked) or done (nothing pending). Set from the device at create; no op changes it afterwards.';

comment on column "public"."bookings"."resource_id" is 'Reserved station; null = no specific station (no overlap check).';

comment on column "public"."bookings"."scheduled_end" is 'Reserved window end (UTC); after scheduled_start.';

comment on column "public"."bookings"."scheduled_start" is 'Reserved window start (UTC).';

comment on column "public"."bookings"."status" is 'booked (open; editable), checked_in (a session started from it), cancelled or no_show.';

comment on column "public"."bookings"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor and the base_version for stale-edit checks.';

comment on column "public"."controller_allocations"."activity_code" is 'Activity business code of the play the pad was used for.';

comment on column "public"."controller_allocations"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."controller_allocations"."assignment_id" is 'Group assignment the pad belongs to (scope group); closed with it.';

comment on column "public"."controller_allocations"."created_by" is 'auth.users id of the staff member whose sync op allocated the pad.';

comment on column "public"."controller_allocations"."ended_at" is 'When the pad was released (UTC); null = still in use.';

comment on column "public"."controller_allocations"."group_id" is 'Group session holding the pad (scope group).';

comment on column "public"."controller_allocations"."player_label" is 'Group player''s display name at allocation time (scope group).';

comment on column "public"."controller_allocations"."player_number" is 'Group player number holding the pad (scope group).';

comment on column "public"."controller_allocations"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."controller_allocations"."resource_id" is 'Station where the pad is used; may differ from the pad''s home after a borrow.';

comment on column "public"."controller_allocations"."scope" is 'single (session_id + segment_id set) or group (group_id + assignment_id + player_number set).';

comment on column "public"."controller_allocations"."segment_id" is 'Session segment the pad belongs to (scope single); closed with it.';

comment on column "public"."controller_allocations"."session_id" is 'Single session holding the pad (scope single).';

comment on column "public"."controller_allocations"."started_at" is 'When the pad was handed out (UTC; the segment / assignment start).';

comment on column "public"."controller_allocations"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."controller_moves"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."controller_moves"."created_by" is 'auth.users id of the staff member whose sync op moved the pad.';

comment on column "public"."controller_moves"."from_resource_id" is 'Station the pad actually was at (not necessarily its home).';

comment on column "public"."controller_moves"."kind" is 'loan (pad owes a return to its home), permanent (to_resource_id becomes its new home) or returnHome (back to its home; loan cleared).';

comment on column "public"."controller_moves"."moved_at" is 'When the pad was carried (UTC), as reported by the device (or the server time if none was sent).';

comment on column "public"."controller_moves"."session_ref" is 'For a loan, the borrowing session as app text ''s:<session id>'' or ''g:<group id>'' (not an FK); null otherwise.';

comment on column "public"."controller_moves"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."controller_moves"."to_resource_id" is 'Station the pad was carried to.';

comment on column "public"."controllers"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."controllers"."current_resource_id" is 'Station where the pad physically is now; equals home_resource_id unless it has been moved.';

comment on column "public"."controllers"."home_resource_id" is 'Station the pad belongs to and is returned to. Changed only by a permanent move (re-homing, needs settings).';

comment on column "public"."controllers"."label" is 'The marking on the pad (e.g. HEX-1), which staff use to find it.';

comment on column "public"."controllers"."loan_return_to" is 'Set while the pad is on loan away from home: the home station id (uuid as text) it must go back to; null otherwise.';

comment on column "public"."controllers"."loan_session_ref" is 'Set while on loan: the session that owes the return, as s:<sessionId> or g:<groupId> (app reference string, not a foreign key).';

comment on column "public"."controllers"."notes" is 'Why the pad is in its current status (e.g. stick drift).';

comment on column "public"."controllers"."status" is 'One of usable, faulty, missing, retired, unavailable. Only usable pads count as free and can be borrowed or allocated. While the arena has any non-retired pad, count-only starts are checked against free pads at the station (_inventory_tracked).';

comment on column "public"."controllers"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."customers"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."customers"."is_guest" is 'True for a walk-in started without registering: one record per visit, kept out of the members directory.';

comment on column "public"."customers"."last_visit_at" is 'Start time of the customer''s latest session or group session (UTC); set by op_session_start / op_group_create.';

comment on column "public"."customers"."phone" is 'Contact number, trimmed; null when unknown. Unique per arena when set (ux_customer_phone).';

comment on column "public"."customers"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull. Also the base_version a device sends with customer.update.';

comment on column "public"."game_categories"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."game_categories"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."game_controls"."action" is 'What the player does (e.g. Shoot, Sprint).';

comment on column "public"."game_controls"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."game_controls"."buttons" is 'Controller button names that perform the action, in order (e.g. {CIRCLE}). Free text.';

comment on column "public"."game_controls"."image_url" is 'Optional URL of an illustration for the action.';

comment on column "public"."game_controls"."section" is 'Group heading within the guide (e.g. Attacking, Defending).';

comment on column "public"."game_controls"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."game_resources"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."game_resources"."notes" is 'Staff note explaining the status (e.g. why it is not playable).';

comment on column "public"."game_resources"."status" is 'One of playable, not_playable, not_installed, maintenance, temporarily_unavailable. Anything but playable (or a missing row) blocks the game on that resource.';

comment on column "public"."game_resources"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."games"."active" is 'False retires the title from selection without deleting it (game.set_active).';

comment on column "public"."games"."aliases" is 'Alternative names used for search (e.g. FIFA for EA SPORTS FC 25).';

comment on column "public"."games"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."games"."category_id" is 'Optional game_categories row; set to null if the category is deleted.';

comment on column "public"."games"."last_played_at" is 'Start time (UTC) of the latest session segment or group placement on this game.';

comment on column "public"."games"."max_local_players" is 'Most players (controllers) one system may use at once on this title, 1-8. Starts, reconfigures and group placements above it are refused with players_exceeded.';

comment on column "public"."games"."platforms" is 'Platform tags the title runs on (e.g. PS5, PSVR2). Free text; not validated.';

comment on column "public"."games"."player_mode" is 'One of single, local (local multiplayer), online (online multiplayer), both (local and online).';

comment on column "public"."games"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."group_assignments"."activity_code" is 'Activity business code (not uuid), tied to the arena''s catalog by the composite FK.';

comment on column "public"."group_assignments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_assignments"."controller_count" is 'Controllers this player uses (1 to 4); equals the number of allocated pads when pads are tracked. Null when not applicable.';

comment on column "public"."group_assignments"."ended_at" is 'When the player left this station (UTC); null = the open assignment.';

comment on column "public"."group_assignments"."idx" is '0-based position of this assignment in the player''s own history (each switch or re-add + 1).';

comment on column "public"."group_assignments"."player_label" is 'Display name for the player; carried over on a switch.';

comment on column "public"."group_assignments"."player_number" is 'Player''s number within the group (> 0); stable across switches.';

comment on column "public"."group_assignments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_assignments"."resource_id" is 'Station the player is on.';

comment on column "public"."group_assignments"."started_at" is 'When the player started on this station (UTC), as reported by the device.';

comment on column "public"."group_assignments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_charges"."amount_paise" is 'Line amount in integer paise before bill-level cash rounding; the group total is group_sessions.billed_amount_paise.';

comment on column "public"."group_charges"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_charges"."assignment_id" is 'Assignment billed by this line when exactly one player was on the station for it; null for shared or pooled lines.';

comment on column "public"."group_charges"."band_code" is 'Price band: standard or happy (happy hour).';

comment on column "public"."group_charges"."billed_minutes" is 'Minutes charged after billing-unit / block rounding (or units x unit_minutes for unit-priced activities).';

comment on column "public"."group_charges"."charge_index" is '0-based ordinal of this line within the group''s bill.';

comment on column "public"."group_charges"."controller_count" is 'Controller count the rate was looked up for (combined per station, or the purchased count for the pooled line).';

comment on column "public"."group_charges"."played_minutes" is 'Whole minutes actually played inside this interval.';

comment on column "public"."group_charges"."player_number" is 'That player''s number when the line belongs to one player; otherwise null.';

comment on column "public"."group_charges"."resource_id" is 'Station billed; null for the pooled-controller line.';

comment on column "public"."group_charges"."segment_end" is 'End of the billed interval (UTC); can extend past the actual end when the minimum charge applies.';

comment on column "public"."group_charges"."segment_start" is 'Start of the billed interval (UTC).';

comment on column "public"."group_charges"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_charges"."unit_minutes" is 'Length in minutes of the rate''s pricing unit that unit_price_paise buys.';

comment on column "public"."group_charges"."unit_price_paise" is 'Rate price per unit_minutes, in integer paise, from the group''s pricing_snapshot.';

comment on column "public"."group_extensions"."added_amount_paise" is 'Extra cost in integer paise: server group subtotal at new_end_at minus subtotal at old_end_at; a mismatch refuses the op.';

comment on column "public"."group_extensions"."added_minutes" is 'Minutes added, as sent by the device (> 0).';

comment on column "public"."group_extensions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_extensions"."created_by" is 'auth.users id of the staff member whose sync op extended the group.';

comment on column "public"."group_extensions"."new_end_at" is 'Group scheduled_end_at after this extension (UTC).';

comment on column "public"."group_extensions"."old_end_at" is 'Group scheduled_end_at before this extension (UTC); must match the server''s value or the op is refused as stale.';

comment on column "public"."group_extensions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_extensions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_payments"."amount_paise" is 'Signed integer paise: positive for a payment, negative for a refund, never zero.';

comment on column "public"."group_payments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_payments"."created_by" is 'auth.users id of the staff member whose sync op recorded the payment.';

comment on column "public"."group_payments"."is_refund" is 'True for a refund; must agree with the sign of amount_paise (payments.kind is the single-session equivalent).';

comment on column "public"."group_payments"."method" is 'cash, upi, card or other.';

comment on column "public"."group_payments"."note" is 'Free-text staff note.';

comment on column "public"."group_payments"."reason" is 'Why the refund was given; required when is_refund.';

comment on column "public"."group_payments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_payments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_sessions"."actual_ended_at" is 'When the group actually ended (UTC); null while active.';

comment on column "public"."group_sessions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."group_sessions"."billed_amount_paise" is 'Final bill in integer paise after cash rounding; null until ended. Must equal the server''s re-pricing exactly.';

comment on column "public"."group_sessions"."billing_mode" is 'per_system (each station billed at its own controller count) or shared_controller_pool (purchased controllers billed once over the window); must equal the snapshot policy''s group_billing_mode.';

comment on column "public"."group_sessions"."created_by" is 'auth.users id of the staff member whose sync op created the group.';

comment on column "public"."group_sessions"."payment_status" is 'unpaid, partial, paid or waived; recomputed from group_payments against billed_amount_paise. waived is sticky.';

comment on column "public"."group_sessions"."player_count" is 'Number of players in the party (> 0), as declared at create.';

comment on column "public"."group_sessions"."policy_snapshot" is 'The billing policy part of pricing_snapshot (pricing_snapshot->''policy''), stored separately at create.';

comment on column "public"."group_sessions"."pricing_snapshot" is 'Immutable copy of the arena''s price list frozen at create; must match the current catalog or one retired within 72 h (_assert_snapshot). Every bill and extension is priced from it.';

comment on column "public"."group_sessions"."primary_customer_id" is 'Lead customer of the group; op_group_create records the visit on this customer.';

comment on column "public"."group_sessions"."purchased_controller_count" is
  'Controllers bought for the whole window in shared_controller_pool mode (staff''s declaration); 0 otherwise.';

comment on column "public"."group_sessions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."group_sessions"."scheduled_end_at" is 'Planned end of the shared countdown (UTC); moved by group_extensions.';

comment on column "public"."group_sessions"."started_at" is 'Group start (UTC), as reported by the device.';

comment on column "public"."group_sessions"."status" is 'active, completed (ended and billed by op_group_end) or voided (owner void; row kept).';

comment on column "public"."group_sessions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."group_sessions"."void_reason" is 'Reason given by the owner when voiding; also written to audit_log.';

comment on column "public"."holidays"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."holidays"."closed" is 'True when the arena is closed that day (listed in the snapshot''s closed_days); false = open, but without happy hour.';

comment on column "public"."holidays"."day" is 'Business calendar day in Asia/Kolkata (IST); unique per arena.';

comment on column "public"."holidays"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."payments"."amount_paise" is 'Signed integer paise: positive for a payment, negative for a refund, never zero.';

comment on column "public"."payments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."payments"."created_by" is 'auth.users id of the staff member whose sync op recorded the payment.';

comment on column "public"."payments"."kind" is 'payment or refund; must agree with the sign of amount_paise.';

comment on column "public"."payments"."method" is 'cash, upi, card or other.';

comment on column "public"."payments"."note" is 'Free-text staff note.';

comment on column "public"."payments"."reason" is 'Why the refund was given; required when kind = refund.';

comment on column "public"."payments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."payments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."pricing_catalog_history"."arena_id" is 'Owning arena (tenant). No client access: RLS is enabled with no policy and grants are revoked.';

comment on column "public"."pricing_catalog_history"."canon" is 'The retired price list in _pricing_canon form (rates, activities, policy, hours, holidays, closed_days), compared for equality with a device snapshot.';

comment on column "public"."pricing_catalog_history"."canon_md5" is 'md5 of canon::text (generated). Part of the primary key; lookups match it and then compare canon itself.';

comment on column "public"."pricing_catalog_history"."retired_at" is 'When the list was last replaced (statement time); entries older than _pricing_grace() are no longer accepted.';

comment on column "public"."rate_bands"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."rate_bands"."code" is 'Band code, unique per arena; the pricer selects standard or happy. Any other code is stored but never chosen.';

comment on column "public"."rate_bands"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp). The table is not in the sync_pull feed; devices see band codes through sync_v_rates.';

comment on column "public"."rate_cards"."active" is 'Only rates on active cards are synced (sync_v_rates) and priced (_pricing_snapshot).';

comment on column "public"."rate_cards"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."rate_cards"."effective_from" is 'When the card takes effect (UTC); the newest active card is the one rate.upsert / rate.delete edit.';

comment on column "public"."rate_cards"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp). The table is not in the sync_pull feed; devices see cards only through sync_v_rates.';

comment on column "public"."rates"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."rates"."band_id" is 'Time band the price applies in (rate_bands, e.g. standard or happy). A happy-hour period with no happy rate falls back to the standard rate.';

comment on column "public"."rates"."controller_count" is 'Number of controllers the price is for (e.g. PS5 with 1-4 pads); null = the price does not depend on controllers. Matched exactly, null to null.';

comment on column "public"."rates"."price_paise" is 'Price in integer paise (1/100 rupee) per unit_minutes; >= 0.';

comment on column "public"."rates"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull (via sync_v_rates).';

comment on column "public"."rates"."unit_minutes" is 'Length in minutes of the unit that price_paise buys (> 0). For unit-model activities (e.g. VR) it is the sold unit; otherwise price is prorated per this many minutes.';

comment on column "public"."resource_activities"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."resource_activities"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."resources"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."resources"."current_mode" is 'Activity code the resource is locked to (e.g. a PS5/VR station in VR mode); null = not mode-locked. Starts for another activity are refused (_mode_ok); changed by resource.set_mode only while nothing is open on it.';

comment on column "public"."resources"."kind" is 'One of station, table, room.';

comment on column "public"."resources"."name" is 'Display name, unique within the arena (e.g. HEX, Pool Table 1).';

comment on column "public"."resources"."status" is 'One of available, maintenance, temporarily_unavailable, disabled. Set by resource.upsert / resource.set_status.';

comment on column "public"."resources"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."session_charges"."amount_paise" is 'Line amount in integer paise before bill-level cash rounding; the session total is sessions.billed_amount_paise.';

comment on column "public"."session_charges"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."session_charges"."band_code" is 'Price band: standard or happy (happy hour).';

comment on column "public"."session_charges"."billed_minutes" is 'Minutes charged after billing-unit / block rounding (or units x unit_minutes for unit-priced activities).';

comment on column "public"."session_charges"."controller_count" is 'Controller count the rate was looked up for (copied from the segment).';

comment on column "public"."session_charges"."played_minutes" is 'Whole minutes actually played inside this interval.';

comment on column "public"."session_charges"."resource_id" is 'Station of that segment.';

comment on column "public"."session_charges"."segment_end" is 'End of the billed band interval (UTC); can extend past the actual end when the minimum charge applies.';

comment on column "public"."session_charges"."segment_id" is 'Segment this line was priced from.';

comment on column "public"."session_charges"."segment_index" is '0-based ordinal of this charge line within the session''s bill (one segment can yield several lines); not session_segments.idx.';

comment on column "public"."session_charges"."segment_start" is 'Start of the billed band interval (UTC).';

comment on column "public"."session_charges"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."session_charges"."unit_minutes" is 'Length in minutes of the rate''s pricing unit that unit_price_paise buys.';

comment on column "public"."session_charges"."unit_price_paise" is 'Rate price per unit_minutes, in integer paise, from the session''s pricing_snapshot.';

comment on column "public"."session_extensions"."added_amount_paise" is 'Extra cost in integer paise: server quote at new_end_at minus quote at old_end_at on the session''s pricing_snapshot; a mismatch refuses the op.';

comment on column "public"."session_extensions"."added_minutes" is 'Minutes added, as sent by the device (> 0).';

comment on column "public"."session_extensions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."session_extensions"."created_by" is 'auth.users id of the staff member whose sync op extended the session.';

comment on column "public"."session_extensions"."new_end_at" is 'Session scheduled_end_at after this extension (UTC).';

comment on column "public"."session_extensions"."old_end_at" is 'Session scheduled_end_at before this extension (UTC); must match the server''s value or the op is refused as stale.';

comment on column "public"."session_extensions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."session_extensions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."session_segments"."activity_code" is 'Activity business code (not uuid), tied to the arena''s catalog by the composite FK; selects the rate from the session''s pricing_snapshot.';

comment on column "public"."session_segments"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."session_segments"."controller_count" is 'Controllers in use on the station (1 to 4, the port capacity); selects the controller-count rate. Null when not applicable.';

comment on column "public"."session_segments"."ended_at" is 'Segment end (UTC); null = the open segment.';

comment on column "public"."session_segments"."idx" is '0-based position of the segment within its session (start = 0, each reconfigure + 1); unique per session.';

comment on column "public"."session_segments"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."session_segments"."resource_id" is 'Station (resource) played on during this segment.';

comment on column "public"."session_segments"."started_at" is 'Segment start (UTC), as reported by the device.';

comment on column "public"."session_segments"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."sessions"."actual_ended_at" is 'When play actually ended (UTC); null while active. Billing uses actual time.';

comment on column "public"."sessions"."arena_id" is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column "public"."sessions"."billed_amount_paise" is 'Final bill in integer paise after cash rounding; null until ended. op_session_end refuses it unless it equals the server''s own re-pricing exactly.';

comment on column "public"."sessions"."booking_id" is 'Booking checked in by this session (op_session_start sets the booking to checked_in), if any.';

comment on column "public"."sessions"."created_by" is 'auth.users id of the staff member whose sync op started the session.';

comment on column "public"."sessions"."payment_status" is 'unpaid, partial, paid or waived; recomputed from payments against billed_amount_paise by op_session_end / op_payment. waived is sticky.';

comment on column "public"."sessions"."policy_snapshot" is 'The billing policy part of pricing_snapshot (pricing_snapshot->''policy''), stored separately at start.';

comment on column "public"."sessions"."pricing_snapshot" is 'Immutable copy of the arena''s price list (rates, activities, policy, holidays) frozen at start. Must match the arena''s current catalog or one retired within 72 h (_assert_snapshot); every bill and extension is priced from it.';

comment on column "public"."sessions"."request_id" is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column "public"."sessions"."scheduled_end_at" is 'Planned end of the countdown (UTC); moved forward by each session_extensions row.';

comment on column "public"."sessions"."started_at" is 'Device-reported start instant (UTC); the server trusts session times and validates only their order.';

comment on column "public"."sessions"."status" is 'active (running), completed (ended and billed by op_session_end) or voided (owner void; row kept).';

comment on column "public"."sessions"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

comment on column "public"."sessions"."void_reason" is 'Reason given by the owner when voiding; also written to audit_log.';

comment on column "public"."settings"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."settings"."json" is 'Setting value. business_hours: {"open": {...}, "happy": {...}}, each keyed by ISO weekday "1" (Monday) to "7", value {"start": m, "end": m} in minutes after IST midnight, or null when closed / no happy hour.';

comment on column "public"."settings"."key" is 'Setting name, unique per arena. Writable: business_hours.';

comment on column "public"."settings"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."staff_profiles"."active" is 'False revokes all access server-side: app_arena_ids and the permission helpers only consider active rows.';

comment on column "public"."staff_profiles"."arena_id" is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column "public"."staff_profiles"."perms" is 'Permission codes from _known_perms(): start, bill, discount, members, stations, money, reports, settings. Holding money or reports makes the member owner level (app_is_owner).';

comment on column "public"."staff_profiles"."role" is '''owner'' or ''staff''. An owner implicitly holds every permission (app_has_perm); op_staff_update keeps an owner''s perms complete and the row active.';

comment on column "public"."staff_profiles"."sync_xid" is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

comment on column "public"."staff_profiles"."user_id" is 'The Supabase Auth login (auth.users.id) this profile belongs to.';

comment on column "public"."sync_ops"."arena_id" is 'Arena the op was pushed to.';

comment on column "public"."sync_ops"."created_at" is 'Server receipt time of the op; audit evidence independent of device clocks.';

comment on column "public"."sync_ops"."device_id" is 'Device identifier passed to sync_push, if any.';

comment on column "public"."sync_ops"."error_code" is 'Stable refusal code when rejected (the op''s raised message, e.g. stale or price_mismatch, or a mapped class such as forbidden / duplicate / invalid).';

comment on column "public"."sync_ops"."error_message" is 'Refusal detail when rejected (exception hint, else message).';

comment on column "public"."sync_ops"."kind" is 'Op kind dispatched by _sync_apply, e.g. session.start, payment.record; ? if missing.';

comment on column "public"."sync_ops"."op_id" is 'Device-generated op id (outbox key); primary key, so an op is applied at most once. Reuse under another arena raises op_id_reused.';

comment on column "public"."sync_ops"."result" is 'The op function''s jsonb result when applied; replayed verbatim on a re-push.';

comment on column "public"."sync_ops"."status" is 'applied or rejected. Retryable failures are never recorded.';

comment on column "public"."sync_ops"."user_id" is 'auth.uid() of the signed-in member who pushed the op (no FK).';

comment on column "public"."sync_tombstones"."arena_id" is 'Arena of the deleted row (no FK, so tombstones outlive the arena row).';

comment on column "public"."sync_tombstones"."deleted_at" is 'Server time of the delete.';

comment on column "public"."sync_tombstones"."id" is 'Insertion-order surrogate key (sequence sync_tombstones_id_seq); the feed orders by sync_xid, not id.';

comment on column "public"."sync_tombstones"."row_key" is 'The whole deleted row as jsonb (to_jsonb(old)); the device picks the key it stores that table''s rows under.';

comment on column "public"."sync_tombstones"."sync_xid" is 'Id of the deleting transaction; places the tombstone in the sync_pull change-feed window.';

comment on column "public"."sync_tombstones"."table_name" is 'Name of the table the row was deleted from (trigger tg_table_name).';

comment on function "public"."_active_card"(uuid) is 'Returns the arena''s active rate card id, creating a card named Current when none is active.';

comment on function "public"."_activity_id"(uuid, text) is 'Resolves an activity code to its id within an arena, raising activity_missing when absent.';

comment on function "public"."_assert_known_perms"(text[]) is 'Internal: raise invalid_permission if the array contains a code outside _known_perms(); null or empty is accepted.';

comment on function "public"."_assert_same_arena"() is 'Trigger (t_same_arena): for each (column, table) pair given as trigger arguments, refuse a reference to a row of another arena with cross_arena_reference.';

comment on function "public"."_assert_settings_holder"(uuid) is 'Internal: raise last_settings_holder unless at least one active profile in the arena is an owner or holds the settings permission.';

comment on function "public"."_assert_snapshot"(uuid, jsonb) is 'Pricing: raises pricing_snapshot_mismatch unless a device snapshot equals the arena''s live or recently retired price list.';

comment on function "public"."_band_id"(uuid, text) is 'Resolves a rate band code to its id within an arena, creating the band when absent.';

comment on function "public"."_booking_free"(uuid, uuid, uuid, timestamp with time zone, timestamp
  with time zone) is 'Locks a station and raises booking_conflict if another open booking overlaps the given window.';

comment on function "public"."_free_pads_at"(uuid, uuid) is 'Counts usable, unallocated controllers currently at a station.';

comment on function "public"."_game_max_players"(uuid) is 'Returns a game''s max local players, defaulting to 1.';

comment on function "public"."_game_playable"(uuid, uuid) is 'Raises not_playable unless the game is installed and playable on the station (no-op without a game).';

comment on function "public"."_group_active"(uuid, uuid) is 'Locks a group session row and raises not_found or not_active unless it is active.';

comment on function
  "public"."_group_assignable"(uuid, uuid, uuid, text, uuid, integer, integer, integer, integer) is
  'Raises unless a group player can be placed on the station with the requested activity, game and controllers.';

comment on function "public"."_group_lock"(uuid, jsonb, uuid[]) is 'Locks all stations, then all pads, involved in a group op in a fixed order; raises retry if a borrowed pad moved meanwhile.';

comment on function "public"."_group_place"(uuid, uuid, jsonb, timestamp
  with time zone, integer, integer) is 'Validates and inserts one group assignment, borrowing and allocating its pads; returns the count of skipped pad moves.';

comment on function "public"."_inventory_tracked"(uuid) is 'True when the arena has at least one non-retired controller.';

comment on function "public"."_jsonb_uuids"(jsonb) is 'Internal: convert a jsonb array of uuid strings to uuid[] (empty array for null).';

comment on function "public"."_known_perms"() is 'The eight permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings.';

comment on function "public"."_lock_pads"(uuid, uuid[]) is 'Locks the given controller rows in id order (always after the stations).';

comment on function "public"."_lock_resources"(uuid, uuid[]) is 'Locks the given station (resource) rows in id order (always before the pads).';

comment on function "public"."_mode_ok"(uuid, uuid, text) is 'Raises mode_locked when the station is locked to a different activity mode.';

comment on function "public"."_need"(uuid, text) is 'Internal guard for op_* functions: raise forbidden (42501) unless the signed-in user holds the permission in the arena.';

comment on function
  "public"."_pad_allocate"(uuid, jsonb, text, uuid, uuid, uuid, uuid, integer, text, uuid, text,
  uuid, timestamp with time zone) is 'Validates and inserts controller allocations for a session segment or group assignment.';

comment on function "public"."_pad_borrow"(uuid, jsonb, uuid, text, timestamp
  with time zone) is 'Moves pads to a station for a session or group, recording loans and returns home; returns how many were already there.';

comment on function "public"."_pad_ids"(jsonb) is 'Extracts controller_id values from a jsonb array as uuid[].';

comment on function "public"."_pad_origins"(uuid, uuid[]) is 'Distinct current stations of the given controllers.';

comment on function "public"."_payment_status"(bigint, bigint) is 'Internal: paid / partial / unpaid from billed and paid amounts in paise; a null billed amount gives partial or unpaid.';

comment on function "public"."_pr_ceil_step"(bigint, integer) is 'Pricing: smallest multiple of step that is >= v (v unchanged when step <= 1); port of Dart ceilToStep.';

comment on function "public"."_pr_charge_key"(text, uuid, integer, text, timestamp
  with time zone,
  timestamp with time zone, bigint, bigint, integer, bigint, bigint) is 'Pricing: text key of a charge row''s money-relevant fields, used to compare device and server charge rows as multisets.';

comment on function "public"."_pr_div"(bigint, bigint) is 'Pricing: integer division n / d rounded half up; port of Dart roundDivHalfUp.';

comment on function "public"."_pr_group_bill"(uuid, timestamp
  with time zone) is 'Pricing: server-side bill of a group session (per-system sweeps or a shared controller pool); port of GroupBilling.bill.';

comment on function "public"."_pr_happy"(jsonb, date) is 'Pricing: happy-hour range of one IST day under a snapshot, null on holidays, closed days or no window; port of BusinessCalendar.happyWindow.';

comment on function "public"."_pr_ist_date"(timestamp with time zone) is 'Pricing: IST (fixed +05:30) business date of a UTC instant; port of Dart IstDate.fromUtc.';

comment on function "public"."_pr_keys"(jsonb, text, uuid, integer) is 'Pricing: _pr_charge_key of every line of a quote.';

comment on function "public"."_pr_money"(bigint, integer, text) is 'Pricing: cash-rounds a paise amount to step, up or to nearest; port of Dart applyMoneyRounding.';

comment on function "public"."_pr_policy"(jsonb) is 'Pricing: billing policy of a snapshot merged over the Dart BillingPolicy.defaults.';

comment on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
  with time zone) is 'Pricing: quotes one interval for one activity and controller count on a snapshot (lines, subtotal, cash-rounded amount); port of PricingService.quote.';

comment on function "public"."_pr_rate"(jsonb, text, text, integer) is 'Pricing: first rate in a snapshot matching activity, band and controller count exactly; port of PricingSnapshot.rateFor.';

comment on function "public"."_pr_round_step"(bigint, integer) is 'Pricing: nearest multiple of step to v, ties up (v unchanged when step <= 1); port of Dart roundToStep.';

comment on function "public"."_pr_secs"(timestamp with time zone, timestamp
  with time zone) is 'Pricing: whole seconds between two instants, truncated (Dart Duration.inSeconds).';

comment on function "public"."_pr_session_bill"(uuid, timestamp
  with time zone) is 'Pricing: server-side bill of a single session over all its segments on its frozen snapshot; port of SegmentBilling.bill.';

comment on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp
  with time zone, boolean) is 'Pricing: sweeps one station''s group assignments into constant-controller stretches and quotes each; port of GroupBilling sweepResource.';

comment on function "public"."_price_mismatch"(text, bigint, bigint) is 'Raises price_mismatch with a hint comparing the server and device amounts in paise.';

comment on function "public"."_pricing_canon"(jsonb) is 'Pricing: canonical form of a snapshot (sorted, defaults filled, card name dropped) for equality checks.';

comment on function "public"."_pricing_grace"() is 'Pricing: window (72 hours) during which a retired price list is still accepted at session or group start.';

comment on function "public"."_pricing_snapshot"(uuid) is 'Pricing: the arena''s current price list built from its catalog, in the device''s PricingSnapshot JSON shape.';

comment on function "public"."_rupees"(bigint) is 'Internal: format an amount in integer paise as a rupee string (e.g. 30000 -> ₹300.00) for user-facing error hints.';

comment on function "public"."_same_ids"(uuid[], uuid[]) is 'Internal: true when both uuid arrays contain the same distinct ids, ignoring order and duplicates (null is treated as empty).';

comment on function "public"."_seed_arena_catalog"(uuid) is 'Internal: seed a freshly created arena with the default catalog (activities, stations, rates, billing policy, games, controllers, game compatibility). Not idempotent.';

comment on function
  "public"."_single_supply"(uuid, uuid, text, uuid, integer, integer, uuid, integer) is
  'Raises unless the station mode and the requested controllers (pads or a count) are valid for a single session.';

comment on function "public"."_stale"(xid8, text) is 'Internal: true when a non-empty client base_version differs from the row''s current sync_xid (the row changed since the device last saw it).';

comment on function "public"."_station_free_for_single"(uuid) is 'Raises resource_busy when the station has an open session segment or group assignment.';

comment on function "public"."_station_usable"(uuid, uuid) is 'Raises resource_missing or resource_unavailable unless the station exists and is available.';

comment on function "public"."_sync_apply"(uuid, text, jsonb) is 'Internal (sync_push): dispatch one op kind to its op_* function and return its result (null for an unknown kind); archives the previous price list when a pricing op changes it.';

comment on function "public"."_sync_sources"() is 'Internal (sync_pull): list of (table name, source relation) pairs that make up the sync change feed.';

comment on function "public"."_untracked_busy"(uuid, uuid, uuid[]) is 'True when open play at the station uses controllers without any allocated pads.';

comment on function "public"."_usable_pads_at"(uuid, uuid) is 'Counts usable controllers currently at a station, whether allocated or not.';

comment on function "public"."_uses_controllers"(uuid, text) is 'True when the activity uses controllers; false when unknown.';

comment on function "public"."add_staff_by_email"(uuid, text, text, text[]) is
  'Client API (owner level): link an existing login to the arena as a staff profile with the given permissions, reactivating and overwriting an existing staff profile. Refuses owners'' profiles, unknown permissions, and leaving nobody with Settings.';

comment on function "public"."app_arena_ids"() is 'Arena ids where the signed-in user has an active staff profile; the membership test used by RLS policies and the sync RPCs.';

comment on function "public"."app_has_perm"(uuid, text) is 'True when the signed-in user is an active member of the arena and is an owner or holds the given permission.';

comment on function "public"."app_is_owner"(uuid) is 'True when the signed-in user is owner level in the arena: an active profile with role owner, or holding the money or reports permission.';

comment on function "public"."assert_controller_free_for_allocation"() is 'Trigger (controller_allocations): refuse an open allocation for a controller that already has one (controller_taken), serialised by locking the controller row.';

comment on function "public"."assert_resource_free_for_assignment"() is 'Trigger (group_assignments): refuse an open assignment on a station that has an open session segment or an open assignment of another group (resource_busy).';

comment on function "public"."assert_resource_free_for_segment"() is 'Trigger (session_segments): refuse an open segment on a station that already has an open segment or an open group assignment (resource_busy), serialised by locking the station row.';

comment on function "public"."bootstrap_owner"(text, text, text) is 'Operator-only (SQL editor): create a new arena with the default catalog and make an existing, confirmed login its owner. Returns the arena id; each call creates a new arena.';

comment on function "public"."my_arenas"() is 'Client API: the signed-in user''s staff profiles across arenas (including inactive ones) as a jsonb array of {arena_id, arena_name, name, role, perms, active}.';

comment on function "public"."op_booking_create"(uuid, jsonb) is 'Sync op booking.create: creates a booked reservation, refusing an overlap with another open booking on the same station.';

comment on function "public"."op_booking_set_status"(uuid, jsonb) is 'Sync op booking.set_status: cancels an open booking or marks it a no-show; a repeat of the same status is a no-op.';

comment on function "public"."op_booking_update"(uuid, jsonb) is 'Sync op booking.update: edits an open booking, refusing a stale base_version or an overlap with another booking on the station.';

comment on function "public"."op_controller_move"(uuid, jsonb) is 'Sync op controller.move: loans, returns home or permanently re-homes a pad, locking both stations before the pad.';

comment on function "public"."op_controller_set_status"(uuid, jsonb) is 'Sync op controller.set_status: sets a pad''s status and notes.';

comment on function "public"."op_controller_upsert"(uuid, jsonb) is 'Sync op controller.upsert: creates or edits a pad, refusing to relocate one that is in use.';

comment on function "public"."op_customer_create"(uuid, jsonb) is 'Sync op customer.create: registers a customer, keeping the row without its phone when that phone already belongs to someone else.';

comment on function "public"."op_customer_update"(uuid, jsonb) is 'Sync op customer.update: edits a customer, refusing a stale base_version or a phone already in use.';

comment on function "public"."op_game_replace_controls"(uuid, jsonb) is 'Sync op game.replace_controls: replaces the full list of control-guide rows for one game.';

comment on function "public"."op_game_set_active"(uuid, jsonb) is 'Sync op game.set_active: activates or deactivates a game.';

comment on function "public"."op_game_set_compat"(uuid, jsonb) is 'Sync op game.set_compat: upserts the compatibility status of a game on a station (what _game_playable checks).';

comment on function "public"."op_game_upsert"(uuid, jsonb) is 'Sync op game.upsert: creates or edits a catalog game.';

comment on function "public"."op_group_add"(uuid, jsonb) is 'Sync op group.add: adds one player assignment to an active group after re-validating the station and pads.';

comment on function "public"."op_group_create"(uuid, jsonb) is 'Sync op group.create: starts a group session and places every player, then verifies the frozen price list and billing mode.';

comment on function "public"."op_group_end"(uuid, jsonb) is 'Sync op group.end: closes an active group, stores its charges and bill, and refuses unless the server re-prices it to exactly the same money.';

comment on function "public"."op_group_end_player"(uuid, jsonb) is 'Sync op group.end_player: ends one player''s open assignment and releases their pads.';

comment on function "public"."op_group_extend"(uuid, jsonb) is 'Sync op group.extend: moves a group''s scheduled end and verifies the extension price server-side.';

comment on function "public"."op_group_switch"(uuid, jsonb) is 'Sync op group.switch: closes a player''s open assignment and places them on a new station or game.';

comment on function "public"."op_group_void"(uuid, jsonb) is 'Sync op group.void: voids a group session (owner level only), closing open assignments and pads and auditing the reason.';

comment on function "public"."op_holiday_delete"(uuid, jsonb) is 'Sync op holiday.delete: removes the holiday on a given day (idempotent).';

comment on function "public"."op_holiday_upsert"(uuid, jsonb) is 'Sync op holiday.upsert: adds or edits the holiday on a given day.';

comment on function "public"."op_payment"(uuid, jsonb) is 'Sync op payment.record: records a payment or refund on a session or group, refusing overpayment of a final bill or a refund beyond what was paid.';

comment on function "public"."op_policy_save"(uuid, jsonb) is 'Sync op policy.save: overwrites the arena''s active billing policy (creating a default one if missing).';

comment on function "public"."op_rate_delete"(uuid, jsonb) is 'Sync op rate.delete: deletes the active card''s rate for a band, activity and controller count (idempotent).';

comment on function "public"."op_rate_upsert"(uuid, jsonb) is 'Sync op rate.upsert: inserts or updates the active card''s rate for a band, activity and controller count.';

comment on function "public"."op_resource_set_mode"(uuid, jsonb) is 'Sync op resource.set_mode: sets or clears a station''s activity mode lock while it is idle.';

comment on function "public"."set_updated_at"() is 'Trigger (before update): set updated_at to now() unless the update already set it explicitly.';

comment on function "public"."sync_fetch_entity"(uuid, jsonb) is 'Client API (sync): for each {type, id} ref, return the server''s current rows for that whole entity (session, group, controller, customer or booking) so a device can replace its copy after a refused op.';

comment on function "public"."sync_pull"(uuid, text, integer) is 'Client API (sync): one page of the arena''s change feed (changed rows and tombstones) since the given sync_xid cursor, cut on transaction boundaries; returns the next cursor and has_more.';

comment on function "public"."sync_push"(uuid, jsonb, text) is 'Client API (sync): apply a batch of device ops in order, each at most once per op_id (recorded in sync_ops), and return each op''s status: applied, rejected (with error code) or retry.';

comment on function "public"."sync_record_delete"() is 'Trigger (after delete on synced tables): write the deleted row to sync_tombstones so sync_pull can propagate the delete to devices.';

comment on function "public"."sync_stamp"() is 'Trigger (before insert or update on synced tables): set sync_xid to the current transaction id, the row''s change-feed position and version.';

comment on table "public"."activities" is 'Activity types an arena sells (e.g. PS5, VR, POOL, LOUNGE), identified by a per-arena business code; part of the pricing snapshot.';

comment on table "public"."arenas" is 'One gaming centre (tenant). Every arena-scoped row references it via arena_id; created by bootstrap_owner().';

comment on table "public"."audit_log" is 'Append-only audit trail of voids and sync-time data adjustments, per arena. Not part of the sync change feed.';

comment on table "public"."billing_policies" is 'Configurable billing rules for an arena. The oldest active row is the live policy and is captured into every session''s pricing snapshot.';

comment on table "public"."bookings" is 'A reservation of a station and activity for a future time window, checked in when its session starts.';

comment on table "public"."controller_allocations" is 'Append-only per-pad timeline: which physical controller was used by which session segment or group player, where, and when. An open row (ended_at null) means the pad is in a player''s hands.';

comment on table "public"."controller_moves" is 'Append-only history of physical pad carries between stations (loan, permanent re-home, return home).';

comment on table "public"."controllers" is 'Physical controllers (pads): label, home station, current location, condition and any outstanding loan.';

comment on table "public"."customers" is 'Customers of an arena: registered members and per-visit walk-in guest records. Referenced by sessions, groups and bookings.';

comment on table "public"."game_categories" is 'Genre categories used to group an arena''s games; names are unique per arena.';

comment on table "public"."game_controls" is 'Control-guide entries for a game: an action, the buttons that perform it and an optional explanation. Replaced wholesale per game by game.replace_controls.';

comment on table "public"."game_resources" is 'Compatibility matrix: whether a game can be played on a given resource. Only status playable allows a session on that game there.';

comment on table "public"."games" is 'Game titles in an arena''s library, with search aliases, platforms, player limits and an active flag.';

comment on table "public"."group_assignments" is 'Placement of one group player on one station, activity, game and controller count for a stretch of time; the open row is where the player is now.';

comment on table "public"."group_charges" is 'Itemised bill lines of an ended group session, verified against the server''s own re-pricing of the group.';

comment on table "public"."group_extensions" is 'Append-only record of each extension of a group session''s scheduled end, with the extra cost the server verified.';

comment on table "public"."group_payments" is 'Append-only payments and refunds against a group session; their sum is what was collected.';

comment on table "public"."group_sessions" is 'A group session: one shared countdown and one bill over several players, whose station placements are group_assignments.';

comment on table "public"."holidays" is 'Holiday and closure days per arena. Every listed day has no happy hour; closed days are also shut. Part of the pricing snapshot.';

comment on table "public"."payments" is 'Append-only payments and refunds against a single session; their sum is what was collected.';

comment on table "public"."pricing_catalog_history" is 'Price lists retired by a pricing change, kept so a device that went offline holding the old list can still start sessions within the grace window. Server-only.';

comment on table "public"."rate_bands" is 'Pricing time bands per arena, identified by code. The server pricer uses the codes standard and happy.';

comment on table "public"."rate_cards" is 'Named price lists grouping rates. Rates on active cards form the arena''s live price list; ops edit the newest active card.';

comment on table "public"."rates" is 'Prices on a rate card: for an activity, band and optional controller count, price_paise per unit_minutes. Part of the pricing snapshot.';

comment on table "public"."resource_activities" is 'Link table: the activities a resource supports. Replaced wholesale per resource by resource.upsert.';

comment on table "public"."resources" is 'Bookable places on the floor (gaming stations, pool tables, rooms). Sessions, group assignments, bookings and controllers point at them.';

comment on table "public"."session_charges" is 'Itemised bill lines of an ended single session: one row per price band piece of each segment, verified against the server''s own re-pricing.';

comment on table "public"."session_extensions" is 'Append-only record of each extension of a single session''s scheduled end, with the extra cost the server verified.';

comment on table "public"."session_segments" is 'One stretch of a single session on one station, activity, game and controller count. The open segment (ended_at null) is where the session is now; at most one open segment or group assignment per station.';

comment on table "public"."sessions" is 'A single-player session: the parent of its segments, extensions, charges and payments. Holds the frozen price list and, once ended, the bill.';

comment on table "public"."settings" is 'Per-arena key/value settings synced to devices. Currently only business_hours is writable (settings.save).';

comment on table "public"."staff_profiles" is 'Membership of an auth user in an arena: display name, role and permission codes. Active rows grant read access (app_arena_ids) and op_* permissions.';

comment on table "public"."sync_ops" is 'Server-only idempotency ledger for sync_push: one row per device op id with its outcome, replayed on retry. No client grants; RLS on with no policies (deny all).';

comment on table "public"."sync_tombstones" is 'Server-only record of deleted rows from synced tables, served by sync_pull so devices delete them too. No client grants; RLS on with no policies (deny all).';

comment on view "public"."sync_v_arenas" is 'Change-feed source for arenas: the arena row plus arena_id = id so sync_pull can filter it like every other table. Server-only (read by sync_pull).';

comment on view "public"."sync_v_bookings" is 'Change-feed source for bookings: every booking column plus the activity''s business code (activity_code, null when no activity). Server-only (read by sync_pull / sync_fetch_entity).';

comment on view "public"."sync_v_rates" is 'Rates on active rate cards, with activity_code and band code. Change-feed source for rates and the rates section of the server pricing snapshot. Server-only.';

comment on view "public"."sync_v_resource_activities" is 'Change-feed source for resource_activities: each link plus the activity''s business code. Server-only (read by sync_pull).';
