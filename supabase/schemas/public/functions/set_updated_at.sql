-- set_updated_at() — trigger: bump updated_at on update
--
-- BEFORE UPDATE row trigger (t_<table>_updated) on tables with updated_at.
-- Sets updated_at = now() (transaction start time) only when the UPDATE did
-- not change updated_at itself, so an explicit value (op_* functions set
-- statement_timestamp()) is kept.
-- Server-only: not executable by anon/authenticated.
create or replace function public.set_updated_at()
  returns trigger
  language plpgsql
  set search_path to 'public', 'extensions'
  AS $function$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$function$;

comment on function public.set_updated_at() is 'Trigger (before update): set updated_at to now() unless the update already set it explicitly.';

grant execute on function "public"."set_updated_at"() to "postgres", "service_role";

revoke all on function "public"."set_updated_at"() from public;

revoke all on function "public".set_updated_at() from anon;

revoke all on function "public".set_updated_at() from authenticated;
