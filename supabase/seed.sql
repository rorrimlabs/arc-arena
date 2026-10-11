-- Seed data for a single development arena (spec §39). Prices are in paise
-- (₹ × 100) and mirror docs/OWNER_CONFIRMATION.md / spec §5.
--
-- The catalog itself lives in _seed_arena_catalog() (migration 0012) so the dev
-- arena and an arena created in the app through create_arena() start from the
-- same rows — including each game's player mode / local-player limit, which the
-- server's controller checks depend on.

do $$
declare
  v_arena uuid;
begin
  insert into arenas(name) values ('Arena') returning id into v_arena;
  perform _seed_arena_catalog(v_arena);
end $$;
