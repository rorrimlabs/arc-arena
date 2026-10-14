-- op_rate_upsert — sync op 'rate.upsert': set the price of one rate on the active rate card.
--
-- Permission: settings.
-- Payload: activity_code, band? ('standard' or absent), controller_count? (absent/empty =
--   any count), unit_minutes, price_paise.
-- Checks / errors: activity_missing (unknown activity_code; raised by the declare initialisers, so
--   before the permission check); forbidden; invalid (hint band: any band but standard; time-of-day
--   prices such as happy hours are pricing rules); invalid_payload / invalid (bad unit or price).
-- Writes: rates; may create a rate_cards ('Current') or the 'standard' rate_bands row (_sync_apply
--   then retires the previous price list into pricing_catalog_history). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
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
  v_band uuid;
  v_cc int := nullif(p->>'controller_count','')::int;
  v_id uuid;
begin
  -- The declare initialisers (_active_card, _activity_id) already ran; anything they
  -- inserted rolls back with the op if this refuses.
  perform _need(p_arena, 'settings');
  if coalesce(p->>'band', 'standard') <> 'standard' then
    raise exception 'invalid' using hint = 'band';
  end if;
  v_band := _band_id(p_arena, 'standard');
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

comment on function public.op_rate_upsert(uuid, jsonb) is
  'Sync op rate.upsert: inserts or updates the active card''s standard rate for an activity and controller count.';

grant execute on function "public"."op_rate_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rate_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_rate_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_rate_upsert(p_arena uuid, p jsonb) from authenticated;
