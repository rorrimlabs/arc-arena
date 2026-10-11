-- arena_ops — explicit controller moves, server mirror.
--
-- 0008 made controller_moves RPC-only, which left the two moves that happen
-- outside a session transaction without a server write path: the owner
-- re-homing a pad (permanent) and staff carrying a pad around the floor (loan)
-- or back to its home station (returnHome — the "Returned" action on the
-- end/bill sheets and the controller board). move_controller mirrors
-- LocalControllerAllocationRepository.moveController; like 0007/0008 it MIRRORS
-- the on-device rules, it does not replace them.

-- move_controller: carry one pad (brief §5).
--   loan       -> p_to_resource; owes a return to its home (loan_return_to /
--                 loan_session_ref = p_session_ref).
--   permanent  -> p_to_resource becomes its new home; any loan is cleared.
--                 Owner-only: it changes the inventory, not just the floor.
--   returnHome -> back to home_resource_id (p_to_resource is ignored); loan
--                 cleared.
-- As on the device, the controller row is always written (so e.g. returnHome
-- on a pad already home still clears a stale loan), but a controller_moves row
-- is appended only when the pad actually changes place — a same-place move,
-- including a sync retry of one already applied, records no history. Refused
-- for a pad held by an open allocation: it is in a player's hands, and the
-- session flows move such pads themselves. Returns whether a move was recorded.
create or replace function move_controller(
  p_arena       uuid,
  p_controller  uuid,
  p_kind        text,
  p_to_resource uuid        default null,
  p_session_ref text        default null,
  p_at          timestamptz default null
) returns boolean as $$
declare
  v_now  timestamptz := statement_timestamp();
  v_loc  uuid;
  v_home uuid;
  v_to   uuid;
begin
  if p_arena not in (select app_arena_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('loan', 'permanent', 'returnHome') then
    raise exception 'move_kind_invalid' using hint = coalesce(p_kind, 'null');
  end if;
  if p_kind = 'permanent' and not app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'permanent move is owner-only';
  end if;

  select current_resource_id, home_resource_id into v_loc, v_home
    from controllers where id = p_controller and arena_id = p_arena for update;
  if not found then raise exception 'controller_missing'; end if;

  if exists (select 1 from controller_allocations
               where controller_id = p_controller and ended_at is null) then
    raise exception 'controller_in_use';
  end if;

  if p_kind = 'returnHome' then
    v_to := v_home;
  else
    perform 1 from resources where id = p_to_resource and arena_id = p_arena;
    if not found then raise exception 'resource_missing'; end if;
    v_to := p_to_resource;
  end if;

  update controllers
     set current_resource_id = v_to,
         home_resource_id    = case when p_kind = 'permanent' then v_to else home_resource_id end,
         loan_return_to      = case when p_kind = 'loan' then v_home::text end,
         loan_session_ref    = case when p_kind = 'loan' then p_session_ref end
   where id = p_controller;

  if v_to = v_loc then return false; end if;
  insert into controller_moves(arena_id, controller_id, from_resource_id, to_resource_id,
      kind, session_ref, moved_at, created_by, created_at)
    values (p_arena, p_controller, v_loc, v_to, p_kind,
      case when p_kind = 'loan' then p_session_ref end,
      coalesce(p_at, v_now), auth.uid(), v_now);
  return true;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function move_controller(uuid, uuid, text, uuid, text, timestamptz)
  from anon, public;
grant execute on function move_controller(uuid, uuid, text, uuid, text, timestamptz)
  to authenticated;
