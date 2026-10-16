-- _staff_hr(staff) — a staff profile's HR facts, defaults filled in
--
-- From staff_hr_profiles when there is a row, else the defaults: joined on the profile's
-- creation date (IST), not left, tracked unless role owner, the arena's standard day
-- (_work_hours) and paid-leave allowance (_leave_rules). One row, or none for an unknown id.
-- Server-only: not executable by anon/authenticated.
create or replace function public._staff_hr (
  p_staff uuid
)
  returns table (
    arena_id         uuid,
    name             text,
    role             text,
    active           boolean,
    joined_on        date,
    left_on          date,
    tracks           boolean,
    standard_day_min integer,
    paid_leave_days  numeric
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select sp.arena_id, sp.name, sp.role, sp.active,
         coalesce(h.joined_on, _pr_ist_date(sp.created_at)),
         h.left_on,
         coalesce(h.tracks_attendance, sp.role <> 'owner'),
         coalesce(h.standard_day_min, (_work_hours(sp.arena_id)->>'standard_day_min')::int),
         coalesce(h.paid_leave_days, (_leave_rules(sp.arena_id)->>'paid_leave_days')::numeric)
    from staff_profiles sp
    left join staff_hr_profiles h on h.staff_id = sp.id
   where sp.id = p_staff;
$function$;

comment on function public._staff_hr(uuid) is 'Internal: a staff profile''s joining/leaving dates, tracking, standard day and paid-leave allowance, defaults filled in.';

grant execute on function "public"."_staff_hr"(uuid) to "postgres", "service_role";

revoke all on function "public"."_staff_hr"(uuid) from public;

revoke all on function "public"."_staff_hr"(uuid) from anon;

revoke all on function "public"."_staff_hr"(uuid) from authenticated;
