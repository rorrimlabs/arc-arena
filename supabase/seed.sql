-- Seed data for a single development arena (spec §39). Prices are in paise
-- (₹ × 100) and mirror docs/OWNER_CONFIRMATION.md / spec §5. LOCAL ONLY: never
-- apply this to a hosted project.
--
-- The catalog itself lives in _seed_arena_catalog() so this dev arena and a
-- real arena created with bootstrap_owner() start from the same rows —
-- including each game's player mode / local-player limit, which the server's
-- controller checks depend on.
--
-- The seeded arena has no owner. To sign in locally, create a login (Studio →
-- Authentication → Add user, Auto Confirm) and attach it to a NEW arena with:
--   select bootstrap_owner('you@arena.test', '404 Arena', 'Your Name');

do $$
declare
  v_arena uuid;
begin
  insert into arenas(name) values ('Arena') returning id into v_arena;
  perform _seed_arena_catalog(v_arena);
end $$;
