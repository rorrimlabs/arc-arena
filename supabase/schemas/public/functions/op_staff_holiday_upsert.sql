-- op_staff_holiday_upsert — sync op 'staff_holiday.upsert': add or rename a staff holiday
--
-- Permission: settings.
-- Payload: day (IST date), name, paid (default true).
-- Checks / errors: forbidden; invalid_payload (hint day / name).
-- Writes: staff_holidays (one row per day). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_staff_holiday_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_name text := btrim(coalesce(p->>'name', ''));
begin
  perform _need(p_arena, 'settings');
  if p->>'day' is null then raise exception 'invalid_payload' using hint = 'day'; end if;
  if v_name = '' or length(v_name) > 80 then
    raise exception 'invalid_payload' using hint = 'name: 1–80 characters';
  end if;
  insert into staff_holidays(arena_id, day, name, paid)
    values (p_arena, (p->>'day')::date, v_name, coalesce((p->>'paid')::boolean, true))
  on conflict (arena_id, day) do update set name = excluded.name, paid = excluded.paid;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_staff_holiday_upsert(uuid, jsonb) is 'Sync op staff_holiday.upsert: add or edit the staff holiday on an IST day (paid by default).';

grant execute on function "public"."op_staff_holiday_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_staff_holiday_upsert"(uuid, jsonb) from public;

revoke all on function "public"."op_staff_holiday_upsert"(uuid, jsonb) from anon;

revoke all on function "public"."op_staff_holiday_upsert"(uuid, jsonb) from authenticated;
