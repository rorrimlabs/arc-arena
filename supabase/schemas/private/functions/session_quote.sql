-- session_quote(arena, station, activity, controllers, from, to) — price a past single session
--
-- Lives in `private`; clients reach it only through the SECURITY INVOKER wrapper
-- public.session_quote.
--
-- What session.record would bill for one station / type / controller count over [p_from, p_to)
-- on the arena's CURRENT price list (_pricing_snapshot), the whole time billed:
-- {subtotal, total (cash-rounded)}. Used by the floor app and the admin dashboard to show the
-- price of a missed bill before it is added; op_session_record re-prices and refuses any
-- difference (price_mismatch).
-- Who: bill_record (owners hold it); anyone else 'forbidden'.
-- Errors: forbidden; invalid_time (to not after from, or over 24 h); not_found (station);
--   activity_not_offered; no_rate. SECURITY DEFINER.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.session_quote (
  p_arena       uuid,
  p_resource    uuid,
  p_activity    text,
  p_controllers integer,
  p_from        timestamptz,
  p_to          timestamptz
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_snap jsonb; q jsonb; pol jsonb; v_sub bigint;
begin
  if auth.uid() is null or p_arena is null or not private.app_has_perm(p_arena, 'bill_record') then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs bill_record';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '24 hours' then
    raise exception 'invalid_time' using hint = 'the end must be after the start, at most 24 h later';
  end if;
  if not exists (select 1 from resources where id = p_resource and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'station';
  end if;
  v_snap := _pricing_snapshot(p_arena);
  perform _seg_priced(p_arena, p_resource, v_snap, p_activity, p_controllers);
  q := _pr_quote(v_snap, p_activity, p_controllers, p_from, p_to, p_from);
  pol := _pr_policy(v_snap);
  v_sub := coalesce((q->>'subtotal')::bigint, 0);
  return jsonb_build_object('subtotal', v_sub,
    'total', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'));
end;
$function$;

comment on function private.session_quote(uuid, uuid, text, integer, timestamptz, timestamptz) is 'Client API (bill_record): the price session.record would bill for a past single session on the current price list, {subtotal, total}.';

grant execute on function "private"."session_quote"(uuid, uuid, text, integer, timestamptz, timestamptz) to "authenticated", "postgres", "service_role";

revoke all on function "private"."session_quote"(uuid, uuid, text, integer, timestamptz, timestamptz) from public;

revoke all on function "private".session_quote(p_arena uuid, p_resource uuid, p_activity text, p_controllers integer, p_from timestamptz, p_to timestamptz) from anon;
