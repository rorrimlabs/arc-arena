-- private — SECURITY DEFINER code, kept out of the Data API
--
-- Supabase's rule: a SECURITY DEFINER function never lives in an exposed schema
-- (config.toml [api] schemas = public, graphql_public). The client API's bodies
-- and the RLS helpers live here; `public` keeps only SECURITY INVOKER wrappers
-- with the same names and arguments, so clients call exactly what they did.
--
-- Never add this schema to [api] schemas. `authenticated` needs USAGE (and
-- EXECUTE on each function, granted in its file) because RLS policies and the
-- invoker wrappers run as the caller. `anon` gets nothing.
create schema "private";

comment on schema "private" is 'SECURITY DEFINER bodies of the client API and the RLS helpers; not exposed over the Data API.';

revoke all on schema "private" from public;

revoke all on schema "private" from "anon";

grant usage on schema "private" to "authenticated";

grant usage on schema "private" to "service_role";
