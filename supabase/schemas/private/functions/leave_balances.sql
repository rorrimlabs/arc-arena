-- leave_balances(arena, staff) — paid-leave balance per person for the current leave year
--
-- Lives in `private`; clients reach it only through the SECURITY INVOKER wrapper
-- public.leave_balances.
--
-- One row per person (p_staff, or every employee when null: staff, and an owner only when they
-- are explicitly tracked as working here, _staff_hr.tracks) for the leave year containing
-- today (IST): {staff_id, staff_name, active, joined_on, year_start, year_end, allowance,
-- adjustments, used, pending, balance} (_leave_balance).
-- Who: your own p_staff always; anyone else (or null) needs leave_approve or payroll.
-- Errors: forbidden. SECURITY DEFINER.
-- Client API: callable by signed-in users (authenticated).
create or replace function private.leave_balances (
  p_arena uuid,
  p_staff uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_today date := _pr_ist_date(statement_timestamp());
begin
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  if (p_staff is null or not exists (select 1 from staff_profiles
        where id = p_staff and arena_id = p_arena and user_id = auth.uid()))
     and not exists (select 1 from private.app_arena_ids_with(array['leave_approve', 'payroll']) a
                      where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs leave_approve';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('staff_id', s.id, 'staff_name', s.name, 'active', s.active,
             'joined_on', h.joined_on) || _leave_balance(s.id, v_today) order by s.sort_order, s.name)
      from staff_profiles s
      cross join lateral _staff_hr(s.id) h
     where s.arena_id = p_arena
       and (case when p_staff is not null then s.id = p_staff
                 else s.role <> 'owner' or h.tracks end)), '[]'::jsonb);
end;
$function$;

comment on function private.leave_balances(uuid, uuid) is 'Client API: paid-leave allowance, used, pending and balance per person for the current leave year — your own, or everyone''s with leave_approve / payroll.';

grant execute on function "private"."leave_balances"(uuid, uuid) to "authenticated", "postgres", "service_role";

revoke all on function "private"."leave_balances"(uuid, uuid) from public;

revoke all on function "private"."leave_balances"(uuid, uuid) from anon;
