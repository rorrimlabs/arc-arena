-- app_arena_ids() — arenas where the caller has an active staff profile
--
-- Returns the arena_id of every active staff_profiles row for auth.uid(); an
-- inactive profile grants nothing. It is the membership test behind the SELECT
-- RLS policies on arena tables and the gate in sync_push, sync_pull and
-- sync_fetch_entity. SECURITY DEFINER so it can read staff_profiles whatever
-- the caller's own RLS view of that table is.
-- Client API: callable by signed-in users (authenticated).
create or replace function public.app_arena_ids()
  returns SETOF uuid
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  -- `and active` matches the client's PermissionGuard active gate and the
  -- role-aware helpers: a deactivated staff member loses all access server-side.
  select arena_id from staff_profiles where user_id = auth.uid() and active;
$function$;

comment on function public.app_arena_ids() is 'Arena ids where the signed-in user has an active staff profile; the membership test used by RLS policies and the sync RPCs.';

grant execute on function "public"."app_arena_ids"() to "authenticated", "postgres", "service_role";

revoke all on function "public"."app_arena_ids"() from public;

revoke all on function "public".app_arena_ids() from anon;
