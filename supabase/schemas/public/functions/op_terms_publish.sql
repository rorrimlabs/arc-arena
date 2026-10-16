-- op_terms_publish — sync op 'terms.publish': publish a new version of the staff terms
--
-- Permission: owner level (app_is_owner: role owner, or holds money or reports); not a _need perm.
-- Payload: id (client uuid: the new version's row id), title (1-120 characters after trimming),
--   body (the full text, 1-50,000 characters after trimming).
-- The version number is the arena's highest plus one (1 for the first); publishing asks every
-- member who is not owner level to accept the new version on the floor app.
-- Checks / errors: forbidden; invalid_payload (hint id / title / body); duplicate (id reused).
-- Writes: staff_terms. Returns: {version}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_terms_publish (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id      uuid := nullif(p->>'id', '')::uuid;
  v_title   text := btrim(coalesce(p->>'title', ''));
  v_body    text := btrim(coalesce(p->>'body', ''));
  v_version integer;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'terms are owner-only';
  end if;
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if v_title = '' or char_length(v_title) > 120 then
    raise exception 'invalid_payload' using hint = 'title: 1 to 120 characters';
  end if;
  if v_body = '' or char_length(v_body) > 50000 then
    raise exception 'invalid_payload' using hint = 'body: 1 to 50,000 characters';
  end if;
  if exists (select 1 from staff_terms where id = v_id) then
    raise exception 'duplicate' using hint = 'id';
  end if;

  -- Two publishes at once queue here, so versions never collide.
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text || ':staff_terms', 0));
  select coalesce(max(version), 0) + 1 into v_version from staff_terms where arena_id = p_arena;
  insert into staff_terms(id, arena_id, version, title, body, published_by, published_at)
    values (v_id, p_arena, v_version, v_title, v_body, auth.uid(), statement_timestamp());
  return jsonb_build_object('version', v_version);
end;
$function$;

comment on function public.op_terms_publish(uuid, jsonb) is 'Sync op terms.publish: adds the next version of the venue''s staff terms (owner level); everyone else accepts it again.';

grant execute on function "public"."op_terms_publish"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_terms_publish"(uuid, jsonb) from public;

revoke all on function "public".op_terms_publish(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_terms_publish(p_arena uuid, p jsonb) from authenticated;
