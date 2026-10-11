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
exec flutter test test/sync/ "$@"
