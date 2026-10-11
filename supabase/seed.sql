-- Seed data for a single arena (spec §39). Prices are in paise (₹ × 100).
-- Rates mirror docs/OWNER_CONFIRMATION.md / spec §5. Happy-hour rates exist only
-- where the activity is happy-eligible (PS5, Pool); VR and Lounge have none yet.

do $$
declare
  v_arena uuid;
  v_ps5 uuid; v_vr uuid; v_pool uuid; v_lounge uuid;
  v_hex uuid; v_void uuid; v_ghost uuid; v_rift uuid; v_pool1 uuid; v_private uuid;
  v_std uuid; v_happy uuid;
  v_card uuid;
  c_football uuid; c_fighting uuid; c_wrestling uuid; c_racing uuid;
  c_action uuid; c_shooter uuid; c_sports uuid; c_vr uuid; c_other uuid;
  v_eafc uuid;
begin
  insert into arenas(name) values ('Arena') returning id into v_arena;

  -- Activities ---------------------------------------------------------------
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'PS5','PlayStation 5', true, true, 'hourly', true, 1) returning id into v_ps5;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'VR','VR (PSVR2)', false, true, 'unit', false, 2) returning id into v_vr;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'POOL','Pool', false, false, 'hourly', true, 3) returning id into v_pool;
  insert into activities(arena_id, code, name, uses_controllers, uses_games, duration_model, happy_hour_eligible, sort_order)
    values (v_arena,'LOUNGE','Private Lounge', false, false, 'flat_hourly', false, 4) returning id into v_lounge;

  -- Resources ----------------------------------------------------------------
  insert into resources(arena_id,name,kind,sort_order) values (v_arena,'HEX','station',1) returning id into v_hex;
  insert into resources(arena_id,name,kind,sort_order) values (v_arena,'VOID','station',2) returning id into v_void;
  insert into resources(arena_id,name,kind,sort_order) values (v_arena,'GHOST','station',3) returning id into v_ghost;
  insert into resources(arena_id,name,kind,sort_order) values (v_arena,'RIFT','station',4) returning id into v_rift;
  insert into resources(arena_id,name,kind,sort_order) values (v_arena,'Pool Table 1','table',5) returning id into v_pool1;
  insert into resources(arena_id,name,kind,sort_order) values (v_arena,'Private Lounge','room',6) returning id into v_private;

  -- Resource ↔ activity links. RIFT hosts BOTH PS5 and VR (only VR-capable).
  insert into resource_activities(arena_id,resource_id,activity_id) values
    (v_arena,v_hex,v_ps5),(v_arena,v_void,v_ps5),(v_arena,v_ghost,v_ps5),
    (v_arena,v_rift,v_ps5),(v_arena,v_rift,v_vr),
    (v_arena,v_pool1,v_pool),(v_arena,v_private,v_lounge);

  -- Rate bands + card --------------------------------------------------------
  insert into rate_bands(arena_id,code,name) values (v_arena,'standard','Standard') returning id into v_std;
  insert into rate_bands(arena_id,code,name) values (v_arena,'happy','Happy Hour') returning id into v_happy;
  insert into rate_cards(arena_id,name) values (v_arena,'Current') returning id into v_card;

  -- Rates (per hour unless unit_minutes says otherwise) ----------------------
  insert into rates(arena_id,rate_card_id,activity_id,band_id,controller_count,unit_minutes,price_paise) values
    -- PS5 by controller count: standard / happy
    (v_arena,v_card,v_ps5,v_std,  1,60,15000),(v_arena,v_card,v_ps5,v_happy,1,60,12000),
    (v_arena,v_card,v_ps5,v_std,  2,60,28000),(v_arena,v_card,v_ps5,v_happy,2,60,22000),
    (v_arena,v_card,v_ps5,v_std,  3,60,39000),(v_arena,v_card,v_ps5,v_happy,3,60,31000),
    (v_arena,v_card,v_ps5,v_std,  4,60,48000),(v_arena,v_card,v_ps5,v_happy,4,60,38000),
    -- VR: ₹200 / 30 min, standard only (happy-eligibility OWNER CONFIRMATION #10)
    (v_arena,v_card,v_vr,v_std,  null,30,20000),
    -- Pool: ₹275 / ₹220 per hour
    (v_arena,v_card,v_pool,v_std, null,60,27500),(v_arena,v_card,v_pool,v_happy,null,60,22000),
    -- Lounge: ₹2000 / hour, standard only
    (v_arena,v_card,v_lounge,v_std,null,60,200000);

  -- Default billing policy (all defaults from docs/OWNER_CONFIRMATION.md) -----
  insert into billing_policies(arena_id,name) values (v_arena,'Default');

  -- Game categories ----------------------------------------------------------
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Football',1) returning id into c_football;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Fighting',2) returning id into c_fighting;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Wrestling',3) returning id into c_wrestling;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Racing',4) returning id into c_racing;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Action',5) returning id into c_action;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Shooter',6) returning id into c_shooter;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Sports',7) returning id into c_sports;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'VR',8) returning id into c_vr;
  insert into game_categories(arena_id,name,sort_order) values (v_arena,'Other',9) returning id into c_other;

  -- ~15 starter games --------------------------------------------------------
  insert into games(arena_id,name,aliases,category_id,platforms) values
    (v_arena,'EA SPORTS FC 25', array['EA FC','FIFA'], c_football, array['PS5']) returning id into v_eafc;
  insert into games(arena_id,name,aliases,category_id,platforms) values
    (v_arena,'eFootball', array['PES'], c_football, array['PS5']),
    (v_arena,'Tekken 8', '{}', c_fighting, array['PS5']),
    (v_arena,'Mortal Kombat 1', array['MK1'], c_fighting, array['PS5']),
    (v_arena,'Street Fighter 6', array['SF6'], c_fighting, array['PS5']),
    (v_arena,'WWE 2K24', '{}', c_wrestling, array['PS5']),
    (v_arena,'Gran Turismo 7', array['GT7'], c_racing, array['PS5','PSVR2']),
    (v_arena,'F1 24', '{}', c_racing, array['PS5']),
    (v_arena,'God of War Ragnarok', array['GOW'], c_action, array['PS5']),
    (v_arena,'Marvel''s Spider-Man 2', array['Spiderman 2'], c_action, array['PS5']),
    (v_arena,'Call of Duty: MW III', array['COD','Warzone'], c_shooter, array['PS5']),
    (v_arena,'Fortnite', '{}', c_shooter, array['PS5']),
    (v_arena,'NBA 2K24', '{}', c_sports, array['PS5']),
    (v_arena,'Beat Saber', '{}', c_vr, array['PSVR2']),
    (v_arena,'Swordsman VR', '{}', c_vr, array['PSVR2']);

  -- Controls for EA FC (spec §23 example) ------------------------------------
  insert into game_controls(arena_id,game_id,section,action,buttons,explanation,sort_order) values
    (v_arena,v_eafc,'Attacking','Shoot',        array['CIRCLE'],   'Hold longer for more power', 1),
    (v_arena,v_eafc,'Attacking','Short Pass',    array['CROSS'],    null, 2),
    (v_arena,v_eafc,'Attacking','Through Ball',  array['TRIANGLE'], null, 3),
    (v_arena,v_eafc,'Attacking','Lob / Cross',   array['SQUARE'],   null, 4),
    (v_arena,v_eafc,'Attacking','Sprint',        array['R2'],       'Hold while moving', 5),
    (v_arena,v_eafc,'Defending','Tackle',        array['CIRCLE'],   null, 6),
    (v_arena,v_eafc,'Defending','Jockey',        array['L2'],       null, 7),
    (v_arena,v_eafc,'Defending','Switch Player', array['L1'],       null, 8);

  -- Controllers: two per PS5 station, eight in all (mirrors seed_data.dart) ---
  insert into controllers(arena_id, label, home_resource_id, current_resource_id, status)
  select v_arena, r.name || '-' || n::text, r.id, r.id, 'usable'
  from resources r, generate_series(1,2) as n
  where r.arena_id = v_arena and r.name in ('HEX','VOID','GHOST','RIFT');

  -- Game ↔ resource availability (spec §4): PS5 games playable on the four PS5
  -- stations (with the EA FC / Tekken overrides); pure-VR games on RIFT only.
  insert into game_resources(arena_id, game_id, resource_id, status)
  select v_arena, g.id, r.id,
    case
      when g.name = 'EA SPORTS FC 25' and r.name = 'GHOST' then 'not_playable'
      when g.name = 'Tekken 8'        and r.name = 'RIFT'  then 'not_playable'
      else 'playable'
    end
  from games g
  join resources r on r.arena_id = v_arena and r.name in ('HEX','VOID','GHOST','RIFT')
  where g.arena_id = v_arena and 'PS5' = any(g.platforms);

  insert into game_resources(arena_id, game_id, resource_id, status)
  select v_arena, g.id, r.id, 'playable'
  from games g
  join resources r on r.arena_id = v_arena and r.name = 'RIFT'
  where g.arena_id = v_arena and 'PSVR2' = any(g.platforms) and not ('PS5' = any(g.platforms));
end $$;
