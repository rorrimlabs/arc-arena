#!/usr/bin/env bash
# Two-connection races on the sync write path (0011/0012). pgTAP runs in one
# connection and cannot prove these; here two real sessions collide.
#
#   Race 1 — two devices borrow the SAME physical pad (GHOST-1) for sessions at
#            two different stations. Connection A wins and holds its locks for
#            ~3s; B must wait on them and then be refused (controller_taken).
#   Race 2 — the SAME op (one op id) is pushed twice at once, as a client retry
#            after a timeout racing the original. Exactly one applies; the other
#            replays the stored result. No second session, no second payment.
#
# Prereq: local stack running. From the repo root:
#   bash supabase/concurrency_tests/run_pads.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P() { docker exec -i supabase_db_arena_ops psql -U postgres -X -q -t -A -v ON_ERROR_STOP=0 "$@"; }
ARENA=e0000000-0000-4000-8000-0000000000c2; OWNER=c0c0c0c0-0000-4000-8000-000000000002; CUSTOMER=cccccccc-0000-0000-0000-0000000eace0; LABEL=race-pads
RUN=$(uuidgen | tr 'A-Z' 'a-z' | cut -c1-8)   # unique ids per run

# Own arena + owner + customer, deleted again on exit (fixture.sh) — this
# script never touches another arena's sessions or pads.
source "$HERE/fixture.sh"; fixture_up; trap fixture_down EXIT

start_op() { # op_id session_id segment_id station alloc_id move_id
cat <<SQL
select _pricing_snapshot('$ARENA'::uuid) as snap \\gset
set role authenticated;
select set_config('request.jwt.claims','{"sub":"$OWNER","role":"authenticated"}', false);
select sync_push('$ARENA'::uuid, jsonb_build_array(jsonb_build_object(
  'op_id','$1','kind','session.start','payload', jsonb_build_object(
    'id','$2','segment_id','$3','customer_id','cccccccc-0000-0000-0000-0000000eace0',
    'started_at','2026-10-01T09:00:00Z','scheduled_end_at','2026-10-01T10:00:00Z',
    'pricing_snapshot',:'snap'::jsonb,'resource_id',(select id from resources where name='$4' and arena_id='$ARENA'),
    'activity_code','PS5','controller_count',1,
    'allocations', jsonb_build_array(jsonb_build_object('id','$5','controller_id',(select id from controllers where label='GHOST-1' and arena_id='$ARENA'))),
    'moves', jsonb_build_array(jsonb_build_object('id','$6','controller_id',(select id from controllers where label='GHOST-1' and arena_id='$ARENA')))))),
  'race')->'results'->0->>'status' as status;
SQL
}
u() { printf '%s-0000-4000-8000-%012d' "$RUN" "$1"; }

echo "== Race 1: two stations, one pad =="
A=$(mktemp); B=$(mktemp)
{ echo "begin;"; start_op "$(u 1)" "$(u 11)" "$(u 21)" HEX "$(u 31)" "$(u 41)"; echo "select pg_sleep(3); commit;"; } | P > "$A" 2>&1 &
AP=$!
{ sleep 0.3; start_op "$(u 2)" "$(u 12)" "$(u 22)" RIFT "$(u 32)" "$(u 42)"; } | P > "$B" 2>&1 &
BP=$!
wait $AP $BP
echo "A: $(grep -vE '^$|^\{' "$A" | tr '\n' ' ')"
echo "B: $(grep -vE '^$|^\{' "$B" | tr '\n' ' ')"
# While B waited, A moved GHOST-1 to a station B had not locked, so B may come
# back 'retry' (nothing recorded). The client re-pushes the same op — do that.
if grep -q retry "$B"; then
  echo "B was told to retry; re-pushing the same op as the client would"
  start_op "$(u 2)" "$(u 12)" "$(u 22)" RIFT "$(u 32)" "$(u 42)" | P > "$B" 2>&1
  echo "B (retry): $(grep -vE '^$|^\{' "$B" | tr '\n' ' ')"
fi
B_ERR=$(P -c "select error_code from sync_ops where op_id = '$(u 2)'")
OPEN=$(P -c "select count(*) from controller_allocations a join controllers c on c.id = a.controller_id where c.arena_id='$ARENA' and c.label='GHOST-1' and a.ended_at is null")
echo "B error_code=$B_ERR; open allocations on GHOST-1=$OPEN (expect 1)"
R1=FAIL; grep -q applied "$A" && [ "$B_ERR" = "controller_taken" ] && [ "$OPEN" = "1" ] && R1=PASS
echo "Race 1: $R1"

echo "== Race 2: one op pushed twice at once =="
# Reset THIS arena's floor between the races (never anyone else's).
P <<SQL >/dev/null
update session_segments set ended_at = now() where arena_id = '$ARENA' and ended_at is null;
update controller_allocations set ended_at = now() where arena_id = '$ARENA' and ended_at is null;
update controllers set current_resource_id = home_resource_id, loan_return_to = null, loan_session_ref = null
  where arena_id = '$ARENA';
SQL
OPID=$(u 3)
{ echo "begin;"; start_op "$OPID" "$(u 13)" "$(u 23)" VOID "$(u 33)" "$(u 43)"; echo "select pg_sleep(3); commit;"; } | P > "$A" 2>&1 &
AP=$!
{ sleep 0.3; echo "set role authenticated;
select set_config('request.jwt.claims','{\"sub\":\"$OWNER\",\"role\":\"authenticated\"}', false);
select (r->'results'->0->>'status') || ' replayed=' || (r->'results'->0->>'replayed') from (select sync_push('$ARENA'::uuid, jsonb_build_array(jsonb_build_object(
  'op_id','$OPID','kind','session.start','payload','{}'::jsonb)), 'race-retry') r) q;"; } | P > "$B" 2>&1 &
BP=$!
wait $AP $BP
echo "A: $(grep -vE '^$|^\{' "$A" | tr '\n' ' ')"
echo "B: $(grep -vE '^$|^\{' "$B" | tr '\n' ' ')"
N=$(P -c "select count(*) from sessions where id = '$(u 13)'")
L=$(P -c "select count(*) from sync_ops where op_id = '$OPID'")
echo "sessions created=$N ledger rows=$L (expect 1 / 1)"
R2=FAIL; grep -q "applied replayed=true" "$B" && [ "$N" = "1" ] && [ "$L" = "1" ] && R2=PASS
echo "Race 2: $R2"
rm -f "$A" "$B"

[ "$R1" = PASS ] && [ "$R2" = PASS ] && echo "PASS: pad races serialised; duplicate op applied once" || { echo "FAIL"; exit 1; }
