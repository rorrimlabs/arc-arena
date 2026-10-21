-- accessory_kind_catalog() — client API: the global list of ready-made accessory types
--
-- What an owner picks from in Settings → Accessory types → From catalog (custom types stay
-- available). Picking one sends the ordinary accessory_kind.upsert with these values, and the
-- owner's copy is then theirs to edit: nothing here is checked by any op.
-- Each entry: name (an accessory_kinds name, 1–40 characters), group (gaming | cue | sports |
-- other, as station_type_catalog) and counts_as_controller (game pads: allocated to players and
-- counted for controller-count pricing; everything else is only tracked physically).
-- Data lives in the function body so it ships with the schema to every environment.
-- Reads no table; runs as the caller.
create or replace function public.accessory_kind_catalog ()
  returns jsonb
  language sql
  immutable
  security invoker
  set search_path to ''
  AS $function$
  select '[
    {"name": "Controller", "group": "gaming", "counts_as_controller": true},
    {"name": "Fight stick", "group": "gaming", "counts_as_controller": true},
    {"name": "VR headset", "group": "gaming", "counts_as_controller": false},
    {"name": "Steering wheel", "group": "gaming", "counts_as_controller": false},
    {"name": "Headphones", "group": "gaming", "counts_as_controller": false},
    {"name": "Cue stick", "group": "cue", "counts_as_controller": false},
    {"name": "Ball set", "group": "cue", "counts_as_controller": false},
    {"name": "Football", "group": "sports", "counts_as_controller": false},
    {"name": "Cricket kit", "group": "sports", "counts_as_controller": false},
    {"name": "Badminton racket", "group": "sports", "counts_as_controller": false},
    {"name": "Bibs", "group": "sports", "counts_as_controller": false}
  ]'::jsonb;
$function$;

comment on function public.accessory_kind_catalog() is 'Client API: the global catalog of ready-made accessory types (name, group, counts_as_controller) an owner picks from; reads no table.';

revoke all on function "public"."accessory_kind_catalog"() from public;

revoke all on function "public".accessory_kind_catalog() from anon;

revoke all on function "public".accessory_kind_catalog() from authenticated;

grant execute on function "public"."accessory_kind_catalog"() to "authenticated", "postgres", "service_role";
