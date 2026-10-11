-- 0014 — API surface hygiene before the first hosted deployment.
--
-- Found by supabase/audit/security_audit.sql:
--   * Trigger functions kept PostgreSQL's default EXECUTE grant to PUBLIC, so
--     anon/authenticated could "call" them (including the SECURITY DEFINER
--     sync_record_delete). Postgres refuses to run a trigger function outside
--     a trigger, so nothing was reachable — but the grant has no purpose, and
--     triggers do not need it: EXECUTE is checked when a trigger is created,
--     not when it fires.
--   * btree_gist was created in `public` "if needed" (0001) and is used by
--     nothing. Supabase's advisor flags extensions in public; move it to the
--     `extensions` schema like every other one.
-- No table, row or client-callable function changes.

do $$
declare f text;
begin
  foreach f in array array[
    'set_updated_at()', 'sync_stamp()', 'sync_record_delete()',
    'assert_resource_free_for_segment()', 'assert_resource_free_for_assignment()',
    'assert_controller_free_for_allocation()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

create schema if not exists extensions;
alter extension btree_gist set schema extensions;
