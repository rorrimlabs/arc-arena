-- op_holiday_delete — sync op 'holiday.delete': remove a holiday from the business calendar.
--
-- Permission: settings.
-- Payload: day (date).
-- Checks / errors: forbidden. Deleting a day that is not a holiday succeeds (idempotent).
-- Writes: holidays (_sync_apply then retires the previous price list into
--   pricing_catalog_history). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_holiday_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  delete from holidays where arena_id = p_arena and day = (p->>'day')::date;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_holiday_delete(uuid, jsonb) is
  'Sync op holiday.delete: removes the holiday on a given day (idempotent).';

grant execute on function "public"."op_holiday_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_holiday_delete"(uuid, jsonb) from public;

revoke all on function "public".op_holiday_delete(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_holiday_delete(p_arena uuid, p jsonb) from authenticated;
