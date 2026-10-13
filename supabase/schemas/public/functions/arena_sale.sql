-- arena_sale() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.arena_sale, which holds the
-- SECURITY DEFINER body and its checks (private/functions/arena_sale.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.arena_sale (
  p_arena uuid,
  p_id    uuid
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path to ''
  AS $function$
  select private.arena_sale(p_arena, p_id);
$function$;

comment on function public.arena_sale(uuid, uuid) is 'Client API (owner level): one closed bill with its charge lines, extensions, payments ledger and void record, for the admin dashboard''s Sales detail.';

grant execute on function "public"."arena_sale"(uuid, uuid) to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_sale"(uuid, uuid) from public;

revoke all on function "public".arena_sale(p_arena uuid, p_id uuid) from anon;
