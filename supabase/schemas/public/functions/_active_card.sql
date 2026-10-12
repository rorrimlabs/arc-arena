-- _active_card(p_arena) — id of the arena's active rate card, creating one if none.
--
-- The active rate_cards row with the latest effective_from; if there is none, inserts a card
-- named 'Current' (other columns default) and returns it. Used by op_rate_upsert and op_rate_delete.
-- Server-only: not executable by anon/authenticated.
create or replace function public._active_card (
  p_arena uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v uuid;
begin
  select id into v from rate_cards where arena_id = p_arena and active
    order by effective_from desc limit 1;
  if not found then
    insert into rate_cards(arena_id, name) values (p_arena, 'Current') returning id into v;
  end if;
  return v;
end;
$function$;

comment on function public._active_card(uuid) is 'Returns the arena''s active rate card id, creating a card named Current when none is active.';

grant execute on function "public"."_active_card"(uuid) to "postgres", "service_role";

revoke all on function "public"."_active_card"(uuid) from public;

revoke all on function "public"._active_card(p_arena uuid) from anon;

revoke all on function "public"._active_card(p_arena uuid) from authenticated;
