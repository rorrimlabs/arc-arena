-- arena_invites(arena) — the arena's open invitations, for the owner dashboard
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Clients reach it only through the
-- SECURITY INVOKER wrapper public.arena_invites.
--
-- Caller must be owner level in p_arena (app_is_owner, same as arena_staff),
-- else 'forbidden'. Returns a jsonb array, newest first, of the invites not
-- yet accepted or withdrawn: {invite_id, email, name, role, perms, created_at,
-- expires_at, expired, invited_by_name}. The token hash is never returned.
create or replace function private.arena_invites (
  p_arena uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can list invites';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'invite_id', i.id, 'email', i.email, 'name', i.name, 'role', i.role,
        'perms', to_jsonb(i.perms), 'created_at', i.created_at, 'expires_at', i.expires_at,
        'expired', i.expires_at <= statement_timestamp(),
        'invited_by_name', s.name) order by i.created_at desc)
      from staff_invites i
      left join staff_profiles s on s.arena_id = i.arena_id and s.user_id = i.invited_by
     where i.arena_id = p_arena and i.accepted_at is null and i.revoked_at is null
  ), '[]'::jsonb);
end;
$function$;

comment on function private.arena_invites(uuid) is 'Owner level: the arena''s open invitations (not accepted or withdrawn), newest first, without their token hashes.';

grant execute
  on function "private"."arena_invites"(uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."arena_invites"(uuid) from public;

revoke all on function "private".arena_invites(p_arena uuid) from anon;
