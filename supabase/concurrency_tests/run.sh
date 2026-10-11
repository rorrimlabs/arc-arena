#!/usr/bin/env bash
# Two-connection concurrency test for the one-open-segment-per-resource rule.
#
# pgTAP (supabase/tests/) runs in a single connection and cannot prove true
# concurrency. This proves the real guarantee: the `resources ... FOR UPDATE`
# lock plus the assert_resource_free_for_segment trigger SERIALISE two
# simultaneous start_session calls on the SAME station — exactly one wins and
# the other gets `resource_busy`. Connection A wins and holds the lock for ~3s
# (pg_sleep inside its transaction); B starts 0.3s later, blocks on A's lock,
# then fails when A commits.
#
# Prereq: the local stack is running (`supabase start`). From the repo root:
#   bash supabase/concurrency_tests/run.sh
set -uo pipefail
DB=supabase_db_arena_ops
HERE="$(cd "$(dirname "$0")" && pwd)"
P() { docker exec -i "$DB" psql -U postgres -X -q -v ON_ERROR_STOP=0 "$@"; }

# Idempotent fixture (owner + customer), and free HEX from any prior run.
P <<'SQL' >/dev/null
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
    'authenticated','authenticated','owner@race.local','',now(),now(),now(),'{}','{}',false,false)
  on conflict (id) do nothing;
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  select (select id from arenas limit 1),'11111111-1111-1111-1111-111111111111','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true
  on conflict (user_id,arena_id) do nothing;
insert into customers(id,arena_id,name)
  values ('cccccccc-0000-0000-0000-00000000c0de',(select id from arenas limit 1),'Race Cust')
  on conflict (id) do nothing;
update session_segments set ended_at=now()
  where resource_id=(select id from resources where name='HEX') and ended_at is null;
SQL

A=$(mktemp); B=$(mktemp)
P < "$HERE/race_A.sql" > "$A" 2>&1 &  AP=$!
P < "$HERE/race_B.sql" > "$B" 2>&1 &  BP=$!
wait "$AP" "$BP"

echo "--- A (expected winner) ---"; grep -E "a_result|dddddddd-0000-0000-0000-00000000000a" "$A" || cat "$A"
echo "--- B (expected resource_busy) ---"; grep -E "resource_busy|ERROR" "$B" || echo "(B did not error)"
N=$(docker exec -i "$DB" psql -U postgres -X -tAc "select count(*) from session_segments s join resources r on r.id=s.resource_id where r.name='HEX' and s.ended_at is null;")
echo "--- open segments on HEX: ${N} (expect 1) ---"
BUSY=$(grep -c resource_busy "$B")
rm -f "$A" "$B"

# Leave HEX free for re-runs.
docker exec -i "$DB" psql -U postgres -X -q -c \
  "update session_segments set ended_at=now() where resource_id=(select id from resources where name='HEX') and ended_at is null;" >/dev/null

if [ "$N" = "1" ] && [ "$BUSY" -ge 1 ]; then
  echo "PASS: exactly one start won; the other got resource_busy"
else
  echo "FAIL: concurrency invariant not satisfied"; exit 1
fi
