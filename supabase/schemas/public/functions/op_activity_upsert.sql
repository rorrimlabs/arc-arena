-- op_activity_upsert — sync op 'activity.upsert': create or edit a station type (activity).
--
-- Permission: settings.
-- Payload: id, code, name, uses_controllers, uses_games, duration_model
-- ('hourly' | 'unit' | 'flat_hourly'), happy_hour_eligible, sort_order?, active?.
-- The code is the type's stable business key (segments, rates, bookings and
-- pricing snapshots refer to it): 1–12 of A–Z, 0–9, _ after upper-casing, and it
-- cannot change once the type exists. Retiring a type is active = false.
-- Checks / errors: forbidden; invalid_code; invalid_name (1–40 characters);
-- not_found (hint activity: the id belongs to another arena); code_locked
-- (changing an existing type's code); activity_busy (switching
-- uses_controllers while a session or group player of this type is running);
-- duplicate (code already used by another type); invalid (bad duration_model).
-- Writes: activities. A price-list change: _sync_apply retires the previous
-- catalog into pricing_catalog_history. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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

comment on function public.op_activity_upsert(uuid, jsonb) is
  'Sync op activity.upsert: creates or edits a station type (activity); its code is fixed once created.';

grant execute on function "public"."op_activity_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_activity_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_activity_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_activity_upsert(p_arena uuid, p jsonb) from authenticated;
