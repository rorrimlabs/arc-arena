-- _need(arena, perm) — raise unless the caller holds a permission
--
-- Guard used at the top of op_* functions: raises 'forbidden' (42501, hint
-- 'needs <perm>') unless app_has_perm(p_arena, p_perm), i.e. the caller is an
-- active owner or holds p_perm. sync_push maps 42501 to the 'forbidden' code.
-- Server-only: not executable by anon/authenticated.
create or replace function public._need (
  p_arena uuid,
  p_perm  text
)
  returns void
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
begin
  if not private.app_has_perm(p_arena, p_perm) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs ' || p_perm;
  end if;
end;
$function$;

comment on function public._need(uuid, text) is 'Internal guard for op_* functions: raise forbidden (42501) unless the signed-in user holds the permission in the arena.';

grant execute on function "public"."_need"(uuid, text) to "postgres", "service_role";

revoke all on function "public"."_need"(uuid, text) from public;

revoke all on function "public"._need(p_arena uuid, p_perm text) from anon;

revoke all on function "public"._need(p_arena uuid, p_perm text) from authenticated;
