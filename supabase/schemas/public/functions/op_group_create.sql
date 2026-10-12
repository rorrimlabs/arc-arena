-- op_group_create — sync op 'group.create': start a group session with its initial player
--   assignments.
--
-- Permission: start.
-- Payload: id, primary_customer_id, player_count, purchased_controller_count? (default 0),
--   started_at, scheduled_end_at, pricing_snapshot (incl. policy), billing_mode? (default
--   'per_system'); assignments[] {id, player_number, player_label, resource_id, activity_code,
--   game_id?, controller_count?, allocations[] {id?, controller_id}, moves[] {id?, controller_id},
--   idx?}.
-- Checks / errors: forbidden; no_assignments; retry (40001); placement errors per assignment
--   (_group_place -> _group_assignable): resource_missing, resource_unavailable, mode_locked,
--   not_playable, resource_busy (single session on the station, or another group),
--   controllers_exceeded (> 4 on the station), players_exceeded (game player limit),
--   controllers_unavailable, game_conflict (sharing a station with a different activity/game);
--   then pad errors from _pad_borrow / _pad_allocate: controller_missing, controller_unusable,
--   controller_taken (open allocation, or an untracked count-only player at that station),
--   controller_duplicate, controller_elsewhere (allocated pad not at the target station);
--   pricing_snapshot_mismatch (price list is neither the live one nor one retired within the grace
--   window, or billing_mode differs from the snapshot policy's group_billing_mode); duplicate /
--   missing_reference.
-- Writes: group_sessions, group_assignments, controllers + controller_moves,
--   controller_allocations, games.last_played_at, customers.last_visit_at. Returns: {group_id,
--   adjusted}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_create (
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
  v_group uuid := (p->>'id')::uuid;
  v_started timestamptz := (p->>'started_at')::timestamptz;
  v_skipped int := 0; a jsonb;
begin
  perform _need(p_arena, 'start');
  if jsonb_array_length(coalesce(p->'assignments', '[]'::jsonb)) = 0 then
    raise exception 'no_assignments';
  end if;
  -- Every target station and borrowed-pad origin, then the pads, in uuid order.
  perform _group_lock(p_arena, p->'assignments');
  insert into group_sessions(id, arena_id, primary_customer_id, player_count,
      purchased_controller_count, status, payment_status, started_at, scheduled_end_at,
      pricing_snapshot, policy_snapshot, billing_mode, created_by, created_at, updated_at)
    values (v_group, p_arena, (p->>'primary_customer_id')::uuid, (p->>'player_count')::int,
      coalesce((p->>'purchased_controller_count')::int, 0), 'active', 'unpaid', v_started,
      (p->>'scheduled_end_at')::timestamptz, p->'pricing_snapshot',
      p->'pricing_snapshot'->'policy', coalesce(nullif(p->>'billing_mode',''), 'per_system'),
      auth.uid(), v_now, v_now);
  -- Device order: each check sees the players placed before it (as on device).
  for a in select value from jsonb_array_elements(p->'assignments') loop
    v_skipped := v_skipped + _group_place(p_arena, v_group, a, v_started,
      coalesce((a->>'idx')::int, 0), null);
  end loop;
  update customers set last_visit_at = v_started, updated_at = v_now
    where id = (p->>'primary_customer_id')::uuid and arena_id = p_arena;

  -- The frozen price list must be this arena's current one, and the group's
  -- billing mode must be the one that price list prescribes (0013).
  perform _assert_snapshot(p_arena, p->'pricing_snapshot');
  if coalesce(nullif(p->>'billing_mode', ''), 'per_system')
     <> _pr_policy(p->'pricing_snapshot')->>'group_billing_mode' then
    raise exception 'pricing_snapshot_mismatch'
      using hint = 'billing_mode differs from the price list''s group billing mode';
  end if;
  return jsonb_build_object('group_id', v_group, 'adjusted', v_skipped > 0);
end;
$function$;

comment on function public.op_group_create(uuid, jsonb) is
  'Sync op group.create: starts a group session and places every player, then verifies the frozen price list and billing mode.';

grant execute on function "public"."op_group_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_create"(uuid, jsonb) from public;

revoke all on function "public".op_group_create(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_create(p_arena uuid, p jsonb) from authenticated;
