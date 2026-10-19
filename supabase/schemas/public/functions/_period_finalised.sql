-- _period_finalised(arena, from, to) — does a finalised salary run cover any of these days?
--
-- A finalised run is frozen: attendance corrections and leave changes on its days are refused
-- (period_finalised) and go into the next run as adjustments instead.
-- Takes a share lock on every live run covering the days first, so a change and a finalise of
-- the same days never interleave: a finalise in flight (op_salary_run_finalise holds the run
-- FOR UPDATE) makes the caller wait and then see it finalised, and a finalise waits for a change
-- already past this check to commit, so its rebuild includes it.
-- Server-only: not executable by anon/authenticated.
create or replace function public._period_finalised (
  p_arena uuid,
  p_from  date,
  p_to    date
)
  returns boolean
  language plpgsql
  set search_path to 'public'
  AS $function$
begin
  perform 1 from salary_runs
    where arena_id = p_arena and status <> 'discarded'
      and period_start <= p_to and period_end >= p_from
    for share;
  return exists (select 1 from salary_runs
                  where arena_id = p_arena and status = 'finalised'
                    and period_start <= p_to and period_end >= p_from);
end;
$function$;

comment on function public._period_finalised(uuid, date, date) is 'Internal: true when a finalised salary run covers any day of [from, to].';

grant execute on function "public"."_period_finalised"(uuid, date, date) to "postgres", "service_role";

revoke all on function "public"."_period_finalised"(uuid, date, date) from public;

revoke all on function "public"."_period_finalised"(uuid, date, date) from anon;

revoke all on function "public"."_period_finalised"(uuid, date, date) from authenticated;
