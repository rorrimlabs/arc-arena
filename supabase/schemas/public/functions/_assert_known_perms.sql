-- _assert_known_perms(perms) — refuse unknown permission codes
--
-- Raises 'invalid_permission' (hint lists the valid codes) if any element of
-- p_perms is not in _known_perms(); null or empty passes. Called by
-- add_staff_by_email and op_staff_update before writing staff_profiles.perms.
-- Server-only: not executable by anon/authenticated.
create or replace function public._assert_known_perms (
  p_perms text[]
)
  returns void
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
begin
  if exists (select 1 from unnest(coalesce(p_perms, '{}')) x where x <> all(_known_perms())) then
    raise exception 'invalid_permission'
      using hint = 'permissions must be among ' || array_to_string(_known_perms(), ', ');
  end if;
end;
$function$;

comment on function public._assert_known_perms(text[]) is 'Internal: raise invalid_permission if the array contains a code outside _known_perms(); null or empty is accepted.';

grant execute on function "public"."_assert_known_perms"(text[]) to "postgres", "service_role";

revoke all on function "public"."_assert_known_perms"(text[]) from public;

revoke all on function "public"._assert_known_perms(p_perms text[]) from anon;

revoke all on function "public"._assert_known_perms(p_perms text[]) from authenticated;
