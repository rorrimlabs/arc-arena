-- Read-only security audit of the public API surface.
--
-- ONE query, so it runs the same in psql (local stack) and in the hosted
-- project's SQL editor (which shows only one result). It only SELECTs from the
-- system catalogs — safe on any environment.
--
--   local:  docker exec -i supabase_db_arena_ops psql -U postgres -X < supabase/audit/security_audit.sql
--   hosted: Dashboard → SQL Editor → paste this file → Run
--
-- Expected: NO row with status 'FAIL'. Rows with status 'REVIEW' list the
-- intended client API and the installed extensions, for a human to check
-- against docs/DEPLOY_SUPABASE.md.
with
writable as (   -- clients must never write a table directly (sync_push only)
  select 'FAIL' status, 'client can write table/view' check_name,
         c.relname || ' (' || r.rolname || ' ' || p.priv || ')' detail
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   cross join (values ('anon'), ('authenticated')) r(rolname)
   cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) p(priv)
   where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p')
     and has_table_privilege(r.rolname, c.oid, p.priv)),
no_rls as (
  select 'FAIL', 'table without row level security', c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity),
views as (      -- a view runs as its owner and bypasses RLS
  select 'FAIL', 'view readable by a client role', c.relname || ' (' || r.rolname || ')'
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   cross join (values ('anon'), ('authenticated')) r(rolname)
   where n.nspname = 'public' and c.relkind in ('v', 'm')
     and has_table_privilege(r.rolname, c.oid, 'SELECT')),
definer_path as (
  select 'FAIL', 'SECURITY DEFINER without pinned search_path', p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
anon_exec as (
  select 'FAIL', 'anon can execute a public function', p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
     and p.oid not in (select objid from pg_depend where deptype = 'e')),
unexpected_api as (  -- anything signed-in users can call beyond the known API
  select 'FAIL', 'unexpected function callable by authenticated', p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.oid not in (select objid from pg_depend where deptype = 'e')
     and p.proname not in ('sync_push', 'sync_pull', 'sync_fetch_entity', 'my_arenas',
       'create_my_arena', 'invite_member', 'accept_invite', 'revoke_invite', 'arena_invites',
       'arena_staff', 'arena_sales', 'arena_sale', 'arena_pricing', 'app_is_owner')),
definer_api as (     -- Security Advisor 0028/0029: client API bodies live in `private`
  select 'FAIL', 'SECURITY DEFINER function in public executable by a client role',
         p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE'))),
open_policy as (     -- every policy must key off arena membership
  select 'FAIL', 'policy not scoped to arena membership', c.relname || '.' || pol.polname
    from pg_policy pol join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and coalesce(pg_get_expr(pol.polqual, pol.polrelid), '')
         || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') !~ 'app_(owner_)?arena_ids'),
api as (
  select 'REVIEW', 'client API (authenticated may execute)', p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.oid not in (select objid from pg_depend where deptype = 'e')),
ext as (
  select 'REVIEW', 'extension', extname || ' ' || extversion || ' in ' || extnamespace::regnamespace
    from pg_extension)
select * from writable union all select * from no_rls union all select * from views
union all select * from definer_path union all select * from anon_exec
union all select * from unexpected_api union all select * from definer_api union all select * from open_policy
union all select * from api union all select * from ext
order by 1, 2, 3;
