-- op_terms_accept — sync op 'terms.accept': accept the staff terms in force (for yourself)
--
-- Permission: any active member, for their own staff profile.
-- Payload: id (client uuid: the acceptance row id), terms_id (the version read), device_at?
--   (the phone's clock, evidence only).
-- Only the latest version can be accepted: one published meanwhile makes the request stale
-- (the app shows the new text). Accepting a version already accepted returns the first
-- acceptance unchanged.
-- Checks / errors: not_found (hint staff / terms); invalid_payload (hint id / device_at);
--   stale (a newer version was published).
-- Writes: staff_terms_acceptances (accepted_at = server time). Returns: {accepted_at}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_terms_accept (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id     uuid := nullif(p->>'id', '')::uuid;
  v_terms  uuid := nullif(p->>'terms_id', '')::uuid;
  v_staff  uuid;
  v_latest uuid;
  v_device timestamptz;
  v_at     timestamptz;
begin
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  begin
    v_device := nullif(p->>'device_at', '')::timestamptz;
  exception when others then
    raise exception 'invalid_payload' using hint = 'device_at';
  end;
  if v_terms is null or not exists (select 1 from staff_terms where id = v_terms and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'terms';
  end if;

  select accepted_at into v_at from staff_terms_acceptances
    where staff_id = v_staff and terms_id = v_terms;
  if found then return jsonb_build_object('accepted_at', v_at); end if;

  select id into v_latest from staff_terms where arena_id = p_arena order by version desc limit 1;
  if v_latest <> v_terms then
    raise exception 'stale' using hint = 'a newer version of the terms was published';
  end if;

  insert into staff_terms_acceptances(id, arena_id, staff_id, terms_id, accepted_at, device_at)
    values (v_id, p_arena, v_staff, v_terms, statement_timestamp(), v_device)
    returning accepted_at into v_at;
  return jsonb_build_object('accepted_at', v_at);
end;
$function$;

comment on function public.op_terms_accept(uuid, jsonb) is 'Sync op terms.accept: records that the caller accepted the latest version of the staff terms (server time; device time as evidence).';

grant execute on function "public"."op_terms_accept"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_terms_accept"(uuid, jsonb) from public;

revoke all on function "public".op_terms_accept(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_terms_accept(p_arena uuid, p jsonb) from authenticated;
