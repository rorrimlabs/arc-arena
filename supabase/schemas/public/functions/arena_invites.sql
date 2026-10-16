-- arena_invites() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_invites, which holds
-- the SECURITY DEFINER body and its checks (private/functions/arena_invites.sql).
create or replace function public.arena_invites (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_invites(p_arena);
$function$;

comment on function public.arena_invites(uuid) is 'Client API (owner level): the arena''s open invitations, newest first.';

grant execute on function "public"."arena_invites"(uuid) to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_invites"(uuid) from public;

revoke all on function "public".arena_invites(p_arena uuid) from anon;
