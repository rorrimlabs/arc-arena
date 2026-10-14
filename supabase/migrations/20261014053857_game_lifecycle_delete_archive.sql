set local check_function_bodies = off;

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
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove') then
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
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
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

create or replace function public.op_game_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id      uuid := (p->>'id')::uuid;
  v_playing int;
  v_history text;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if exists (select 1 from games where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  -- The lock queues behind a start that is placing a session on it right now (its foreign-key
  -- check holds a key-share lock), so the checks below see that session once it commits.
  perform 1 from games where id = v_id and arena_id = p_arena for update;
  if not found then return jsonb_build_object('deleted', true); end if;

  select (select count(*) from session_segments
           where arena_id = p_arena and game_id = v_id and ended_at is null)
       + (select count(*) from group_assignments
           where arena_id = p_arena and game_id = v_id and ended_at is null)
    into v_playing;
  if v_playing > 0 then
    raise exception 'game_in_play' using hint = v_playing::text;
  end if;

  v_history := case
    when exists (select 1 from session_segments where arena_id = p_arena and game_id = v_id)
      then 'sessions'
    when exists (select 1 from group_assignments where arena_id = p_arena and game_id = v_id)
      then 'groups'
    when exists (select 1 from controller_allocations where arena_id = p_arena and game_id = v_id)
      then 'pads'
    when exists (select 1 from bookings where arena_id = p_arena and game_id = v_id)
      then 'bookings'
  end;
  if v_history is not null then
    raise exception 'game_has_history' using hint = v_history;
  end if;

  delete from games where id = v_id and arena_id = p_arena;
  return jsonb_build_object('deleted', true);
end;
$function$;

revoke all on function "public"."op_game_delete"(uuid, jsonb) from public, "anon", "authenticated";

create or replace function public.op_game_set_active (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_target boolean := (p->>'active')::boolean;
  v_active boolean;
begin
  perform _need(p_arena, 'settings');
  if v_target is null then raise exception 'invalid_payload' using hint = 'active'; end if;
  select active into v_active from games
   where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'game'; end if;
  if v_active is distinct from v_target then
    update games set active = v_target, updated_at = statement_timestamp()
      where id = (p->>'id')::uuid and arena_id = p_arena;
  end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_game_set_compat (
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
  insert into game_resources(arena_id, game_id, resource_id, status, notes)
    values (p_arena, (p->>'game_id')::uuid, (p->>'resource_id')::uuid, p->>'status', p->>'notes')
  on conflict (game_id, resource_id) do update
    set status = excluded.status,
        notes = case when p ? 'notes' then excluded.notes else game_resources.notes end,
        updated_at = statement_timestamp()
    where game_resources.arena_id = p_arena;
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
declare
  v_id     uuid := (p->>'id')::uuid;
  v_name   text := btrim(p->>'name');
  v_active boolean;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  -- An id that belongs to another arena is "not found" here, never a silent no-op.
  if exists (select 1 from games where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'game';
  end if;
  if v_name is null or v_name = '' or char_length(v_name) > 80 then
    raise exception 'invalid_name' using hint = '1 to 80 characters';
  end if;

  select active into v_active from games where id = v_id and arena_id = p_arena for update;
  if found then
    if p ? 'base_active' and (p->>'base_active')::boolean is distinct from v_active
       and p ? 'active' and (p->>'active')::boolean is distinct from v_active then
      raise exception 'stale' using hint = 'the game was archived or restored on another device';
    end if;
  elsif exists (select 1 from sync_tombstones
                 where arena_id = p_arena and table_name = 'games' and row_key->>'id' = v_id::text) then
    raise exception 'not_found' using hint = 'game deleted';
  end if;

  -- Names are unique ignoring case; the lock makes two concurrent saves of "FIFA" and "fifa" queue.
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text || ':game:' || lower(v_name), 0));
  if exists (select 1 from games
              where arena_id = p_arena and id <> v_id and lower(name) = lower(v_name)) then
    raise exception 'duplicate' using hint = 'name';
  end if;

  insert into games(id, arena_id, name, aliases, category_id, platforms, player_mode,
      max_local_players, active, age_rating, media)
    values (v_id, p_arena, v_name,
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true),
      (p->>'age_rating')::smallint, p->>'media')
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = case when p ? 'active' then excluded.active else games.active end,
      age_rating = case when p ? 'age_rating' then excluded.age_rating else games.age_rating end,
      media = case when p ? 'media' then excluded.media else games.media end,
      updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on column "public"."games"."active" is 'False archives the title: hidden from new sessions and bookings on every device, kept for the sessions, bills and bookings that refer to it (game.set_active).';

comment on function "public"."op_game_delete"(uuid, jsonb) is 'Sync op game.delete: permanently deletes a game no session, group, pad allocation or booking ever used (with its station statuses and control guide); refuses one in play (game_in_play) or with history (game_has_history: archive it instead).';

comment on function "public"."op_game_set_active"(uuid, jsonb) is 'Sync op game.set_active: archives (false) or restores (true) a game; sessions already playing it continue and history keeps it.';

comment on function "public"."op_game_upsert"(uuid, jsonb) is 'Sync op game.upsert: creates or edits a catalog game (name trimmed and unique ignoring case); refuses an edit over a newer archive/restore (stale) and never re-creates a deleted game.';

revoke all on function "public"."op_game_delete"(uuid, jsonb) from "postgres";

grant execute on function "public"."op_game_delete"(uuid, jsonb) to "postgres";

grant execute on function "public"."op_game_delete"(uuid, jsonb) to "service_role";
