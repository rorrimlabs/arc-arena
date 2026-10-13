set local check_function_bodies = off;

alter table "public"."arenas"
  add column "area" text;

alter table "public"."arenas"
  add column "phone" text;

alter table "public"."games"
  add column "age_rating" smallint;

alter table "public"."games"
  add column "media" text;

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

create or replace function public.op_arena_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_name  text := btrim(p->>'name');
  v_area  text := nullif(btrim(p->>'area'), '');
  v_phone text := nullif(btrim(p->>'phone'), '');
begin
  perform _need(p_arena, 'settings');
  if p ? 'name' and (v_name is null or char_length(v_name) not between 1 and 80) then
    raise exception 'invalid_name' using hint = '1–80 characters';
  end if;
  if p ? 'area' and char_length(v_area) > 80 then
    raise exception 'invalid_area' using hint = 'up to 80 characters';
  end if;
  if p ? 'phone' and v_phone !~ '^[0-9+() -]{6,20}$' then
    raise exception 'invalid_phone' using hint = '6–20 digits, spaces, +, ( ) or -';
  end if;
  update arenas set
      name  = case when p ? 'name' then v_name else name end,
      area  = case when p ? 'area' then v_area else area end,
      phone = case when p ? 'phone' then v_phone else phone end,
      updated_at = statement_timestamp()
    where id = p_arena;
  if not found then raise exception 'not_found' using hint = 'arena'; end if;
  return '{}'::jsonb;
end;
$function$;

revoke all on function "public"."op_arena_update"(uuid, jsonb) from public, "anon", "authenticated";

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
      max_local_players, active, age_rating, media)
    values ((p->>'id')::uuid, p_arena, p->>'name',
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(p->>'player_mode', 'single'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true),
      (p->>'age_rating')::smallint, p->>'media')
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      player_mode = excluded.player_mode, max_local_players = excluded.max_local_players,
      active = excluded.active,
      age_rating = case when p ? 'age_rating' then excluded.age_rating else games.age_rating end,
      media = case when p ? 'media' then excluded.media else games.media end,
      updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

alter table "public"."arenas"
  add constraint "arenas_area_check" check ((char_length(area) <= 80));

alter table "public"."arenas"
  add constraint "arenas_phone_check" check ((phone ~ '^[0-9+() -]{6,20}$'::text));

alter table "public"."games"
  add constraint "games_age_rating_check" check ((age_rating = ANY (ARRAY[3, 7, 12, 16, 18])));

alter table "public"."games"
  add constraint "games_media_check" check ((media = ANY (ARRAY['digital'::text, 'disc'::text])));

comment on column "public"."arenas"."area" is 'Locality shown with the arena name (e.g. Koramangala); null when not set. Written by arena.update.';

comment on column "public"."arenas"."phone" is 'Arena contact number, 6–20 of digits, spaces, +, ( ) and -; null when not set. Written by arena.update.';

comment on column "public"."games"."age_rating" is 'Minimum age the title is rated for (PEGI-style 3, 7, 12, 16 or 18); null when not set. Shown on the admin dashboard; the floor app does not read it yet.';

comment on column "public"."games"."media" is 'How the arena owns the title: digital or disc; null when not set. Shown on the admin dashboard; the floor app does not read it yet.';

comment on function "public"."op_arena_update"(uuid, jsonb) is 'Sync op arena.update: edits the arena''s name, area and phone (only the keys sent).';

revoke all on function "public"."op_arena_update"(uuid, jsonb) from "postgres";

grant execute on function "public"."op_arena_update"(uuid, jsonb) to "postgres";

grant execute on function "public"."op_arena_update"(uuid, jsonb) to "service_role";
