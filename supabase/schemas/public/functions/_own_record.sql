-- _own_record(arena, staff) — refuse acting on your own record (unless you are an owner)
--
-- Nobody approves their own leave or corrects or accepts their own attendance; role owner may.
-- Raises own_record.
-- Server-only: not executable by anon/authenticated.
create or replace function public._own_record (
  p_arena uuid,
  p_staff uuid
)
  returns void
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
begin
  if exists (select 1 from staff_profiles where id = p_staff and user_id = auth.uid())
     and not exists (select 1 from staff_profiles where arena_id = p_arena
                      and user_id = auth.uid() and active and role = 'owner') then
    raise exception 'own_record' using hint = 'ask someone else to do this for you';
  end if;
end;
$function$;

comment on function public._own_record(uuid, uuid) is 'Internal: raise own_record when the caller acts on their own staff record and is not role owner.';

grant execute on function "public"."_own_record"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_own_record"(uuid, uuid) from public;

revoke all on function "public"."_own_record"(uuid, uuid) from anon;

revoke all on function "public"."_own_record"(uuid, uuid) from authenticated;
