-- _group_lock(p_arena, p_assignments, p_extra) — lock every station and pad a group op touches.
--
-- Collects each assignment's resource_id, the p_extra stations and the current stations of pads
-- being borrowed (moves), then locks stations (_lock_resources) before pads (_lock_pads), each in
-- id order, to avoid deadlocks. Raises 'retry' (SQLSTATE 40001) if a borrowed pad moved between
-- the read and the lock. Used by op_group_create, op_group_add and op_group_switch.
-- Server-only: not executable by anon/authenticated.
create or replace function public._group_lock (
  p_arena       uuid,
  p_assignments jsonb,
  p_extra       uuid[] default '{}'::uuid[]
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_res uuid[] := p_extra; v_borrow uuid[] := '{}'; v_pads uuid[] := '{}'; a jsonb;
  v_origins uuid[];
begin
  for a in select value from jsonb_array_elements(p_assignments) loop
    v_res := v_res || (a->>'resource_id')::uuid;
    v_borrow := v_borrow || _pad_ids(a->'moves');
    v_pads := v_pads || _pad_ids(a->'allocations');
  end loop;
  v_origins := _pad_origins(p_arena, v_borrow);
  -- Stations before pads, each in id order (same order as the single-session ops).
  perform _lock_resources(p_arena, v_res || v_origins);
  perform _lock_pads(p_arena, v_borrow || v_pads);
  -- A pad that moved between the read and the lock sits at a station we do not hold: retry.
  if not (_pad_origins(p_arena, v_borrow) <@ (v_res || v_origins)) then
    raise exception 'retry' using errcode = '40001';
  end if;
end;
$function$;

comment on function public._group_lock(uuid, jsonb, uuid[]) is 'Locks all stations, then all pads, involved in a group op in a fixed order; raises retry if a borrowed pad moved meanwhile.';

grant execute on function "public"."_group_lock"(uuid, jsonb, uuid[]) to "postgres", "service_role";

revoke all on function "public"."_group_lock"(uuid, jsonb, uuid[]) from public;

revoke all on function "public"._group_lock(p_arena uuid, p_assignments jsonb, p_extra uuid[]) from anon;

revoke all on function "public"._group_lock(p_arena uuid, p_assignments jsonb, p_extra uuid[]) from authenticated;
