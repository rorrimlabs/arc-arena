-- op_rule_upsert — sync op 'rule.upsert': create or edit a day/time pricing rule.
--
-- Permission: settings.
-- Payload: id, name, days[] (ISO 1–7), start_min, end_min (IST minutes, end exclusive),
--   holiday_mode? ('any' | 'only' | 'skip'), valid_from?, valid_until? (IST dates),
--   activity_codes[]? (empty = every type), adjust_kind ('percent' | 'per_hour'), adjust_value
--   (signed; percent −100…500, per_hour paise), active?, priority? (a new rule goes last).
-- Checks / errors: forbidden; not_found (hint rule: the id belongs to another arena);
--   invalid_name (1–40 characters); invalid_window (no days, or not 0 ≤ start < end ≤ 1440, or
--   valid_until before valid_from); invalid_adjustment (unknown kind, 0 or out of range);
--   unknown_type (hint: an activity code the arena does not have).
-- Writes: pricing_rules. A price-list change: _sync_apply retires the previous catalog into
--   pricing_catalog_history. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_rule_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_name  text := btrim(coalesce(p->>'name', ''));
  v_days  smallint[] := array(select distinct x::smallint from jsonb_array_elements_text(
                          coalesce(p->'days', '[]'::jsonb)) x order by 1);
  v_codes text[] := array(select distinct upper(btrim(x)) from jsonb_array_elements_text(
                          coalesce(p->'activity_codes', '[]'::jsonb)) x order by 1);
  v_start int := (p->>'start_min')::int;
  v_end   int := (p->>'end_min')::int;
  v_from  date := nullif(p->>'valid_from', '')::date;
  v_until date := nullif(p->>'valid_until', '')::date;
  v_kind  text := p->>'adjust_kind';
  v_value int := (p->>'adjust_value')::int;
  v_bad   text;
  v_prio  int;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from pricing_rules where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'rule';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if cardinality(v_days) = 0 or not v_days <@ array[1,2,3,4,5,6,7]::smallint[]
     or v_start is null or v_end is null or v_start < 0 or v_start >= v_end or v_end > 1440
     or (v_from is not null and v_until is not null and v_until < v_from) then
    raise exception 'invalid_window';
  end if;
  if v_value is null or v_value = 0
     or not ((v_kind = 'percent' and v_value between -100 and 500)
          or (v_kind = 'per_hour' and v_value between -10000000 and 10000000)) then
    raise exception 'invalid_adjustment';
  end if;
  select c into v_bad from unnest(v_codes) c
   where not exists (select 1 from activities where arena_id = p_arena and code = c) limit 1;
  if v_bad is not null then raise exception 'unknown_type' using hint = v_bad; end if;

  select priority into v_prio from pricing_rules where id = v_id for update;
  v_prio := coalesce((p->>'priority')::int, v_prio,
    (select coalesce(max(priority), 0) + 1 from pricing_rules where arena_id = p_arena));

  insert into pricing_rules(id, arena_id, name, priority, active, days, start_min, end_min,
      holiday_mode, valid_from, valid_until, activity_codes, adjust_kind, adjust_value)
    values (v_id, p_arena, v_name, v_prio, coalesce((p->>'active')::boolean, true), v_days,
      v_start, v_end, coalesce(p->>'holiday_mode', 'any'), v_from, v_until, v_codes, v_kind, v_value)
  on conflict (id) do update set
    name = excluded.name, priority = excluded.priority, active = excluded.active,
    days = excluded.days, start_min = excluded.start_min, end_min = excluded.end_min,
    holiday_mode = excluded.holiday_mode, valid_from = excluded.valid_from,
    valid_until = excluded.valid_until, activity_codes = excluded.activity_codes,
    adjust_kind = excluded.adjust_kind, adjust_value = excluded.adjust_value,
    updated_at = statement_timestamp()
  where pricing_rules.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_rule_upsert(uuid, jsonb) is
  'Sync op rule.upsert: creates or edits a day/time pricing rule (percent or paise per hour, by session start).';

grant execute on function "public"."op_rule_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_rule_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_rule_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_rule_upsert(p_arena uuid, p jsonb) from authenticated;
