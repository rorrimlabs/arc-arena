-- app_has_perm(arena, perm) — does the caller hold this permission in the arena?
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Used by RLS policies and server functions;
-- not part of the client API.
--
-- True when auth.uid() has an active staff profile in p_arena that either has
-- role 'owner' (owners implicitly hold every permission) or lists p_perm in
-- perms. Used by _need and directly by op_* functions for either-of checks.
-- SECURITY DEFINER so it reads staff_profiles regardless of the caller's RLS.
-- Executable by authenticated because RLS policies run as the caller; not
-- reachable over the Data API (private is not an exposed schema).
create or replace function private.app_has_perm (
  p_arena uuid,
  p_perm  text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select exists (
    select 1 from staff_profiles
     where user_id = auth.uid() and arena_id = p_arena and active
       and (role = 'owner' or p_perm = any(perms))
  );
$function$;

comment on function private.app_has_perm(uuid, text) is 'True when the signed-in user is an active member of the arena and is an owner or holds the given permission.';

grant execute
  on function "private"."app_has_perm"(uuid, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."app_has_perm"(uuid, text) from public;

revoke all on function "private".app_has_perm(p_arena uuid, p_perm text) from anon;
