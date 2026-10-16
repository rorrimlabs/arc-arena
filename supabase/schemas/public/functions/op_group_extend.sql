-- op_group_extend — sync op 'group.extend': push out an active group's scheduled end.
--
-- Permission: start.
-- Payload: group_id, extension_id, old_end_at, new_end_at, added_minutes, added_amount_paise,
--   reason.
-- Checks / errors: forbidden; not_found (hint group); not_active; stale (scheduled end is distinct
--   from old_end_at, so a missing old_end_at counts as stale); price_mismatch (added_amount_paise
--   differs from the server's subtotal difference).
-- Writes: group_extensions, group_sessions.scheduled_end_at. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_extend (
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
  v_group uuid := (p->>'group_id')::uuid;
  v_old timestamptz := (p->>'old_end_at')::timestamptz;
  v_new timestamptz := (p->>'new_end_at')::timestamptz;
  v_end timestamptz; v_added bigint;
begin
  perform _need(p_arena, 'start');
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  if v_end is distinct from v_old then
    raise exception 'stale' using hint = 'the group was extended on another device';
  end if;
  insert into group_extensions(id, arena_id, group_id, added_minutes, old_end_at, new_end_at,
      added_amount_paise, reason, created_by, created_at)
    values ((p->>'extension_id')::uuid, p_arena, v_group, (p->>'added_minutes')::int, v_end,
      v_new, coalesce((p->>'added_amount_paise')::bigint, 0), p->>'reason', auth.uid(), v_now);
  update group_sessions set scheduled_end_at = v_new, updated_at = v_now where id = v_group;

  -- Server-side pricing (0013): the extension costs the difference between the
  -- group's subtotal at the new end and at the old end.
  v_added := (_pr_group_bill(v_group, v_new)->>'subtotal')::bigint
           - (_pr_group_bill(v_group, v_old)->>'subtotal')::bigint;
  if v_added is distinct from coalesce((p->>'added_amount_paise')::bigint, 0) then
    perform _price_mismatch('extension', v_added, (p->>'added_amount_paise')::bigint);
  end if;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_group_extend(uuid, jsonb) is
  'Sync op group.extend: moves a group''s scheduled end and verifies the extension price server-side.';

grant execute on function "public"."op_group_extend"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_extend"(uuid, jsonb) from public;

revoke all on function "public".op_group_extend(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_extend(p_arena uuid, p jsonb) from authenticated;
