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

# Every run creates fresh it-*@arena.test logins and an "IT …" arena
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

# Provision the run's two logins the way the owner does (migration 0015): sign-
# up is off, so they are created through the Auth ADMIN API — the scripted
# equivalent of the dashboard's "Add user" — and the owner is attached with
# bootstrap_owner. The local service key is read into a NON-exported shell
# variable used only by these curl calls; it is never printed and never reaches
# the Flutter test process (which gets only the URL and the anon key).
SERVICE_KEY=$(supabase status -o env 2>/dev/null | grep -E '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '"')
RUN=$(uuidgen | tr 'A-Z' 'a-z' | cut -c1-8)
export AO_IT_RUN="$RUN"
export AO_IT_OWNER_EMAIL="it-owner-$RUN@arena.test" AO_IT_STAFF_EMAIL="it-staff-$RUN@arena.test"
for EMAIL in "$AO_IT_OWNER_EMAIL" "$AO_IT_STAFF_EMAIL"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$SB_API_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"it-pass-$EMAIL\",\"email_confirm\":true}")
  [ "$code" = 200 ] || { echo "could not create test login (HTTP $code)" >&2; exit 1; }
done
unset SERVICE_KEY
AO_IT_ARENA=$(docker exec -i supabase_db_arena_ops psql -U postgres -X -q -t -A -v ON_ERROR_STOP=1 \
  -c "select bootstrap_owner('$AO_IT_OWNER_EMAIL', 'IT $RUN', 'Owner A')")
export AO_IT_ARENA
flutter test test/sync/ "$@"
