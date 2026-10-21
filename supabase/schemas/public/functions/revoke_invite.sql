-- revoke_invite() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.revoke_invite, which holds
-- the SECURITY DEFINER body and its checks (private/functions/revoke_invite.sql).
create or replace function public.revoke_invite (
  p_arena  uuid,
  p_invite uuid
)
  returns void
  language sql
  security invoker
  set search_path to ''
  AS $function$
  select private.revoke_invite(p_arena, p_invite);
$function$;

comment on function public.revoke_invite(uuid, uuid) is 'Client API (Settings holder; owner invites need an owner): withdraw an open invitation.';

grant execute on function "public"."revoke_invite"(uuid, uuid) to "authenticated", "postgres", "service_role";

revoke all on function "public"."revoke_invite"(uuid, uuid) from public;

revoke all on function "public".revoke_invite(p_arena uuid, p_invite uuid) from anon;
