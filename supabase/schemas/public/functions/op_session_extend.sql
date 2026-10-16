create or replace function public.op_session_extend (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_session uuid := (p->>'session_id')::uuid;
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_status text; v_end timestamptz;
  v_snap jsonb; v_start timestamptz; v_act text; v_cc int; q_old jsonb; q_new jsonb; v_added bigint;
begin
  perform _need(p_arena, 'start');
  select status, scheduled_end_at into v_status, v_end
    from sessions where id = v_session and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'session'; end if;
  if v_status <> 'active' then raise exception 'not_active' using hint = v_status; end if;
  if v_end is distinct from v_old then
    raise exception 'stale' using hint = 'the session was extended on another device';
  end if;
  insert into session_extensions(id, arena_id, session_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_session, (p->>'added_minutes')::int, v_end,
      v_new, coalesce((p->>'added_amount_paise')::bigint, 0), p->>'reason', auth.uid(), v_now);
  update sessions set scheduled_end_at = v_new, updated_at = v_now where id = v_session;

  -- Server-side pricing (0013): the extension costs the difference between the
  -- bill at the new end and at the old end, on the session's frozen price list.
  select pricing_snapshot, started_at into v_snap, v_start from sessions where id = v_session;
  select activity_code, controller_count into v_act, v_cc from session_segments
   where session_id = v_session order by (ended_at is null) desc, idx desc limit 1;
  q_old := _pr_quote(v_snap, v_act, v_cc, v_start, v_old);
  q_new := _pr_quote(v_snap, v_act, v_cc, v_start, v_new);
  if q_old is null or q_new is null then
    raise exception 'no_rate' using hint = 'the session''s price list has no rate for this extension';
  end if;
  v_added := (q_new->>'amount')::bigint - (q_old->>'amount')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return jsonb_build_object('new_end_at', p->>'new_end_at');
end;
$function$;

grant execute on function "public"."op_session_extend"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_session_extend"(uuid, jsonb) from public;

revoke all on function "public".op_session_extend(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_session_extend(p_arena uuid, p jsonb) from authenticated;
