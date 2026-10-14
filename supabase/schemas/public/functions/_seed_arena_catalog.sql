-- _seed_arena_catalog(arena) — pgTAP fixture: fill a test arena with the 404 Arena catalog
--
-- TEST FIXTURE ONLY. Real arenas start empty (_create_arena_with_owner no
-- longer calls this; owners build their catalog on the dashboard) and
-- supabase/seed.sql seeds nothing. The pgTAP files build their isolated arenas
-- with it.
--
-- Inserts 4 activities (PS5, VR, POOL, LOUNGE), 6 stations and their activity
-- links, the standard rate band with one 'Current' rate card and its rates
-- (integer paise; no pricing rules: a test that needs happy hours adds the rule),
-- a 'Default' billing policy, 9 game categories, 16 games (controls for EA FC only), 2 controllers per PS5 station and per-station game
-- compatibility; game modes and station overrides follow the device seed.
-- Run once per arena: a second run hits unique keys (e.g. activities code).
-- Server-only: not executable by anon/authenticated.
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

  -- player_mode / max_local_players match lib/data/local/seed_data.dart, so the
  -- server's player-limit checks agree with the device (audit §1).
  insert into games(arena_id,name,aliases,category_id,platforms,player_mode,max_local_players) values
    (v_arena,'EA SPORTS FC 25', array['EA FC','FIFA'], c_football, array['PS5'],'both',4) returning id into v_eafc;
  insert into games(arena_id,name,aliases,category_id,platforms,player_mode,max_local_players) values
    (v_arena,'eFootball', array['PES'], c_football, array['PS5'],'both',2),
    (v_arena,'Tekken 8', '{}', c_fighting, array['PS5'],'local',2),
    (v_arena,'Mortal Kombat 1', array['MK1'], c_fighting, array['PS5'],'local',2),
    (v_arena,'Street Fighter 6', array['SF6'], c_fighting, array['PS5'],'local',2),
    (v_arena,'WWE 2K24', '{}', c_wrestling, array['PS5'],'local',4),
    (v_arena,'Gran Turismo 7', array['GT7'], c_racing, array['PS5','PSVR2'],'both',2),
    (v_arena,'F1 24', '{}', c_racing, array['PS5'],'both',2),
    (v_arena,'God of War Ragnarok', array['GOW'], c_action, array['PS5'],'single',1),
    (v_arena,'Marvel''s Spider-Man 2', array['Spiderman 2'], c_action, array['PS5'],'single',1),
    (v_arena,'GTA V', array['Grand Theft Auto V'], c_action, array['PS5'],'single',1),
    (v_arena,'Call of Duty: MW III', array['COD'], c_shooter, array['PS5'],'both',2),
    (v_arena,'Fortnite', '{}', c_shooter, array['PS5'],'online',1),
    (v_arena,'NBA 2K24', '{}', c_sports, array['PS5'],'local',4),
    (v_arena,'Beat Saber', '{}', c_vr, array['PSVR2'],'single',1),
    (v_arena,'Swordsman VR', '{}', c_vr, array['PSVR2'],'single',1);

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

comment on function public._seed_arena_catalog(uuid) is 'Test fixture only (pgTAP): fill a test arena with the 404 Arena catalog (activities, stations, rates, billing policy, games, controllers, game compatibility). Real arenas start empty. Not idempotent.';

grant execute on function "public"."_seed_arena_catalog"(uuid) to "postgres", "service_role";

revoke all on function "public"."_seed_arena_catalog"(uuid) from public;

revoke all on function "public"._seed_arena_catalog(v_arena uuid) from anon;

revoke all on function "public"._seed_arena_catalog(v_arena uuid) from authenticated;
