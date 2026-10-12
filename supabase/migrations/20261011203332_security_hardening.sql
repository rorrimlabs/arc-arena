set local check_function_bodies = off;

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from
  "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from
  "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on tables from
  "authenticated";

revoke all on sequence "public"."sync_tombstones_id_seq" from "anon";

revoke all on sequence "public"."sync_tombstones_id_seq" from "authenticated";

revoke all on table "public"."activities" from "anon";

revoke all on table "public"."arenas" from "anon";

revoke all on table "public"."audit_log" from "anon";

revoke all on table "public"."billing_policies" from "anon";

revoke all on table "public"."bookings" from "anon";

revoke all on table "public"."controller_allocations" from "anon";

revoke all on table "public"."controller_moves" from "anon";

revoke all on table "public"."controllers" from "anon";

revoke all on table "public"."customers" from "anon";

revoke all on table "public"."game_categories" from "anon";

revoke all on table "public"."game_controls" from "anon";

revoke all on table "public"."game_resources" from "anon";

revoke all on table "public"."games" from "anon";

revoke all on table "public"."group_assignments" from "anon";

revoke all on table "public"."group_charges" from "anon";

revoke all on table "public"."group_extensions" from "anon";

revoke all on table "public"."group_payments" from "anon";

revoke all on table "public"."group_sessions" from "anon";

revoke all on table "public"."holidays" from "anon";

revoke all on table "public"."payments" from "anon";

revoke all on table "public"."rate_bands" from "anon";

revoke all on table "public"."rate_cards" from "anon";

revoke all on table "public"."rates" from "anon";

revoke all on table "public"."resource_activities" from "anon";

revoke all on table "public"."resources" from "anon";

revoke all on table "public"."session_charges" from "anon";

revoke all on table "public"."session_extensions" from "anon";

revoke all on table "public"."session_segments" from "anon";

revoke all on table "public"."sessions" from "anon";

revoke all on table "public"."settings" from "anon";

revoke all on table "public"."staff_profiles" from "anon";

drop policy "p_ins_activities" on "public"."activities";

drop policy "p_upd_activities" on "public"."activities";

drop policy "p_upd_arenas" on "public"."arenas";

drop policy "p_ins_billing_policies" on "public"."billing_policies";

drop policy "p_upd_billing_policies" on "public"."billing_policies";

drop policy "p_ins_bookings" on "public"."bookings";

drop policy "p_upd_bookings" on "public"."bookings";

drop policy "p_ins_controllers" on "public"."controllers";

drop policy "p_upd_controllers" on "public"."controllers";

drop policy "p_ins_customers" on "public"."customers";

drop policy "p_upd_customers" on "public"."customers";

drop policy "p_ins_game_categories" on "public"."game_categories";

drop policy "p_upd_game_categories" on "public"."game_categories";

drop policy "p_ins_game_controls" on "public"."game_controls";

drop policy "p_upd_game_controls" on "public"."game_controls";

drop policy "p_ins_game_resources" on "public"."game_resources";

drop policy "p_upd_game_resources" on "public"."game_resources";

drop policy "p_ins_games" on "public"."games";

drop policy "p_upd_games" on "public"."games";

drop policy "p_ins_holidays" on "public"."holidays";

drop policy "p_upd_holidays" on "public"."holidays";

drop policy "p_ins_rate_bands" on "public"."rate_bands";

drop policy "p_upd_rate_bands" on "public"."rate_bands";

drop policy "p_ins_rate_cards" on "public"."rate_cards";

drop policy "p_upd_rate_cards" on "public"."rate_cards";

drop policy "p_ins_rates" on "public"."rates";

drop policy "p_upd_rates" on "public"."rates";

drop policy "p_ins_resource_activities" on "public"."resource_activities";

drop policy "p_upd_resource_activities" on "public"."resource_activities";

drop policy "p_ins_resources" on "public"."resources";

drop policy "p_upd_resources" on "public"."resources";

drop policy "p_ins_settings" on "public"."settings";

drop policy "p_upd_settings" on "public"."settings";

drop policy "p_ins_staff" on "public"."staff_profiles";

