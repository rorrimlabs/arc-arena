-- op_arena_update — sync op 'arena.update': edit the arena's name, area and phone.
--
-- Permission: settings.
-- Payload: name? (1–80 characters after trimming), area? (up to 80 characters; empty clears it),
--   phone? (6–20 of digits, spaces, +, ( ) and -; empty clears it). Only the keys present are
--   written.
-- Checks / errors: forbidden; invalid_name; invalid_area; invalid_phone.
-- Writes: arenas. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_arena_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_name  text := btrim(p->>'name');
  v_area  text := nullif(btrim(p->>'area'), '');
  v_phone text := nullif(btrim(p->>'phone'), '');
begin
  perform _need(p_arena, 'settings');
  if p ? 'name' and (v_name is null or char_length(v_name) not between 1 and 80) then
    raise exception 'invalid_name' using hint = '1–80 characters';
  end if;
  if p ? 'area' and char_length(v_area) > 80 then
    raise exception 'invalid_area' using hint = 'up to 80 characters';
  end if;
  if p ? 'phone' and v_phone !~ '^[0-9+() -]{6,20}$' then
    raise exception 'invalid_phone' using hint = '6–20 digits, spaces, +, ( ) or -';
  end if;
  update arenas set
      name  = case when p ? 'name' then v_name else name end,
      area  = case when p ? 'area' then v_area else area end,
      phone = case when p ? 'phone' then v_phone else phone end,
      updated_at = statement_timestamp()
    where id = p_arena;
  if not found then raise exception 'not_found' using hint = 'arena'; end if;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_arena_update(uuid, jsonb) is
  'Sync op arena.update: edits the arena''s name, area and phone (only the keys sent).';

grant execute on function "public"."op_arena_update"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_arena_update"(uuid, jsonb) from public;

revoke all on function "public".op_arena_update(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_arena_update(p_arena uuid, p jsonb) from authenticated;
