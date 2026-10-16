set local check_function_bodies = off;

create or replace function private.leave_balances (
  p_arena uuid,
  p_staff uuid default null::uuid
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
