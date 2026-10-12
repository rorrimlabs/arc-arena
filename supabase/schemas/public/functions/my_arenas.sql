-- my_arenas() — the caller's memberships, for choosing an arena after sign-in
--
-- Returns a jsonb array (ordered by arena name, '[]' when none) of
-- {arena_id, arena_name, name, role, perms, active}, one per staff_profiles row
-- of auth.uid(). Inactive profiles are included, flagged active=false, so the
-- app can tell "deactivated" from "no access". Called by the staff app
-- (cloud_root.dart). SECURITY DEFINER; scoped to the caller by auth.uid().
-- Client API: callable by signed-in users (authenticated).
create or replace function public.my_arenas()
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'arena_id', s.arena_id, 'arena_name', a.name, 'name', s.name, 'role', s.role,
      'perms', to_jsonb(s.perms), 'active', s.active) order by a.name), '[]'::jsonb)
    from staff_profiles s join arenas a on a.id = s.arena_id
   where s.user_id = auth.uid();
$function$;

comment on function public.my_arenas() is 'Client API: the signed-in user''s staff profiles across arenas (including inactive ones) as a jsonb array of {arena_id, arena_name, name, role, perms, active}.';

grant execute on function "public"."my_arenas"() to "authenticated", "postgres", "service_role";

revoke all on function "public"."my_arenas"() from public;

revoke all on function "public".my_arenas() from anon;
