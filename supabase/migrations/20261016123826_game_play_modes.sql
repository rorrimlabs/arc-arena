set local check_function_bodies = off;

alter table "public"."games"
  drop constraint "games_age_rating_check";

alter table "public"."games"
  drop constraint "games_player_mode_check";

alter table "public"."games"
  drop column "player_mode";

alter table "public"."games"
  add column "play_modes" text[] not null default '{single}'::text[];

create or replace function public._seed_arena_catalog (
  v_arena uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_ps5 uuid; v_vr uuid; v_pool uuid; v_lounge uuid;
  v_std uuid; v_card uuid;
  c_football uuid; c_fighting uuid; c_wrestling uuid; c_racing uuid;
  c_action uuid; c_shooter uuid; c_sports uuid; c_vr uuid; v_eafc uuid;
begin
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, sort_order)
    values (v_arena,'PS5','PlayStation 5', true, true, 'hourly', 1) returning id into v_ps5;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, sort_order)
    values (v_arena,'VR','VR (PSVR2)', false, true, 'unit', 2) returning id into v_vr;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, sort_order)
    values (v_arena,'POOL','Pool', false, false, 'hourly', 3) returning id into v_pool;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, sort_order)
    values (v_arena,'LOUNGE','Private Lounge', false, false, 'flat_hourly', 4) returning id into v_lounge;

  insert into resources(arena_id,name,kind,sort_order) values
    (v_arena,'HEX','station',1),(v_arena,'VOID','station',2),(v_arena,'GHOST','station',3),
    (v_arena,'RIFT','station',4),(v_arena,'Pool Table 1','table',5),(v_arena,'Private Lounge','room',6);
  insert into resource_activities(arena_id,resource_id,activity_id)
    select v_arena, r.id, a.id from resources r join activities a on a.arena_id = v_arena
     where r.arena_id = v_arena and (
       (r.name in ('HEX','VOID','GHOST','RIFT') and a.code = 'PS5')
       or (r.name = 'RIFT' and a.code = 'VR')
       or (r.name = 'Pool Table 1' and a.code = 'POOL')
       or (r.name = 'Private Lounge' and a.code = 'LOUNGE'));

  insert into rate_bands(arena_id,code,name) values (v_arena,'standard','Standard') returning id into v_std;
  insert into rate_cards(arena_id,name) values (v_arena,'Current') returning id into v_card;
  insert into rates(arena_id,rate_card_id,activity_id,band_id,controller_count,unit_minutes,price_paise) values
    (v_arena,v_card,v_ps5,v_std,  1,60,15000),
    (v_arena,v_card,v_ps5,v_std,  2,60,28000),
    (v_arena,v_card,v_ps5,v_std,  3,60,39000),
    (v_arena,v_card,v_ps5,v_std,  4,60,48000),
    (v_arena,v_card,v_vr,v_std,  null,30,20000),
    (v_arena,v_card,v_pool,v_std, null,60,27500),
    (v_arena,v_card,v_lounge,v_std,null,60,200000);
  insert into billing_policies(arena_id,name) values (v_arena,'Default');

  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Football',1) returning id into c_football;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Fighting',2) returning id into c_fighting;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Wrestling',3) returning id into c_wrestling;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Racing',4) returning id into c_racing;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Action',5) returning id into c_action;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Shooter',6) returning id into c_shooter;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Sports',7) returning id into c_sports;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'VR',8) returning id into c_vr;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Other',9);

  -- play_modes / max_local_players match lib/data/local/seed_data.dart, so the
  -- server's player-limit checks agree with the device (audit §1).
  insert into games(arena_id,name,aliases,category_id,platforms,play_modes,max_local_players) values
    (v_arena,'EA SPORTS FC 25', array['EA FC','FIFA'], c_football, array['PS5'],'{single,local,online}',4) returning id into v_eafc;
  insert into games(arena_id,name,aliases,category_id,platforms,play_modes,max_local_players) values
    (v_arena,'eFootball', array['PES'], c_football, array['PS5'],'{single,local,online}',2),
    (v_arena,'Tekken 8', '{}', c_fighting, array['PS5'],'{story,local,online}',2),
    (v_arena,'Mortal Kombat 1', array['MK1'], c_fighting, array['PS5'],'{story,local,online}',2),
    (v_arena,'Street Fighter 6', array['SF6'], c_fighting, array['PS5'],'{story,local,online}',2),
    (v_arena,'WWE 2K24', '{}', c_wrestling, array['PS5'],'{story,local,online}',4),
    (v_arena,'Gran Turismo 7', array['GT7'], c_racing, array['PS5','PSVR2'],'{single,local,online}',2),
    (v_arena,'F1 24', '{}', c_racing, array['PS5'],'{story,local,online}',2),
    (v_arena,'God of War Ragnarok', array['GOW'], c_action, array['PS5'],'{story}',1),
    (v_arena,'Marvel''s Spider-Man 2', array['Spiderman 2'], c_action, array['PS5'],'{story}',1),
    (v_arena,'GTA V', array['Grand Theft Auto V'], c_action, array['PS5'],'{story,online}',1),
    (v_arena,'Call of Duty: MW III', array['COD'], c_shooter, array['PS5'],'{story,local,online}',2),
    (v_arena,'Fortnite', '{}', c_shooter, array['PS5'],'{online}',1),
    (v_arena,'NBA 2K24', '{}', c_sports, array['PS5'],'{story,local,online}',4),
    (v_arena,'Beat Saber', '{}', c_vr, array['PSVR2'],'{single}',1),
    (v_arena,'Swordsman VR', '{}', c_vr, array['PSVR2'],'{story}',1);

  insert into game_controls(arena_id,game_id,section,action,buttons,explanation,sort_order) values
    (v_arena,v_eafc,'Attacking','Shoot',        array['CIRCLE'],   'Hold longer for more power', 1),
    (v_arena,v_eafc,'Attacking','Short Pass',    array['CROSS'],    null, 2),
    (v_arena,v_eafc,'Attacking','Through Ball',  array['TRIANGLE'], null, 3),
    (v_arena,v_eafc,'Attacking','Lob / Cross',   array['SQUARE'],   null, 4),
    (v_arena,v_eafc,'Attacking','Sprint',        array['R2'],       'Hold while moving', 5),
    (v_arena,v_eafc,'Defending','Tackle',        array['CIRCLE'],   null, 6),
    (v_arena,v_eafc,'Defending','Jockey',        array['L2'],       null, 7),
    (v_arena,v_eafc,'Defending','Switch Player', array['L1'],       null, 8);

  insert into controllers(arena_id, label, home_resource_id, current_resource_id, status)
    select v_arena, r.name || '-' || n::text, r.id, r.id, 'usable'
      from resources r, generate_series(1,2) as n
     where r.arena_id = v_arena and r.name in ('HEX','VOID','GHOST','RIFT');

  -- Same overrides as the device seed: EA FC not on GHOST, Tekken not on RIFT,
  -- GTA V not on HEX; pure-VR games on RIFT only.
  insert into game_resources(arena_id, game_id, resource_id, status)
    select v_arena, g.id, r.id,
      case
        when g.name = 'EA SPORTS FC 25' and r.name = 'GHOST' then 'not_playable'
        when g.name = 'Tekken 8'        and r.name = 'RIFT'  then 'not_playable'
        when g.name = 'GTA V'           and r.name = 'HEX'   then 'not_playable'
        else 'playable'
      end
      from games g
      join resources r on r.arena_id = v_arena and r.name in ('HEX','VOID','GHOST','RIFT')
     where g.arena_id = v_arena and 'PS5' = any(g.platforms);
  insert into game_resources(arena_id, game_id, resource_id, status)
    select v_arena, g.id, r.id, 'playable'
      from games g join resources r on r.arena_id = v_arena and r.name = 'RIFT'
     where g.arena_id = v_arena and 'PSVR2' = any(g.platforms) and not ('PS5' = any(g.platforms));
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
  -- Deduplicated, in the column's canonical order; null when the payload names no mode (an edit
  -- then keeps the stored ones).
  v_modes  text[] := case
    when p ? 'play_modes' then array(
      select m from (select distinct jsonb_array_elements_text(p->'play_modes') as m) x
       order by array_position(array['story', 'single', 'local', 'online'], m))
    when p ? 'player_mode' then case p->>'player_mode'
      when 'both' then array['local', 'online'] else array[p->>'player_mode'] end
  end;
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

  insert into games(id, arena_id, name, aliases, category_id, platforms, play_modes,
      max_local_players, active, age_rating, media)
    values (v_id, p_arena, v_name,
      array(select jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb))),
      nullif(p->>'category_id','')::uuid,
      array(select jsonb_array_elements_text(coalesce(p->'platforms', '[]'::jsonb))),
      coalesce(v_modes, '{single}'), coalesce((p->>'max_local_players')::int, 1),
      coalesce((p->>'active')::boolean, true),
      (p->>'age_rating')::smallint, p->>'media')
  on conflict (id) do update set name = excluded.name, aliases = excluded.aliases,
      category_id = excluded.category_id, platforms = excluded.platforms,
      play_modes = coalesce(v_modes, games.play_modes),
      max_local_players = excluded.max_local_players,
      active = case when p ? 'active' then excluded.active else games.active end,
      age_rating = case when p ? 'age_rating' then excluded.age_rating else games.age_rating end,
      media = case when p ? 'media' then excluded.media else games.media end,
      updated_at = statement_timestamp()
    where games.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

alter table "public"."games"
  add constraint "games_age_rating_check" check (((age_rating >= 3) AND (age_rating <= 18)));

alter table "public"."games"
  add constraint "games_play_modes_check"
    check
    (((cardinality(play_modes) >= 1) AND (play_modes <@ ARRAY['story'::text, 'single'::text,
    'local'::text, 'online'::text])));

comment on column "public"."games"."age_rating" is 'Minimum age the title is rated for, a whole number of years from 3 to 18; null when not set. Shown on the admin dashboard; the floor app does not read it yet.';

comment on column "public"."games"."play_modes" is 'How the title can be played, one or more of story (story mode / campaign), single (single player, e.g. against the computer), local (local multiplayer), online (online multiplayer); listed in that order.';