drop policy "p_upd_staff" on "public"."staff_profiles";

drop function "public"."_group_arena_active"(uuid);

drop function "public"."app_owner_arena_ids"();

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
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$function$;

create or replace function public.op_controller_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_id uuid := (p->>'id')::uuid; v_loc uuid;
begin
  perform _need(p_arena, 'settings');
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from controllers where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'controller';
  end if;
  select current_resource_id into v_loc from controllers where id = v_id and arena_id = p_arena for update;
  if found and v_loc <> (p->>'current_resource_id')::uuid and exists (
       select 1 from controller_allocations where controller_id = v_id and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  insert into controllers(id, arena_id, label, home_resource_id, current_resource_id, status,
      notes, loan_return_to, loan_session_ref)
    values (v_id, p_arena, p->>'label', (p->>'home_resource_id')::uuid,
      (p->>'current_resource_id')::uuid, coalesce(p->>'status', 'usable'), p->>'notes',
      p->>'loan_return_to', p->>'loan_session_ref')
  on conflict (id) do update set label = excluded.label,
      home_resource_id = excluded.home_resource_id, current_resource_id = excluded.current_resource_id,
      status = excluded.status, notes = excluded.notes, loan_return_to = excluded.loan_return_to,
      loan_session_ref = excluded.loan_session_ref, updated_at = statement_timestamp()
    where controllers.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_game_upsert (
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
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from games where id = (p->>'id')::uuid and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  insert into games(id, arena_id, name, aliases, category_id, platforms, player_mode,
      max_local_players, active)
    values ((p->>'id')::uuid, p_arena, p->>'name',
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = excluded.active, updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
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
  if v_end is distinct from v_old then
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
  if v_end is distinct from v_old then
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
  -- money / reports make a member "owner level" (app_is_owner, and the app's
  -- AppUser.isOwner). Only an owner-level member may hand them out or take them away.
  c_owner_perms constant text[] := array['money', 'reports'];
  v_user   uuid    := (p->>'user_id')::uuid;
  v_perms  text[]  := array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb)));
  v_active boolean := coalesce((p->>'active')::boolean, true);
  v_role   text;
  v_old_perms  text[];
  v_old_active boolean;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  perform _assert_known_perms(v_perms);
  select role, perms, active into v_role, v_old_perms, v_old_active from staff_profiles
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
  else
    -- Nobody changes their own access: a Settings holder could otherwise grant
    -- themselves money/reports and become owner level.
    if v_user = auth.uid()
       and (not (v_perms @> v_old_perms and v_old_perms @> v_perms) or v_active <> v_old_active) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'you cannot change your own permissions';
    end if;
    -- Owner-level perms, and owner-level members, are managed by owners only.
    if not app_is_owner(p_arena)
       and (v_old_perms && c_owner_perms
            or ('money' = any(v_perms)) <> ('money' = any(v_old_perms))
            or ('reports' = any(v_perms)) <> ('reports' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports, or change an owner-level member';
    end if;
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
      if v_state in ('40001', '40P01', '55P03', '57014') then
        v_out := v_out || jsonb_build_array(jsonb_build_object('op_id', v_id,
          'status', 'retry', 'error', v_state));
        exit;
      end if;
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

alter table "public"."group_payments"
  add constraint "group_payments_amount_sign_check"
    check (((amount_paise <> 0) AND (is_refund = (amount_paise < 0))));

alter table "public"."payments"
  add constraint "payments_amount_sign_check"
    check (((amount_paise <> 0) AND ((kind = 'refund'::text) = (amount_paise < 0))));

alter table "public"."rates"
  add constraint "rates_unit_minutes_check" check ((unit_minutes > 0));

alter view "public"."sync_v_arenas" set (security_invoker=true);

alter view "public"."sync_v_bookings" set (security_invoker=true);

alter view "public"."sync_v_rates" set (security_invoker=true);

alter view "public"."sync_v_resource_activities" set (security_invoker=true);

create index ix_audit_log_created_by on public.audit_log using btree (created_by);

create index ix_bookings_activity_id on public.bookings using btree (activity_id);

create index ix_bookings_customer_id on public.bookings using btree (customer_id);

create index ix_bookings_game_id on public.bookings using btree (game_id);

create index ix_controller_allocations_created_by on public.controller_allocations
  using btree (created_by);

create index ix_controller_allocations_game_id on public.controller_allocations
  using btree (game_id);

create index ix_controller_allocations_segment_id on public.controller_allocations
  using btree (segment_id);

create index ix_controller_moves_created_by on public.controller_moves using btree (created_by);

create index ix_controller_moves_from_resource_id on public.controller_moves
  using btree (from_resource_id);

create index ix_controller_moves_to_resource_id on public.controller_moves
  using btree (to_resource_id);

create index ix_controllers_home_resource_id on public.controllers using btree (home_resource_id);

create index ix_games_category_id on public.games using btree (category_id);

create index ix_group_assignments_game_id on public.group_assignments using btree (game_id);

create index ix_group_charges_assignment_id on public.group_charges using btree (assignment_id);

create index ix_group_charges_resource_id on public.group_charges using btree (resource_id);

create index ix_group_extensions_created_by on public.group_extensions using btree (created_by);

create index ix_group_extensions_group_id on public.group_extensions using btree (group_id);

create index ix_group_payments_created_by on public.group_payments using btree (created_by);

create index ix_group_sessions_created_by on public.group_sessions using btree (created_by);

create index ix_group_sessions_primary_customer_id on public.group_sessions
  using btree (primary_customer_id);

create index ix_payments_created_by on public.payments using btree (created_by);

create index ix_rates_activity_id on public.rates using btree (activity_id);

create index ix_rates_band_id on public.rates using btree (band_id);

create index ix_resource_activities_activity_id on public.resource_activities
  using btree (activity_id);

create index ix_session_charges_resource_id on public.session_charges using btree (resource_id);

create index ix_session_charges_segment_id on public.session_charges using btree (segment_id);

create index ix_session_extensions_created_by on public.session_extensions using btree (created_by);

create index ix_session_segments_game_id on public.session_segments using btree (game_id);

create index ix_sessions_booking_id on public.sessions using btree (booking_id);

create index ix_sessions_created_by on public.sessions using btree (created_by);

create index ix_sessions_customer_id on public.sessions using btree (customer_id);

alter policy "p_sel_activities" on "public"."activities" to "authenticated";

alter policy "p_sel_arenas" on "public"."arenas" to "authenticated";

alter policy "p_sel_audit_log" on "public"."audit_log" to "authenticated";

alter policy "p_sel_billing_policies" on "public"."billing_policies" to "authenticated";

alter policy "p_sel_bookings" on "public"."bookings" to "authenticated";

alter policy "p_sel_controller_allocations" on "public"."controller_allocations" to "authenticated";

alter policy "p_sel_controller_moves" on "public"."controller_moves" to "authenticated";

alter policy "p_sel_controllers" on "public"."controllers" to "authenticated";

alter policy "p_sel_customers" on "public"."customers" to "authenticated";

alter policy "p_sel_game_categories" on "public"."game_categories" to "authenticated";

alter policy "p_sel_game_controls" on "public"."game_controls" to "authenticated";

alter policy "p_sel_game_resources" on "public"."game_resources" to "authenticated";

alter policy "p_sel_games" on "public"."games" to "authenticated";

alter policy "p_sel_group_assignments" on "public"."group_assignments" to "authenticated";

alter policy "p_sel_group_charges" on "public"."group_charges" to "authenticated";

alter policy "p_sel_group_extensions" on "public"."group_extensions" to "authenticated";

alter policy "p_sel_group_payments" on "public"."group_payments" to "authenticated";

alter policy "p_sel_group_sessions" on "public"."group_sessions" to "authenticated";

alter policy "p_sel_holidays" on "public"."holidays" to "authenticated";

alter policy "p_sel_payments" on "public"."payments" to "authenticated";

alter policy "p_sel_rate_bands" on "public"."rate_bands" to "authenticated";

alter policy "p_sel_rate_cards" on "public"."rate_cards" to "authenticated";

alter policy "p_sel_rates" on "public"."rates" to "authenticated";

alter policy "p_sel_resource_activities" on "public"."resource_activities" to "authenticated";

alter policy "p_sel_resources" on "public"."resources" to "authenticated";

alter policy "p_sel_session_charges" on "public"."session_charges" to "authenticated";

alter policy "p_sel_session_extensions" on "public"."session_extensions" to "authenticated";

alter policy "p_sel_session_segments" on "public"."session_segments" to "authenticated";

alter policy "p_sel_sessions" on "public"."sessions" to "authenticated";

alter policy "p_sel_settings" on "public"."settings" to "authenticated";

alter policy "p_sel_staff" on "public"."staff_profiles" to "authenticated";

revoke all on table "public"."activities" from "authenticated";

grant select on table "public"."activities" to "authenticated";

revoke all on table "public"."arenas" from "authenticated";

grant select on table "public"."arenas" to "authenticated";

revoke all on table "public"."audit_log" from "authenticated";

grant select on table "public"."audit_log" to "authenticated";

revoke all on table "public"."billing_policies" from "authenticated";

grant select on table "public"."billing_policies" to "authenticated";

revoke all on table "public"."bookings" from "authenticated";

grant select on table "public"."bookings" to "authenticated";

revoke all on table "public"."controller_allocations" from "authenticated";

grant select on table "public"."controller_allocations" to "authenticated";

revoke all on table "public"."controller_moves" from "authenticated";

grant select on table "public"."controller_moves" to "authenticated";

revoke all on table "public"."controllers" from "authenticated";

grant select on table "public"."controllers" to "authenticated";

revoke all on table "public"."customers" from "authenticated";

grant select on table "public"."customers" to "authenticated";

revoke all on table "public"."game_categories" from "authenticated";

grant select on table "public"."game_categories" to "authenticated";

revoke all on table "public"."game_controls" from "authenticated";

grant select on table "public"."game_controls" to "authenticated";

revoke all on table "public"."game_resources" from "authenticated";

grant select on table "public"."game_resources" to "authenticated";

revoke all on table "public"."games" from "authenticated";

grant select on table "public"."games" to "authenticated";

revoke all on table "public"."group_assignments" from "authenticated";

grant select on table "public"."group_assignments" to "authenticated";

revoke all on table "public"."group_charges" from "authenticated";

grant select on table "public"."group_charges" to "authenticated";

revoke all on table "public"."group_extensions" from "authenticated";

grant select on table "public"."group_extensions" to "authenticated";

revoke all on table "public"."group_payments" from "authenticated";

grant select on table "public"."group_payments" to "authenticated";

revoke all on table "public"."group_sessions" from "authenticated";

grant select on table "public"."group_sessions" to "authenticated";

revoke all on table "public"."holidays" from "authenticated";

grant select on table "public"."holidays" to "authenticated";

revoke all on table "public"."payments" from "authenticated";

grant select on table "public"."payments" to "authenticated";

revoke all on table "public"."rate_bands" from "authenticated";

grant select on table "public"."rate_bands" to "authenticated";

revoke all on table "public"."rate_cards" from "authenticated";

grant select on table "public"."rate_cards" to "authenticated";

revoke all on table "public"."rates" from "authenticated";

grant select on table "public"."rates" to "authenticated";

revoke all on table "public"."resource_activities" from "authenticated";

grant select on table "public"."resource_activities" to "authenticated";

revoke all on table "public"."resources" from "authenticated";

grant select on table "public"."resources" to "authenticated";

revoke all on table "public"."session_charges" from "authenticated";

grant select on table "public"."session_charges" to "authenticated";

revoke all on table "public"."session_extensions" from "authenticated";

grant select on table "public"."session_extensions" to "authenticated";

revoke all on table "public"."session_segments" from "authenticated";

grant select on table "public"."session_segments" to "authenticated";

revoke all on table "public"."sessions" from "authenticated";

grant select on table "public"."sessions" to "authenticated";

revoke all on table "public"."settings" from "authenticated";

grant select on table "public"."settings" to "authenticated";

revoke all on table "public"."staff_profiles" from "authenticated";

grant select on table "public"."staff_profiles" to "authenticated";
