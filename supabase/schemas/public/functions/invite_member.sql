-- invite_member() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.invite_member, which holds
-- the SECURITY DEFINER body and its checks (private/functions/invite_member.sql).
-- Called by the staff-admin Edge Function as the signed-in owner.
create or replace function public.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language sql
  security invoker
  set search_path to ''
  AS $function$
  select private.invite_member(p_arena, p_email, p_name, p_role, p_perms);
$function$;

comment on function public.invite_member(uuid, text, text, text, text[]) is 'Client API (Settings holder; owner invites need an owner): create a one-time invitation to the arena. Returns {invite_id, token, expires_at}.';

grant execute on function "public"."invite_member"(uuid, text, text, text, text[]) to "authenticated", "postgres", "service_role";

revoke all on function "public"."invite_member"(uuid, text, text, text, text[]) from public;

revoke all on function "public".invite_member(p_arena uuid, p_email text, p_name text, p_role text, p_perms text[]) from anon;
