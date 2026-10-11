#!/usr/bin/env bash
# Runs the app in CLOUD mode against the LOCAL Supabase dev stack.
#
# Writes dart_define.dev.json (git-ignored by `dart_define*.json`) with the
# local API URL and the local ANON (public) key only — never the service-role
# or secret key — and passes it to `flutter run`. Nothing is printed.
#
#   bash tool/dev_run.sh -d "iPhone 17"      # any flutter run arguments
#
# The iOS Simulator reaches the Mac's 127.0.0.1 directly. An Android emulator
# needs AO_SUPABASE_URL=http://10.0.2.2:54431 instead (set ANDROID=1).
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY)=' | sed 's/^/export SB_/')"
case "${SB_API_URL:-}" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "refusing: the local stack is not running (supabase start)" >&2; exit 1 ;;
esac
URL="$SB_API_URL"
[ "${ANDROID:-0}" = "1" ] && URL="${URL/127.0.0.1/10.0.2.2}"
umask 077
cat > dart_define.dev.json <<JSON
{
  "AO_BACKEND": "supabase",
  "AO_SUPABASE_URL": "$URL",
  "AO_SUPABASE_ANON_KEY": "$SB_ANON_KEY"
}
JSON
exec flutter run --dart-define-from-file=dart_define.dev.json "$@"
