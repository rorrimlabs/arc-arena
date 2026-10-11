#!/usr/bin/env bash
# Full verification, in a fixed, repeatable order. Needs the LOCAL dev stack
# (supabase start; project arena_ops, ports 5443x). No reset is required
# between — or before — the steps: every suite isolates its own data.
#
#   bash tool/verify_all.sh
#
#   1 flutter analyze
#   2 flutter test                         (unit/widget; two-device skipped)
#   3 supabase test db --local             (pgTAP, each file in its own arena)
#   4 concurrency: station race            (own arena, deleted on exit)
#   5 concurrency: pad races + double op   (own arena, deleted on exit)
#   6 two-device sync (tool/sync_it.sh)    (own accounts/arena, deleted on exit)
#   7 pricing parity (tool/pricing_parity.sh, rolled back)
#   8 supabase test db again               (order independence: after 4–7)
#
# Isolation canary: for the whole run a second arena with the SAME station and
# controller names exists, so a test that slips back to "the only arena" /
# "the station called HEX" fails instead of passing by luck. At the end the
# script checks the database holds exactly what it held before (arenas,
# accounts, sessions, ops) and removes the canary.
#
# Every step runs even if an earlier one fails; each is reported separately.
# Never point this at a hosted project: steps 3–8 use the local container.
set -uo pipefail
cd "$(dirname "$0")/.."
DB=supabase_db_arena_ops
CANARY=e0000000-0000-4000-8000-0000000000ca
Q() { docker exec -i "$DB" psql -U postgres -X -q -t -A -v ON_ERROR_STOP=1 "$@"; }
docker inspect -f '{{.State.Running}}' "$DB" 2>/dev/null | grep -q true \
  || { echo "local stack not running (supabase start)" >&2; exit 1; }

census() {
  Q -c "select (select count(*) from arenas where id <> '$CANARY') || ' arenas, ' ||
               (select count(*) from auth.users) || ' accounts, ' ||
               (select count(*) from sessions) || ' sessions, ' ||
               (select count(*) from sync_ops) || ' ops'"
}
canary_down() { Q -c "delete from arenas where id = '$CANARY'" >/dev/null; }
canary_down
Q >/dev/null <<SQL
insert into arenas(id, name) values ('$CANARY', 'verify_all isolation canary');
select _seed_arena_catalog('$CANARY');
SQL
trap canary_down EXIT
BEFORE=$(census)

LOG=$(mktemp -d)
declare -a NAMES RESULTS
step() { # name, command...
  local name="$1"; shift
  local f="$LOG/$(( ${#NAMES[@]} + 1 )).log"
  printf '%-34s ' "$name"
  if "$@" >"$f" 2>&1; then RESULTS+=(PASS); echo "PASS  $(summary "$f")"
  else RESULTS+=(FAIL); echo "FAIL  (log: $f)"; tail -15 "$f" | sed 's/^/      /'; fi
  NAMES+=("$name")
}
summary() {
  grep -hoE 'No issues found!|[0-9:]+ \+[0-9]+( ~[0-9]+)?: All tests passed!|Files=[0-9]+, Tests=[0-9]+|PASS: .*|PARITY cases=[0-9]+ .*mismatches_operation=[0-9]+' "$1" \
    | sed -E 's/^[0-9:]+ //' | head -1
}

step "1 flutter analyze"                flutter analyze
step "2 flutter test"                   flutter test
step "3 supabase test db"               supabase test db --local
step "4 concurrency: station race"      bash supabase/concurrency_tests/run.sh
step "5 concurrency: pads + double op"  bash supabase/concurrency_tests/run_pads.sh
step "6 two-device sync"                bash tool/sync_it.sh
step "7 pricing parity"                 bash tool/pricing_parity.sh
step "8 supabase test db (again)"       supabase test db --local

AFTER=$(census)
echo "database before: $BEFORE"
echo "database after:  $AFTER"
fail=0
[ "$BEFORE" = "$AFTER" ] || { echo "FAIL: a suite left data behind"; fail=1; }
for r in "${RESULTS[@]}"; do [ "$r" = PASS ] || fail=1; done
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME STEPS FAILED"
exit $fail
