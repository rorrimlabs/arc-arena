-- op_holiday_upsert — sync op 'holiday.upsert': add or edit a holiday on the business calendar.
--
-- Permission: settings.
-- Payload: day (date), name, closed? (default false).
-- Checks / errors: forbidden; invalid_payload / invalid (bad day, missing name).
-- Writes: holidays (upsert on arena_id, day; _sync_apply then retires the previous price list into
--   pricing_catalog_history). Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_holiday_upsert (
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
  insert into holidays(arena_id, day, name, closed)
    values (p_arena, (p->>'day')::date, p->>'name', coalesce((p->>'closed')::boolean, false))
  on conflict (arena_id, day) do update set name = excluded.name, closed = excluded.closed,
      updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_holiday_upsert(uuid, jsonb) is
  'Sync op holiday.upsert: adds or edits the holiday on a given day.';

grant execute on function "public"."op_holiday_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_holiday_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_holiday_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_holiday_upsert(p_arena uuid, p jsonb) from authenticated;
