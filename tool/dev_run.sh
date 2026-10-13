#!/usr/bin/env bash
# Runs the staff app in CLOUD mode against the LOCAL Supabase dev stack.
#
# Writes apps/mobile/dart_define.dev.json (git-ignored by `dart_define*.json`)
# with the local API URL and the local PUBLISHABLE key only — never the
# service-role / secret key — and passes it to `flutter run`. Nothing is
# printed. Refuses anything that is not a local stack.
#
#   bash tool/dev_run.sh -d "iPhone 17"      # any flutter run arguments
#   AO_SENTRY_DSN=... bash tool/dev_run.sh   # optional: Sentry for this run
#
# The Sentry DSN is taken from the environment only (never stored in the repo).
# The iOS Simulator reaches the Mac's 127.0.0.1 directly. An Android emulator
# needs http://10.0.2.2:<port> instead (set ANDROID=1).
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|PUBLISHABLE_KEY|ANON_KEY)=' | sed 's/^/export SB_/')"
case "${SB_API_URL:-}" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "refusing: the local stack is not running (supabase start)" >&2; exit 1 ;;
esac
KEY="${SB_PUBLISHABLE_KEY:-${SB_ANON_KEY:-}}"
[ -n "$KEY" ] || { echo "no publishable key in supabase status" >&2; exit 1; }
URL="$SB_API_URL"
[ "${ANDROID:-0}" = "1" ] && URL="${URL/127.0.0.1/10.0.2.2}"
cd apps/mobile
umask 077
cat > dart_define.dev.json <<JSON
{
  "AO_BACKEND": "supabase",
  "AO_SUPABASE_URL": "$URL",
  "AO_SUPABASE_ANON_KEY": "$KEY",
  "AO_SENTRY_DSN": "${AO_SENTRY_DSN:-}",
  "AO_ENVIRONMENT": "${AO_ENVIRONMENT:-development}"
}
JSON
exec flutter run --dart-define-from-file=dart_define.dev.json "$@"
