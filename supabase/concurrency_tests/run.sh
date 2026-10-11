#!/usr/bin/env bash
# Two-connection concurrency test for the one-open-segment-per-resource rule.
#
# pgTAP (supabase/tests/) runs in a single connection and cannot prove true
# concurrency. This proves the real guarantee: the `resources ... FOR UPDATE`
# lock plus the assert_resource_free_for_segment trigger SERIALISE two
# simultaneous session.start ops (sync_push, the client write path since 0012)
# on the SAME station — exactly one wins and the other gets `resource_busy`. Connection A wins and holds the lock for ~3s
# (pg_sleep inside its transaction); B starts 0.3s later, blocks on A's lock,
# then fails when A commits.
#
# Prereq: the local stack is running (`supabase start`). From the repo root:
#   bash supabase/concurrency_tests/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P() { docker exec -i supabase_db_arena_ops psql -U postgres -X -q -v ON_ERROR_STOP=0 "$@"; }

# Own arena + owner + customer, deleted again on exit (fixture.sh).
ARENA=e0000000-0000-4000-8000-0000000000c1; OWNER=c0c0c0c0-0000-4000-8000-000000000001; CUSTOMER=cccccccc-0000-0000-0000-00000000c0de; LABEL=race-station
source "$HERE/fixture.sh"; fixture_up; trap fixture_down EXIT

A=$(mktemp); B=$(mktemp)
P < "$HERE/race_A.sql" > "$A" 2>&1 &  AP=$!
P < "$HERE/race_B.sql" > "$B" 2>&1 &  BP=$!
wait "$AP" "$BP"


echo "--- A (expected winner) ---"; grep -E "applied|rejected" "$A" || cat "$A"
echo "--- B (expected resource_busy) ---"; grep -E "resource_busy|ERROR" "$B" || cat "$B"
N=$(PSQL -c "select count(*) from session_segments s join resources r on r.id=s.resource_id where r.arena_id='$ARENA' and r.name='HEX' and s.ended_at is null;")
echo "--- open segments on HEX: ${N} (expect 1) ---"
BUSY=$(grep -c resource_busy "$B")
rm -f "$A" "$B"


if [ "$N" = "1" ] && [ "$BUSY" -ge 1 ]; then
  echo "PASS: exactly one start won; the other got resource_busy"
else
  echo "FAIL: concurrency invariant not satisfied"; exit 1
fi
