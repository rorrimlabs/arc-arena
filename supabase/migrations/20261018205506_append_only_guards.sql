set local check_function_bodies = off;

create or replace function public._append_only()
  returns trigger
  language plpgsql
  set search_path to 'public'
  AS $function$
begin
  raise exception 'append_only' using errcode = '55000',
    hint = tg_table_name || ' rows are never ' || lower(tg_op) || 'd: record a correction instead';
end;
$function$;

create trigger t_bill_discounts_append_only
  before delete or update on public.bill_discounts
  for each row
  execute function public._append_only();

create trigger t_group_charges_append_only
  before delete or update on public.group_charges
  for each row
  execute function public._append_only();

create trigger t_group_payments_append_only
  before delete or update on public.group_payments
  for each row
  execute function public._append_only();

create trigger t_payments_append_only
  before delete or update on public.payments
  for each row
  execute function public._append_only();

create trigger t_session_charges_append_only
  before delete or update on public.session_charges
  for each row
  execute function public._append_only();

comment on function "public"."_append_only"() is 'Trigger (before update or delete on money, audit and evidence tables): raise append_only; corrections are new rows.';

revoke all on function "public"."_append_only"() from public;

grant execute on function "public"."_append_only"() to "postgres", "service_role";
