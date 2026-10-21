-- Default privileges for objects the `postgres` role creates in `private`.
--
-- Same rule as public/default_privileges.sql: a new function is executable only
-- by `postgres` and `service_role`; each file grants `authenticated` explicitly
-- when policies or a public wrapper need it. `anon` never gets anything.

alter default privileges for role "postgres" in schema "private"
  revoke all on functions from public;

alter default privileges for role "postgres" in schema "private"
  grant execute on functions to "service_role";

alter default privileges for role "postgres" in schema "private"
  revoke all on functions from "anon", "authenticated";
