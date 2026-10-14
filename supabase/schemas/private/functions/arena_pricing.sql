-- arena_pricing(arena) — the owner dashboard's Pricing screen
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Clients reach it only through the
-- SECURITY INVOKER wrapper public.arena_pricing.
--
-- One jsonb object:
--   types[] — every activity (station type), retired ones included, ordered by
--             sort_order then name: {id, code, name, uses_controllers,
--             uses_games, duration_model, sort_order,
--             active, stations} where stations counts the arena's stations
--             offering it that are not disabled;
--   rates[] — the active rate card's standard rates as devices price them
--             (sync_v_rates; rows of the retired happy band are left out):
--             {activity_code, band, controller_count, unit_minutes, price_paise};
--   hours   — the opening hours the price list uses: the saved setting, else
--             the default ({open} by ISO weekday 1–7, minutes from IST
--             midnight, null = closed). Happy hours are pricing rules.
-- Writes go through sync_push (activity.upsert, rate.upsert, rate.delete,
-- settings.save). SECURITY DEFINER. Caller must be owner level in p_arena
-- (app_is_owner), else 'forbidden'.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.arena_pricing (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read pricing';
  end if;
  return jsonb_build_object(
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', a.id, 'code', a.code, 'name', a.name,
          'uses_controllers', a.uses_controllers, 'uses_games', a.uses_games,
          'duration_model', a.duration_model,
          'sort_order', a.sort_order, 'active', a.active,
          'stations', (select count(*) from resource_activities ra
                         join resources r on r.id = ra.resource_id
                        where ra.activity_id = a.id and r.status <> 'disabled'))
        order by a.sort_order, lower(a.name))
        from activities a where a.arena_id = p_arena), '[]'::jsonb),
    'rates', coalesce((
      select jsonb_agg(jsonb_build_object('activity_code', v.activity_code, 'band', v.band,
          'controller_count', v.controller_count, 'unit_minutes', v.unit_minutes,
          'price_paise', v.price_paise)
        order by v.activity_code, v.band, v.controller_count nulls first)
        from sync_v_rates v where v.arena_id = p_arena and v.band = 'standard'), '[]'::jsonb),
    'hours', jsonb_build_object('open', _pricing_snapshot(p_arena)->'hours'->'open'));
end;
$function$;

comment on function private.arena_pricing(uuid) is 'Client API (owner level): the arena''s station types with station counts, active standard rates and opening hours, for the admin dashboard''s Pricing screen.';

grant execute on function "private"."arena_pricing"(uuid) to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_pricing"(uuid) from public;

revoke all on function "private".arena_pricing(p_arena uuid) from anon;
