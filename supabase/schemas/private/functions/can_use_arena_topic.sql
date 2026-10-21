-- can_use_arena_topic(topic) — may the caller use this Realtime channel?
--
-- Lives in `private` (not exposed by the Data API). Called by the RLS policies
-- on realtime.messages (realtime/policies.sql), which Supabase Realtime
-- evaluates as the connecting user when a client joins a private channel and
-- when it sends a broadcast. The apps use one channel per arena, topic
-- 'arena:<arena uuid>'. True only for that exact shape and an active
-- staff_profiles row of auth.uid() in that arena — so a non-member, a
-- deactivated member or another arena's user can neither listen nor send. Any
-- other topic is refused (no casts on malformed input: the CASE guards it).
-- Realtime caches the result per connection until the client's JWT is
-- refreshed (≤ jwt_expiry), so a revocation takes effect within that window.
create or replace function private.can_use_arena_topic (
  p_topic text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select case
    when p_topic ~ '^arena:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (select 1 from staff_profiles
                  where user_id = auth.uid() and active and arena_id = substr(p_topic, 7)::uuid)
    else false
  end;
$function$;

comment on function private.can_use_arena_topic(text) is 'True when the topic is arena:<uuid> and the caller is an active member of that arena. Used by the realtime.messages policies (private channels).';

grant execute
  on function "private"."can_use_arena_topic"(text)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."can_use_arena_topic"(text) from public;

revoke all on function "private".can_use_arena_topic(p_topic text) from anon;
