#!/usr/bin/env bash
# One local verification entry point, in a fixed order. Every step runs even if
# an earlier one fails, each is reported on its own (PASS / FAIL / SKIP + why),
# and the exit code is non-zero if ANY step failed — a later pass never hides an
# earlier failure. Nothing here is destructive and nothing touches a hosted
# project: database steps use the local stack (`supabase start`) only.
#
#   bash tool/verify_all.sh                  # static checks + unit tests + local DB
#   bash tool/verify_all.sh --with-it        # + cross-app integration (tool/sync_it.sh)
#   bash tool/verify_all.sh --with-psql      # + pricing parity and concurrency races
#                                            #   (they talk to the DB container with
#                                            #   docker exec psql, inside rolled-back
#                                            #   transactions / their own fixture arena)
#
# Steps:
#   1 flutter analyze                        (apps/mobile)
#   2 flutter test                           (unit/widget; integration tests skip themselves)
#   3 admin unit tests                       (apps/admin: ng test)
#   4 admin build (development config)       (output to a temp dir; the production
#                                             config inlines Google Fonts = network)
#   5 supabase test db --local               (pgTAP; every file in its own arena, rolled back)
#   6 supabase db advisors --local           (security + performance lints; must be empty)
#   7 cross-app integration                  (--with-it)
#   8 pricing parity                         (--with-psql)
#   9 concurrency: station race / pad races  (--with-psql)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
WITH_IT=0; WITH_PSQL=0
for a in "$@"; do
  case "$a" in
    --with-it) WITH_IT=1 ;;
    --with-psql) WITH_PSQL=1 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
SUPABASE=${SUPABASE_BIN:-supabase}
LOG=$(mktemp -d)
declare -a NAMES RESULTS

summary() {
  grep -hoE 'No issues found!|All tests passed!|[0-9]+ passed|Tests +[0-9]+ passed[^)]*\)?|Files=[0-9]+, Tests=[0-9]+|Result: PASS|"results":\[\]|Application bundle generation complete|PASS[: ].*|PARITY .*' "$1" \
    | head -2 | tr '\n' ' '
}
step() { # name, command...
  local name="$1"; shift
  local f="$LOG/$(( ${#NAMES[@]} + 1 )).log"
  printf '%-40s ' "$name"
  if "$@" >"$f" 2>&1; then RESULTS+=(PASS); echo "PASS  $(summary "$f")"
  else RESULTS+=(FAIL); echo "FAIL  (log: $f)"; tail -20 "$f" | sed 's/^/      /'; fi
  NAMES+=("$name")
}
skip() { # name, reason
  printf '%-40s SKIP  %s\n' "$1" "$2"; NAMES+=("$1"); RESULTS+=(SKIP)
}
advisors_clean() {
  local out; out=$("$SUPABASE" db advisors --local --type all 2>&1) || { echo "$out"; return 1; }
  echo "$out"
  echo "$out" | grep -q '"results":\[\]'
}

step "1 flutter analyze"            bash -c "cd '$ROOT/apps/mobile' && flutter analyze"
step "2 flutter test"               bash -c "cd '$ROOT/apps/mobile' && flutter test"
step "3 admin unit tests"           bash -c "cd '$ROOT/apps/admin' && NG_CLI_ANALYTICS=false npx ng test --watch=false"
step "4 admin build (development)"  bash -c "cd '$ROOT/apps/admin' && NG_CLI_ANALYTICS=false npx ng build --configuration development --output-path='$LOG/admin-dist'"

if docker inspect -f '{{.State.Running}}' supabase_db_arena_ops 2>/dev/null | grep -q true; then
  step "5 supabase test db (pgTAP)" "$SUPABASE" test db --local
  step "6 supabase db advisors"     advisors_clean
  if [ $WITH_IT = 1 ]; then step "7 cross-app integration" bash tool/sync_it.sh
  else skip "7 cross-app integration" "pass --with-it (provisions throw-away local logins)"; fi
  if [ $WITH_PSQL = 1 ]; then
    step "8 pricing parity"         bash tool/pricing_parity.sh
    step "9a concurrency: station"  bash supabase/concurrency_tests/run.sh
    step "9b concurrency: pads"     bash supabase/concurrency_tests/run_pads.sh
  else
    skip "8 pricing parity" "pass --with-psql (uses docker exec psql on the local container)"
    skip "9 concurrency races" "pass --with-psql (uses docker exec psql on the local container)"
  fi
else
  for s in "5 supabase test db (pgTAP)" "6 supabase db advisors" "7 cross-app integration" "8 pricing parity" "9 concurrency races"; do
    skip "$s" "local Supabase stack is not running (supabase start)"
  done
fi

fail=0
for r in "${RESULTS[@]}"; do [ "$r" = FAIL ] && fail=1; done
echo
echo "logs: $LOG"
[ $fail = 0 ] && echo "NO FAILURES (see SKIP lines for what did not run)" || echo "SOME STEPS FAILED"
exit $fail
