-- assert_controller_free_for_allocation() — trigger: one open allocation per controller
--
-- BEFORE INSERT OR UPDATE OF controller_id, ended_at row trigger
-- (t_controller_free) on controller_allocations. For an open allocation
-- (ended_at is null) it locks the controllers row, then refuses if the
-- controller already has another open allocation: 'controller_taken'. The
-- partial unique index ux_one_open_allocation_per_controller backs the same rule.
-- Server-only: not executable by anon/authenticated.
create or replace function public.assert_controller_free_for_allocation()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
declare busy int;
begin
  if new.ended_at is not null then return new; end if;
  perform 1 from controllers where id = new.controller_id for update;
  select count(*) into busy from controller_allocations
    where controller_id = new.controller_id and ended_at is null and id <> new.id;
  if busy > 0 then
    raise exception 'controller_taken'
      using hint = 'That controller is already in use.';
  end if;
  return new;
end;
$function$;

comment on function public.assert_controller_free_for_allocation() is 'Trigger (controller_allocations): refuse an open allocation for a controller that already has one (controller_taken), serialised by locking the controller row.';

grant execute
  on function "public"."assert_controller_free_for_allocation"()
  to "postgres", "service_role";

revoke all on function "public"."assert_controller_free_for_allocation"() from public;

revoke all on function "public".assert_controller_free_for_allocation() from anon;

revoke all on function "public".assert_controller_free_for_allocation() from authenticated;
