-- sync_v_rates — the live price list, shaped for devices and the pricer
--
-- Rates on active rate cards only, with the activity code and band code that
-- devices and the pricing snapshot use instead of uuids. Listed in _sync_sources
-- as the source for the 'rates' feed, and the rates part of _pricing_snapshot.
-- sync_xid is the rate's own. security_invoker, and no client grants: read only
-- by SECURITY DEFINER functions.
create view "public"."sync_v_rates"
  with (security_invoker = true)
as
select
  r.id,
  r.arena_id,
  r.rate_card_id,
  r.activity_id,
  r.band_id,
  r.controller_count,
  r.unit_minutes,
  r.price_paise,
  r.created_at,
  r.updated_at,
  r.sync_xid,
  ac.code as activity_code,
  b.code as band
from public.rates r
  join public.activities ac on ac.id = r.activity_id
  join public.rate_bands b on b.id = r.band_id
  join public.rate_cards c on c.id = r.rate_card_id and c.active;

comment on view public.sync_v_rates is 'Rates on active rate cards, with activity_code and band code. Change-feed source for rates and the rates section of the server pricing snapshot. Server-only.';

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."sync_v_rates"
  to "postgres", "service_role";

revoke all on table "public".sync_v_rates from anon;

revoke all on table "public".sync_v_rates from authenticated;
