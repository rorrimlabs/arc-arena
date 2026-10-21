-- _leave_balance(staff, day) — the paid-leave balance of the leave year containing p_day
--
-- allowance (_staff_hr.paid_leave_days) + adjustments of that year − used (paid units of
-- approved / cancel_pending requests on days of that year) = balance; pending = days of pending
-- requests starting in that year. Returns {year_start, year_end, allowance, adjustments, used,
-- pending, balance}.
-- Server-only: not executable by anon/authenticated.
create or replace function public._leave_balance (
  p_staff uuid,
  p_day   date
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  with y as (
    select _leave_year_start(p_staff, p_day) as ys,
           (_leave_year_start(p_staff, p_day) + interval '1 year' - interval '1 day')::date as ye,
           (select paid_leave_days from _staff_hr(p_staff)) as allowance
  ), parts as (
    select y.*,
      coalesce((select sum(a.days) from leave_adjustments a
                 where a.staff_id = p_staff and a.year_start = y.ys), 0) as adjustments,
      coalesce((select sum((x->>'paid_units')::numeric)
                  from leave_requests r, jsonb_array_elements(r.day_split) x
                 where r.staff_id = p_staff and r.status in ('approved', 'cancel_pending')
                   and (x->>'day')::date between y.ys and y.ye), 0) as used,
      coalesce((select sum(r.days) from leave_requests r
                 where r.staff_id = p_staff and r.status = 'pending'
                   and r.from_date between y.ys and y.ye), 0) as pending
      from y
  )
  select jsonb_build_object('year_start', ys, 'year_end', ye, 'allowance', allowance,
           'adjustments', adjustments, 'used', used, 'pending', pending,
           'balance', allowance + adjustments - used)
    from parts;
$function$;

comment on function public._leave_balance(uuid, date) is 'Internal: paid-leave allowance, adjustments, used, pending and balance for the leave year containing an IST day.';

grant execute on function "public"."_leave_balance"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_leave_balance"(uuid, date) from public;

revoke all on function "public"."_leave_balance"(uuid, date) from anon;

revoke all on function "public"."_leave_balance"(uuid, date) from authenticated;
