-- op_staff_holiday_delete — sync op 'staff_holiday.delete': remove the staff holiday on a day
--
-- Permission: settings. Payload: day. A missing day is a no-op.
-- Writes: staff_holidays (delete). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_staff_holiday_delete (
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
  delete from staff_holidays where arena_id = p_arena and day = (p->>'day')::date;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_staff_holiday_delete(uuid, jsonb) is 'Sync op staff_holiday.delete: remove the staff holiday on an IST day.';

grant execute on function "public"."op_staff_holiday_delete"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_staff_holiday_delete"(uuid, jsonb) from public;

revoke all on function "public"."op_staff_holiday_delete"(uuid, jsonb) from anon;

revoke all on function "public"."op_staff_holiday_delete"(uuid, jsonb) from authenticated;
