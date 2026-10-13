set local check_function_bodies = off;

create or replace function public._create_arena_with_owner (
  p_user       uuid,
  p_arena_name text,
  p_owner_name text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_arena uuid;
begin
  insert into arenas(name) values (coalesce(nullif(btrim(p_arena_name), ''), 'Arena'))
    returning id into v_arena;
  insert into staff_profiles(arena_id, user_id, name, role, perms, active)
    values (v_arena, p_user, coalesce(nullif(btrim(p_owner_name), ''), 'Owner'), 'owner',
      array['start','bill','discount','members','stations','money','reports','settings'], true);
  return v_arena;
end;
$function$;

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
                'holiday.upsert', 'holiday.delete', 'activity.upsert') then
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
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
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

create or replace function public.op_activity_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_code text := upper(btrim(coalesce(p->>'code', '')));
  v_name text := btrim(coalesce(p->>'name', ''));
  v_pads boolean := coalesce((p->>'uses_controllers')::boolean, false);
  v_old  activities%rowtype;
begin
  perform _need(p_arena, 'settings');
  if v_code !~ '^[A-Z0-9_]{1,12}$' then
    raise exception 'invalid_code' using hint = 'A–Z, 0–9 or _, up to 12';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if exists (select 1 from activities where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'activity';
  end if;

  select * into v_old from activities where id = v_id and arena_id = p_arena for update;
  if found then
    if v_old.code <> v_code then
      raise exception 'code_locked' using hint = v_old.code;
    end if;
    if v_old.uses_controllers <> v_pads and (
         exists (select 1 from session_segments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)
      or exists (select 1 from group_assignments
                  where arena_id = p_arena and activity_code = v_code and ended_at is null)) then
      raise exception 'activity_busy' using hint = v_code;
    end if;
  end if;

  insert into activities(id, arena_id, code, name, uses_controllers, uses_games, duration_model,
      happy_hour_eligible, sort_order, active)
    values (v_id, p_arena, v_code, v_name, v_pads,
      coalesce((p->>'uses_games')::boolean, false),
      coalesce(p->>'duration_model', 'hourly'),
      coalesce((p->>'happy_hour_eligible')::boolean, true),
      coalesce((p->>'sort_order')::int, 0),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    name = excluded.name, uses_controllers = excluded.uses_controllers,
    uses_games = excluded.uses_games, duration_model = excluded.duration_model,
    happy_hour_eligible = excluded.happy_hour_eligible, sort_order = excluded.sort_order,
    active = excluded.active, updated_at = statement_timestamp()
  where activities.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function "public"."_create_arena_with_owner"(uuid, text, text) is
  'Internal: create an empty arena (no catalog: the owner adds station types, prices, stations, games and controllers on the dashboard) and make the given login its owner with every permission. Shared by bootstrap_owner and create_my_arena; callers validate the login first.';

comment on function "public"."_seed_arena_catalog"(uuid) is 'Test fixture only (pgTAP): fill a test arena with the 404 Arena catalog (activities, stations, rates, billing policy, games, controllers, game compatibility). Real arenas start empty. Not idempotent.';

comment on function "public"."op_activity_upsert"(uuid, jsonb) is 'Sync op activity.upsert: creates or edits a station type (activity); its code is fixed once created.';

revoke all on function "public"."op_activity_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_activity_upsert"(uuid, jsonb) to "postgres", "service_role";
