#!/usr/bin/env bash
# Pricing parity: the app (Dart) and the server (migration 0013, plpgsql) must
# price every bill identically, to the paisa. Run this after ANY change to
# lib/domain/pricing, lib/domain/services/{segment,group}_billing.dart,
# lib/domain/services/session_planner.dart, lib/core/money, lib/core/time, or
# the server's _pr_* functions — and in tool/verify_all.sh.
#
#   bash tool/pricing_parity.sh                 # parity + self-tests
#   bash tool/pricing_parity.sh --random 10000  # more random cases
#   bash tool/pricing_parity.sh --seed 7        # another random corpus
#
# Steps: generate.dart prices a fixed boundary corpus + N seeded random cases
# with the app's code; harness.sql re-prices them on the LOCAL dev database
# (function level and through the real sync_push ops), inside one transaction
# that is rolled back. Then two self-tests prove the check can fail: the app's
# expectation skewed by one paisa, and the server's rounding made one paisa
# wrong (inside the rolled-back transaction). Exit 0 only when parity holds AND
# both deliberate errors are caught. Nothing is left in the database.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=supabase_db_arena_ops
RANDOM_N=3000
SEED=20261011
while [ $# -gt 0 ]; do
  case "$1" in
    --random) RANDOM_N="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
docker inspect -f '{{.State.Running}}' "$DB" 2>/dev/null | grep -q true \
  || { echo "local stack not running (supabase start)" >&2; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
docker cp tool/pricing_parity/harness.sql "$DB":/tmp/parity_harness.sql

# run <cases file> <mutate_server> -> prints the PARITY line, returns mismatches
run() {
  docker cp "$1" "$DB":/tmp/parity_cases.ndjson
  local out
  out=$(docker exec -i "$DB" psql -U postgres -X -q -v mutate_server="$2" -f /tmp/parity_harness.sql 2>&1) \
    || { echo "$out" >&2; return 255; }
  echo "$out" | grep -E '^ *[0-9]+ \| (function|operation)' | head -5 | sed 's/^/    /' >&2 || true
  local line; line=$(echo "$out" | grep -o 'PARITY .*' | tr -s ' ')
  echo "  $line" >&2
  local f o
  f=$(echo "$line" | sed -E 's/.*mismatches_function=([0-9]+).*/\1/')
  o=$(echo "$line" | sed -E 's/.*mismatches_operation=([0-9]+).*/\1/')
  echo $((f + o))
}

echo "== generating cases (seed $SEED, $RANDOM_N random + boundary corpus)"
dart run tool/pricing_parity/generate.dart --seed "$SEED" --random "$RANDOM_N" > "$WORK/cases.ndjson" 2>"$WORK/gen.log" \
  || { cat "$WORK/gen.log" >&2; exit 1; }
dart run tool/pricing_parity/generate.dart --seed "$SEED" --random 200 --skew-paise 1 > "$WORK/skew.ndjson" 2>/dev/null

echo "== parity: app vs server"
M=$(run "$WORK/cases.ndjson" false)
echo "== self-test 1: app expectation skewed by one paisa (must be caught)"
S1=$(run "$WORK/skew.ndjson" false)
echo "== self-test 2: server rounding made one paisa wrong (must be caught)"
S2=$(run "$WORK/cases.ndjson" true)

fail=0
[ "$M" = 0 ] && echo "PASS parity: 0 mismatches" || { echo "FAIL parity: $M mismatch(es)"; fail=1; }
[ "$S1" -gt 0 ] && echo "PASS self-test 1: caught ($S1)" || { echo "FAIL self-test 1: a one-paisa app error went unnoticed"; fail=1; }
[ "$S2" -gt 0 ] && echo "PASS self-test 2: caught ($S2)" || { echo "FAIL self-test 2: a one-paisa server error went unnoticed"; fail=1; }
exit $fail
