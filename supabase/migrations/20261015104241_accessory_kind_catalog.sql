set local check_function_bodies = off;

create or replace function public.accessory_kind_catalog()
  returns jsonb
  language sql
  immutable
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

comment on function "public"."accessory_kind_catalog"() is 'Client API: the global catalog of ready-made accessory types (name, group, counts_as_controller) an owner picks from; reads no table.';

revoke all on function "public"."accessory_kind_catalog"() from public;

grant execute
  on function "public"."accessory_kind_catalog"()
  to "authenticated", "postgres", "service_role";
