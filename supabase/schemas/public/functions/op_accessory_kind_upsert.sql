-- op_accessory_kind_upsert — sync op 'accessory_kind.upsert': create or edit an accessory kind.
--
-- Permission: settings.
-- Payload: id, name, counts_as_controller, sort_order?, active?.
-- Checks / errors: forbidden; invalid_name (1–40 characters); not_found (hint accessory_kind: the
--   id belongs to another arena); accessory_kind_busy (switching counts_as_controller while an
--   accessory of this kind is held by a player); duplicate (name already used, ignoring case).
-- Writes: accessory_kinds. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_accessory_kind_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_name text := btrim(coalesce(p->>'name', ''));
  v_pad  boolean := coalesce((p->>'counts_as_controller')::boolean, false);
  v_old  accessory_kinds%rowtype;
begin
  perform _need(p_arena, 'settings');
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if exists (select 1 from accessory_kinds where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'accessory_kind';
  end if;

  select * into v_old from accessory_kinds where id = v_id and arena_id = p_arena for update;
  if found and v_old.counts_as_controller <> v_pad and exists (
       select 1 from controller_allocations a join controllers c on c.id = a.controller_id
        where c.kind_id = v_id and a.ended_at is null) then
    raise exception 'accessory_kind_busy';
  end if;

  insert into accessory_kinds(id, arena_id, name, counts_as_controller, sort_order, active)
    values (v_id, p_arena, v_name, v_pad, coalesce((p->>'sort_order')::int, 0),
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    name = excluded.name, counts_as_controller = excluded.counts_as_controller,
    sort_order = excluded.sort_order, active = excluded.active, updated_at = statement_timestamp()
  where accessory_kinds.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_accessory_kind_upsert(uuid, jsonb) is
  'Sync op accessory_kind.upsert: creates or edits an accessory kind (Controller, VR headset …).';

grant execute on function "public"."op_accessory_kind_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_accessory_kind_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_accessory_kind_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_accessory_kind_upsert(p_arena uuid, p jsonb) from authenticated;
