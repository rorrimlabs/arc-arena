-- _floor_options(p) — validate and normalise the arena's floor options (settings key
--   'floor_options').
--
-- Shape: {payment_methods: [...], start_presets: [...], warn_minutes: n}, nothing else.
--   payment_methods: one or more of cash, upi, card, other (the methods staff are offered; the
--     server still records any known method, so a payment taken offline is never refused);
--   start_presets: 1–8 whole durations of 5–720 minutes (the choices when starting a session);
--   warn_minutes: 1–30 (how long before the booked end the floor warns staff).
-- Returns the same object with duplicates removed and lists sorted. Raises invalid_floor_options
-- (hint names the bad field) otherwise.
-- Server-only: used by op_settings_save; not executable by anon/authenticated.
create or replace function public._floor_options (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  v_methods text[];
  v_presets int[];
  v_warn    numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('payment_methods', 'start_presets', 'warn_minutes')) then
    raise exception 'invalid_floor_options'
      using hint = 'an object of payment_methods, start_presets and warn_minutes';
  end if;

  if jsonb_typeof(p->'payment_methods') is distinct from 'array' then
    raise exception 'invalid_floor_options' using hint = 'payment_methods';
  end if;
  select array_agg(distinct m order by m) into v_methods
    from jsonb_array_elements_text(p->'payment_methods') m;
  if v_methods is null or not (v_methods <@ array['cash', 'upi', 'card', 'other']) then
    raise exception 'invalid_floor_options'
      using hint = 'payment_methods: one or more of cash, upi, card, other';
  end if;

  if jsonb_typeof(p->'start_presets') is distinct from 'array'
     or exists (select 1 from jsonb_array_elements(p->'start_presets') e
                 where jsonb_typeof(e) <> 'number' or (e::text)::numeric % 1 <> 0) then
    raise exception 'invalid_floor_options' using hint = 'start_presets: whole minutes';
  end if;
  select array_agg(distinct (e::text)::int order by (e::text)::int) into v_presets
    from jsonb_array_elements(p->'start_presets') e;
  if v_presets is null or cardinality(v_presets) > 8
     or exists (select 1 from unnest(v_presets) x where x < 5 or x > 720) then
    raise exception 'invalid_floor_options'
      using hint = 'start_presets: 1–8 durations of 5–720 minutes';
  end if;

  if jsonb_typeof(p->'warn_minutes') is distinct from 'number' then
    raise exception 'invalid_floor_options' using hint = 'warn_minutes';
  end if;
  v_warn := (p->>'warn_minutes')::numeric;
  if v_warn % 1 <> 0 or v_warn < 1 or v_warn > 30 then
    raise exception 'invalid_floor_options' using hint = 'warn_minutes: 1–30';
  end if;

  return jsonb_build_object('payment_methods', to_jsonb(v_methods),
    'start_presets', to_jsonb(v_presets), 'warn_minutes', v_warn::int);
end;
$function$;

comment on function public._floor_options(jsonb) is
  'Validates and normalises the floor_options setting (payment methods offered, session start presets, end-of-session warning minutes); raises invalid_floor_options.';

grant execute on function "public"."_floor_options"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_floor_options"(jsonb) from public;

revoke all on function "public"._floor_options(p jsonb) from anon;

revoke all on function "public"._floor_options(p jsonb) from authenticated;
