#!/usr/bin/env bash
# Runs the two-device sync integration test against the LOCAL Supabase dev
# stack (project arena_ops, ports 5443x). The anon key is read from
# `supabase status` into the environment of the test process only — it is
# never printed. Refuses anything that is not a localhost URL, so this can
# never be pointed at a hosted project by accident.
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY)=' | sed 's/^/export SB_/')"
case "${SB_API_URL:-}" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "refusing: API_URL is not a local stack" >&2; exit 1 ;;
esac
export AO_SUPABASE_URL="$SB_API_URL" AO_SUPABASE_ANON_KEY="$SB_ANON_KEY"

# Every run signs up fresh it-*@arena.test accounts and creates an "IT …" arena
# (committed — two devices must see each other). Remove exactly those on exit,
# pass or fail, so the database is left as the run found it and no other suite
# sees them. Only the reserved it-*@arena.test namespace is touched.
cleanup() {
  docker exec -i supabase_db_arena_ops psql -U postgres -X -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
delete from arenas where id in (
  select sp.arena_id from staff_profiles sp join auth.users u on u.id = sp.user_id
   where u.email like 'it-%@arena.test');
delete from auth.users where email like 'it-%@arena.test';
SQL
}
trap cleanup EXIT
flutter test test/sync/ "$@"
