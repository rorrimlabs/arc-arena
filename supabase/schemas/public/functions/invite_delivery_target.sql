-- invite_delivery_target(email) — which invitation e-mail an address needs
--
-- Server-only (service_role): the staff-admin Edge Function calls it after
-- invite_member to pick the e-mail it sends; clients can never execute it, so
-- it is not an account-existence oracle. Returns null when no login uses the
-- address (send an invite: GoTrue creates the login, confirmed only when its
-- owner opens the link), else {user_id, confirmed}. For an unconfirmed login
-- the Edge Function first scrubs its password (whoever signed it up may not own
-- the address), then sends the invite; for a confirmed one it sends a sign-in
-- link.
-- SECURITY DEFINER to read auth.users; it is in `public` only because the Edge
-- Function reaches the database through the Data API, and only service_role
-- holds EXECUTE (anon/authenticated are revoked, see the security tests).
create or replace function public.invite_delivery_target (
  p_email text
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select jsonb_build_object('user_id', u.id, 'confirmed', u.email_confirmed_at is not null)
    from auth.users u
   where lower(u.email) = lower(btrim(p_email))
   limit 1;
$function$;

comment on function public.invite_delivery_target(text) is 'Server-only (service_role, staff-admin Edge Function): null when no login uses the address, else {user_id, confirmed}. Not executable by clients.';

grant execute on function "public"."invite_delivery_target"(text) to "postgres", "service_role";

revoke all on function "public"."invite_delivery_target"(text) from public;

revoke all on function "public".invite_delivery_target(p_email text) from anon;

revoke all on function "public".invite_delivery_target(p_email text) from authenticated;
