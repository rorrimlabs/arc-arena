-- sync_push() — client API entry point: a SECURITY INVOKER wrapper
--
-- The Data API exposes `public`, so nothing here runs with raised privileges:
-- this runs as the caller and hands over to private.sync_push, which holds the
-- SECURITY DEFINER body and its checks (private/functions/sync_push.sql). Same
-- name, arguments and result as before, so the apps call it unchanged.
create or replace function public.sync_push (
  p_arena  uuid,
  p_ops    jsonb,
  p_device text  default null::text
)
  returns jsonb
  language sql
  security invoker
  set search_path to ''
  AS $function$
  select private.sync_push(p_arena, p_ops, p_device);
$function$;

comment on function public.sync_push(uuid, jsonb, text) is 'Client API (sync): apply a batch of device ops in order, each at most once per op_id (recorded in sync_ops), and return each op''s status: applied, rejected (with error code) or retry.';

grant execute on function "public"."sync_push"(uuid, jsonb, text) to "authenticated", "postgres", "service_role";

revoke all on function "public"."sync_push"(uuid, jsonb, text) from public;

revoke all on function "public".sync_push(p_arena uuid, p_ops jsonb, p_device text) from anon;
