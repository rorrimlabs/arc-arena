-- Realtime Authorization for the apps' private channels (realtime.messages)
--
-- Both apps open one PRIVATE channel per arena, topic 'arena:<arena uuid>'
-- (config private: true). Supabase Realtime checks these policies when a client
-- joins (it needs at least one of them to pass) and when it sends a broadcast;
-- private.can_use_arena_topic admits only active members of that arena.
-- Broadcasts only carry "something changed, pull" nudges — the data itself is
-- always read through RLS-checked queries or sync_pull. Postgres Changes rows
-- are filtered by each table's own RLS.
--
-- The realtime schema is Supabase-managed (locked since 2026-07): only
-- policies on realtime.messages may be added here; RLS on the table is already
-- enabled by Supabase (never alter the table itself).
create policy "arena_members_receive" on "realtime"."messages"
  for select
  to authenticated
  using (((extension = ANY (ARRAY['broadcast'::text, 'presence'::text]))
          AND private.can_use_arena_topic((select realtime.topic()))));

create policy "arena_members_send" on "realtime"."messages"
  for insert
  to authenticated
  with check (((extension = 'broadcast'::text)
               AND private.can_use_arena_topic((select realtime.topic()))));
