-- op_controller_move — sync op 'controller.move': carry a pad to another station (loan / return
--   home / re-home).
--
-- Permission: loan and returnHome need start OR settings; permanent (re-home) needs settings.
-- Payload: controller_id, kind ('loan' | 'permanent' | 'returnHome'), to_resource_id (ignored for
--   returnHome: the pad goes to its home station), session_ref (loan), move_id?, at? (default
--   server time).
-- Checks / errors: move_kind_invalid; forbidden; controller_missing; resource_missing (target not
--   in this arena, or returnHome with no home); retry (40001: the pad moved or was re-homed
--   between the unlocked read and the locks); controller_in_use (pad has an open allocation).
-- Writes: controllers (location, home, loan fields); controller_moves (only when the pad really
--   moved). Returns: {moved, adjusted}: moved=false when the pad was already at the target
--   (adjusted=true if the device sent a move_id, whose history row is not mirrored); moved=true
--   with adjusted=true when the server generated the history row id.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_controller_move (
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
  v_cid uuid := (p->>'controller_id')::uuid;
  v_kind text := p->>'kind';
  v_to uuid := nullif(p->>'to_resource_id','')::uuid;
  v_loc uuid; v_home uuid; v_loc2 uuid; v_home2 uuid;
begin
  if v_kind is null or v_kind not in ('loan','permanent','returnHome') then
    raise exception 'move_kind_invalid';
  end if;
  -- Carrying a pad (loan / return) is floor work: it needs start or settings
  -- (0016). Re-homing it (permanent) changes the inventory: settings.
  if v_kind in ('loan', 'returnHome')
     and not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'settings')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or settings';
  end if;
  if v_kind = 'permanent' then perform _need(p_arena, 'settings'); end if;
  select current_resource_id, home_resource_id into v_loc, v_home
    from controllers where id = v_cid and arena_id = p_arena;
  if not found then raise exception 'controller_missing'; end if;
  if v_kind = 'returnHome' then v_to := v_home; end if;
  if not exists (select 1 from resources where id = v_to and arena_id = p_arena) then
    raise exception 'resource_missing';
  end if;
  perform _lock_resources(p_arena, array[v_loc, v_to]);
  perform _lock_pads(p_arena, array[v_cid]);
  -- Stations are locked before pads (the order every op uses), so the pad was
  -- read unlocked above. If it moved or was re-homed in between, the stations
  -- we hold are the wrong ones: retry rather than move it unlocked.
  select current_resource_id, home_resource_id into v_loc2, v_home2 from controllers where id = v_cid;
  if v_loc2 is distinct from v_loc or v_home2 is distinct from v_home then
    raise exception 'retry' using errcode = '40001';
  end if;
  if exists (select 1 from controller_allocations where controller_id = v_cid and ended_at is null) then
    raise exception 'controller_in_use';
  end if;
  update controllers
     set current_resource_id = v_to,
         home_resource_id = case when v_kind = 'permanent' then v_to else home_resource_id end,
         loan_return_to   = case when v_kind = 'loan' then v_home::text end,
         loan_session_ref = case when v_kind = 'loan' then p->>'session_ref' end,
         updated_at = v_now
   where id = v_cid;
  if v_to = v_loc then
    -- Nothing physically moved (e.g. a return already done on another device):
    -- the device's history row is not mirrored, so it should refetch.
    return jsonb_build_object('moved', false, 'adjusted', nullif(p->>'move_id','') is not null);
  end if;
  insert into controller_moves(id, arena_id, controller_id, from_resource_id, to_resource_id, kind,
      session_ref, moved_at, created_by, created_at)
    values (coalesce(nullif(p->>'move_id','')::uuid, gen_random_uuid()), p_arena, v_cid, v_loc,
      v_to, v_kind, case when v_kind = 'loan' then p->>'session_ref' end,
      coalesce((p->>'at')::timestamptz, v_now), auth.uid(), v_now);
  -- adjusted: no move_id was sent, so the server minted the history row id; the device refetches.
  return jsonb_build_object('moved', true,
    'adjusted', nullif(p->>'move_id','') is null);
end;
$function$;

comment on function public.op_controller_move(uuid, jsonb) is
  'Sync op controller.move: loans, returns home or permanently re-homes a pad, locking both stations before the pad.';

grant execute on function "public"."op_controller_move"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_controller_move"(uuid, jsonb) from public;

revoke all on function "public".op_controller_move(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_controller_move(p_arena uuid, p jsonb) from authenticated;
