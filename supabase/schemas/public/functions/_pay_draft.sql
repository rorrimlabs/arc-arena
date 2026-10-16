-- _pay_draft(arena, run) — lock a salary run of this arena and require it to be a draft
--
-- Raises not_found (hint run) or run_not_draft. Returns the locked run.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pay_draft (
  p_arena uuid,
  p_run   uuid
)
  returns salary_runs
  language plpgsql
  set search_path to 'public'
  AS $function$
declare r salary_runs;
begin
  select * into r from salary_runs where id = p_run and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'salary run'; end if;
  if r.status <> 'draft' then raise exception 'run_not_draft' using hint = r.status; end if;
  return r;
end;
$function$;

comment on function public._pay_draft(uuid, uuid) is 'Internal: lock an arena''s salary run and raise run_not_draft unless it is a draft.';

grant execute on function "public"."_pay_draft"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_pay_draft"(uuid, uuid) from public;

revoke all on function "public"."_pay_draft"(uuid, uuid) from anon;

revoke all on function "public"."_pay_draft"(uuid, uuid) from authenticated;
