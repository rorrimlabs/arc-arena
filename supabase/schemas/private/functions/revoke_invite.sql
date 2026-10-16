-- revoke_invite(arena, invite) — withdraw an open invitation
--
-- Lives in `private`, which the Data API does not expose: SECURITY DEFINER
-- code never sits in an API schema. Clients reach it only through the
-- SECURITY INVOKER wrapper public.revoke_invite.
--
-- The caller holds Settings in p_arena (_need); an owner invite needs an owner.
-- Marks the open invite withdrawn, so its link stops working. 'not_found' when
-- the invite is not an open invite of p_arena.
create or replace function private.revoke_invite (
  p_arena  uuid,
  p_invite uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_role text;
begin
  perform _need(p_arena, 'settings');
  select role into v_role from staff_invites
   where id = p_invite and arena_id = p_arena and accepted_at is null and revoked_at is null
     for update;
  if not found then
    raise exception 'not_found' using hint = 'invite';
  end if;
  if v_role = 'owner' and not exists (select 1 from staff_profiles where arena_id = p_arena
       and user_id = auth.uid() and active and role = 'owner') then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can withdraw an owner invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp() where id = p_invite;
end;
$function$;

comment on function private.revoke_invite(uuid, uuid) is 'Withdraw an open invitation of the arena (caller holds Settings; owner invites need an owner). Its link stops working.';

grant execute
  on function "private"."revoke_invite"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."revoke_invite"(uuid, uuid) from public;

revoke all on function "private".revoke_invite(p_arena uuid, p_invite uuid) from anon;
