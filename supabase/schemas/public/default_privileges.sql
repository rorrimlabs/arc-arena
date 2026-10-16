-- Default privileges for objects the `postgres` role creates in `public`.
--
-- Secure by default: a new table, function or sequence is reachable only by
-- `postgres` and `service_role`. The client roles (`anon`, `authenticated`)
-- get NOTHING automatically — every grant they hold is written explicitly in
-- that object's own file, so exposing something through the Data API is
-- always a deliberate, reviewable line.
--
-- Note: pg-delta replays these files into a shadow database. Each object file
-- still carries its own explicit `revoke ... from anon/authenticated`, so the
-- result does not depend on the order in which defaults are applied.

alter default privileges for role "postgres" in schema "public"
  grant select, update, usage on sequences to "service_role";

alter default privileges for role "postgres" in schema "public"
  revoke all on sequences from "anon", "authenticated";

alter default privileges for role "postgres" in schema "public"
  revoke all on functions from public;

alter default privileges for role "postgres" in schema "public"
  grant execute on functions to "service_role";

alter default privileges for role "postgres" in schema "public"
  revoke all on functions from "anon", "authenticated";

alter default privileges for role "postgres" in schema "public"
  grant delete, insert, maintain, references, select, trigger, truncate, update
  on tables to "service_role";

alter default privileges for role "postgres" in schema "public"
  revoke all on tables from "anon", "authenticated";
