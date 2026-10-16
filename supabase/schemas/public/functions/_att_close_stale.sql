-- _att_close_stale(arena, staff, now) — close clock-ins nobody can still be working on
--
-- An active open entry whose clock-in is older than the arena's max_open_hours was forgotten:
-- it is closed at _att_close_time (the shift end, else clock-in + standard day), with
-- out_source 'auto', flag auto_out and review pending. One person (p_staff) or the whole arena
-- (null). Run before attendance is read for days (attendance_days) or paid (salary runs), so
-- every reader sees the same closed stretch. Returns how many entries it closed.
-- Server-only: not executable by anon/authenticated.
create or replace function public._att_close_stale (
  p_arena uuid,
  p_staff uuid,
  p_now   timestamp with time zone
)
  returns integer
  language plpgsql
  set search_path to 'public'
  AS $function$
declare v_n int;
begin
  update attendance_entries e
     set out_at = _att_close_time(e.staff_id, e.work_date, e.in_at),
         out_source = 'auto',
         flags = array(select distinct f from unnest(e.flags || '{auto_out}'::text[]) f order by f),
         review = 'pending'
   where e.arena_id = p_arena
     and (p_staff is null or e.staff_id = p_staff)
     and e.status = 'active' and e.out_at is null
     and e.in_at + make_interval(hours => (_attendance_rules(p_arena)->>'max_open_hours')::int) < p_now;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

comment on function public._att_close_stale(uuid, uuid, timestamp with time zone) is 'Internal: close forgotten clock-ins (open past max_open_hours) at the shift end / standard day, flagged auto_out for review.';

grant execute on function "public"."_att_close_stale"(uuid, uuid, timestamp with time zone) to "postgres", "service_role";

revoke all on function "public"."_att_close_stale"(uuid, uuid, timestamp with time zone) from public;

revoke all on function "public"."_att_close_stale"(uuid, uuid, timestamp with time zone) from anon;

revoke all on function "public"."_att_close_stale"(uuid, uuid, timestamp with time zone) from authenticated;
