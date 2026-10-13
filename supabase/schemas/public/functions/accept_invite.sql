-- accept_invite() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.accept_invite, which holds
-- the SECURITY DEFINER body and its checks (private/functions/accept_invite.sql).
-- Called by the admin dashboard's /accept-invite page.
create or replace function public.accept_invite (
  p_invite uuid,
  p_token  text
)
  returns jsonb
  language sql
  security invoker
  set search_path to ''
  AS $function$
  select private.accept_invite(p_invite, p_token);
$function$;

comment on function public.accept_invite(uuid, text) is 'Client API: the invited, confirmed login presents its one-time token and joins the arena. Returns {arena_id, arena_name, role}.';

grant execute on function "public"."accept_invite"(uuid, text) to "authenticated", "postgres", "service_role";

revoke all on function "public"."accept_invite"(uuid, text) from public;

revoke all on function "public".accept_invite(p_invite uuid, p_token text) from anon;
