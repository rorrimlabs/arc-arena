#!/usr/bin/env bash
# Cross-app integration suite: the admin dashboard's real data layer (Angular,
# run under `ng test`, no browser driving) and the staff app's real sync stack
# (Flutter SimDevice: Drift + outbox + SyncEngine + RealtimeSync) against ONE
# LOCAL Supabase stack, plus the staff-admin Edge Function and the local mail
# catcher (Mailpit) for the invitation e-mail. Nothing is mocked.
#
#   bash tool/sync_it.sh
#
# Phases (each reported PASS/FAIL; the exit code is non-zero if any failed):
#   0 invitation service (tool/it_invitations.sh): the staff-admin Edge Function
#     over HTTP — who may invite, input checks, e-mail + replace + accept, and a
#     stopped mail catcher / database API (failure is never reported as sent)
#   1 live: a Flutter device joined to the private arena channel waits for a nudge
#   2 dashboard phase 1 (Angular): build a game + its station availability, save
#     floor options, invite a NEW person by e-mail and accept it from the e-mailed
#     link (Mailpit), write $AO_IT_HANDOFF/dashboard.json  → phase 1's nudge must
#     reach the waiting Flutter device (step 1 passes only then)
#   3 live: the dashboard's RealtimeSync waits for a nudge from the floor
#   4 floor (Flutter): test/sync/ — two-device sync, cross-app (reads
#     dashboard.json, runs a session with the dashboard game, writes floor.json),
#     private-channel authorization, arena isolation → step 3 passes only if the
#     floor's committed change reached the dashboard live
#   5 dashboard phase 2 (Angular): the staff's bill is on the owner's Sales list
#     with exactly one payment; another arena's owner sees nothing of it
#   6 the stack's Edge Function runtime is still up afterwards (when it was before)
#
# The Edge Function: `supabase start` runs it (config.toml [edge_runtime]) and the
# run uses that runtime. Only if the stack has none does the run serve it itself
# (`supabase functions serve`, stopped at exit). Never run a second server against
# a stack that has one: `functions serve` takes over the stack's runtime container
# and removes it when it exits, after which the dashboard's invitations answer 503
# {"message":"name resolution failed"} until `supabase stop && supabase start`.
# One run at a time (lock in supabase/.temp): runs share the logins' namespace,
# the mail catcher and that runtime.
#
# Safety: refuses anything but a local stack. The local service-role key (the
# well-known local demo key from `supabase status`) stays in a NON-exported
# shell variable used only by the curl calls below — never printed, never given
# to a test process. Test logins use the reserved it-*@arena.test namespace and
# one random password per run (exported to the test processes only). On exit it
# removes exactly what this run created: its logins and the arenas they own.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SUPABASE=${SUPABASE_BIN:-supabase}

ENVOUT=$("$SUPABASE" status -o env 2>/dev/null) || { echo "local stack not running (supabase start)" >&2; exit 1; }
val() { echo "$ENVOUT" | grep -E "^$1=" | head -1 | cut -d= -f2- | tr -d '"'; }
API=$(val API_URL)
case "$API" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "refusing: API_URL is not a local stack" >&2; exit 1 ;;
esac
PUB=$(val PUBLISHABLE_KEY); [ -n "$PUB" ] || PUB=$(val ANON_KEY)
SERVICE=$(val SERVICE_ROLE_KEY)
MAILPIT=$(val MAILPIT_URL); [ -n "$MAILPIT" ] || MAILPIT=$(val INBUCKET_URL)
[ -n "$PUB" ] && [ -n "$SERVICE" ] || { echo "could not read the local keys" >&2; exit 1; }
unset ENVOUT
PROJECT=$(sed -nE 's/^project_id = "([^"]+)"/\1/p' "$ROOT/supabase/config.toml" | head -1)

# One run at a time on this stack.
LOCK="$ROOT/supabase/.temp/sync_it.lock"
mkdir -p "$ROOT/supabase/.temp"
if ! mkdir "$LOCK" 2>/dev/null; then
  other=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
    echo "another tool/sync_it.sh run (pid $other) is using the local stack: wait for it to end" >&2
    exit 1
  fi
  rm -rf "$LOCK" && mkdir "$LOCK" || { echo "could not take the run lock $LOCK" >&2; exit 1; }
fi
echo $$ >"$LOCK/pid"

json() { python3 -I -c "import sys,json; d=json.load(sys.stdin); print($1)"; }
admin() { # method path [body]  — service role, local only
  curl -sS -X "$1" "$API$2" -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" \
    -H 'Content-Type: application/json' -H 'Prefer: return=minimal' ${3:+-d "$3"}
}
token() { # email → access token (password grant)
  curl -sS -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $PUB" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$AO_IT_PASSWORD\"}" | json "d['access_token']"
}
rpc_as() { # bearer fn body
  curl -sS -X POST "$API/rest/v1/rpc/$2" -H "apikey: $PUB" -H "Authorization: Bearer $1" \
    -H 'Content-Type: application/json' -d "$3"
}

RUN=$(uuidgen | tr 'A-Z' 'a-z' | cut -c1-8)
HANDOFF=$(mktemp -d)
export AO_IT_RUN="$RUN" AO_IT_HANDOFF="$HANDOFF"
export AO_IT_PASSWORD="$(openssl rand -hex 16)Aa1"
export AO_IT_OWNER_EMAIL="it-owner-$RUN@arena.test"
export AO_IT_STAFF_EMAIL="it-staff-$RUN@arena.test"
export AO_IT_OUTSIDER_EMAIL="it-outsider-$RUN@arena.test"
export AO_IT_INVITEE_EMAIL="it-invitee-$RUN@arena.test"   # created by the invitation itself
export AO_IT_MAILPIT_URL="$MAILPIT"
export AO_SUPABASE_URL="$API" AO_SUPABASE_ANON_KEY="$PUB"
# The invitation link's base: the local dashboard (`ng serve`), allowed in config.toml
# [auth] additional_redirect_urls. The specs send it as Origin, like the browser does.
export AO_IT_DASHBOARD_ORIGIN="http://127.0.0.1:4200" AO_IT_PROJECT="$PROJECT"

FN_PID=""
cleanup() {
  [ -n "$FN_PID" ] && kill "$FN_PID" 2>/dev/null
  # Every login of this run (including the invitee the dashboard created), the
  # arenas they own, then the logins.
  local ids
  ids=$(admin GET "/auth/v1/admin/users?per_page=1000" | python3 -I -c "
import sys,json
run='$RUN'
for u in json.load(sys.stdin).get('users',[]):
    e=u.get('email') or ''
    if e.startswith('it-') and e.endswith('-'+run+'@arena.test'): print(u['id'])")
  for id in $ids; do
    for a in $(admin GET "/rest/v1/staff_profiles?select=arena_id&role=eq.owner&user_id=eq.$id" | json "' '.join(r['arena_id'] for r in d)"); do
      admin DELETE "/rest/v1/arenas?id=eq.$a" >/dev/null
    done
  done
  for id in $ids; do admin DELETE "/auth/v1/admin/users/$id" >/dev/null; done
  # Keep the logs of a failed run (they hold no credentials), or of any run with
  # AO_IT_KEEP_LOGS=1; drop the rest.
  if [ "${fail:-1}" != 0 ] || [ "${AO_IT_KEEP_LOGS:-0}" = 1 ]; then
    local keep="${TMPDIR:-/tmp}/sync_it-$RUN"
    mkdir -p "$keep" && cp "$HANDOFF"/*.log "$keep"/ 2>/dev/null
    echo "logs kept in $keep"
  fi
  rm -rf "$HANDOFF"
  rm -rf "$LOCK"
}
trap cleanup EXIT

echo "== provisioning run $RUN (local stack)"
for EMAIL in "$AO_IT_OWNER_EMAIL" "$AO_IT_STAFF_EMAIL" "$AO_IT_OUTSIDER_EMAIL"; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$API/auth/v1/admin/users" \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$AO_IT_PASSWORD\",\"email_confirm\":true}")
  [ "$code" = 200 ] || { echo "could not create a test login (HTTP $code)" >&2; exit 1; }
done
AO_IT_ARENA=$(admin POST /rest/v1/rpc/bootstrap_owner \
  "{\"p_email\":\"$AO_IT_OWNER_EMAIL\",\"p_arena_name\":\"IT $RUN\",\"p_owner_name\":\"Owner A\"}" | tr -d '"')
[[ "$AO_IT_ARENA" =~ ^[0-9a-f-]{36}$ ]] || { echo "bootstrap_owner failed" >&2; exit 1; }
export AO_IT_ARENA
admin POST /rest/v1/rpc/_seed_arena_catalog "{\"v_arena\":\"$AO_IT_ARENA\"}" >/dev/null
# The staff login joins the way everyone does: invited, then accepting.
OWNER_JWT=$(token "$AO_IT_OWNER_EMAIL"); STAFF_JWT=$(token "$AO_IT_STAFF_EMAIL")
INVITE=$(rpc_as "$OWNER_JWT" invite_member "{\"p_arena\":\"$AO_IT_ARENA\",\"p_email\":\"$AO_IT_STAFF_EMAIL\",\"p_name\":\"Staff B\",\"p_role\":\"staff\",\"p_perms\":[\"start\",\"bill\",\"discount\",\"members\"]}")
ACCEPT=$(echo "$INVITE" | json "json.dumps(dict(p_invite=d['invite_id'], p_token=d['token']))")
rpc_as "$STAFF_JWT" accept_invite "$ACCEPT" \
  | grep -q "IT $RUN" || { echo "the staff login could not join by invitation" >&2; exit 1; }
unset OWNER_JWT STAFF_JWT INVITE ACCEPT

fn_status() { curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$API/functions/v1/staff-admin"; }
STACK_RUNTIME=0
if [ "$(fn_status)" = 204 ]; then
  STACK_RUNTIME=1
  echo "== using the stack's Edge Function runtime (supabase start)"
else
  # Missing (`supabase status` lists supabase_edge_runtime_$PROJECT as stopped): the
  # dashboard's own invitations fail until `supabase stop && supabase start`.
  echo "== the stack has no Edge Function runtime: serving staff-admin for this run only"
  echo "   (outside this run, invitations answer 503 \"name resolution failed\" until: supabase stop && supabase start)"
  "$SUPABASE" functions serve --no-verify-jwt >"$HANDOFF/functions.log" 2>&1 &
  FN_PID=$!
  for _ in $(seq 1 90); do
    [ "$(fn_status)" = 204 ] && break
    sleep 1
  done
fi

declare -a NAMES RESULTS
record() { NAMES+=("$1"); RESULTS+=("$2"); printf '%-46s %s\n' "$1" "$2"; }
run_step() { # name, command...
  local name="$1"; shift; local f="$HANDOFF/step-${#NAMES[@]}.log"
  if "$@" >"$f" 2>&1; then record "$name" PASS
  else record "$name" FAIL; tail -40 "$f" | sed 's/^/    /'; fi
}
wait_for() { # file, seconds
  for _ in $(seq 1 "$2"); do [ -e "$1" ] && return 0; sleep 1; done; return 1
}
ng_it() { (cd "$ROOT/apps/admin" && NG_CLI_ANALYTICS=false npx ng test --watch=false --include="$1"); }

# 0: the invitation service over HTTP, before the live phases start listening.
run_step "0 invitation service (staff-admin, HTTP)" bash "$ROOT/tool/it_invitations.sh"

# 1 + 2: Flutter listens live while the dashboard writes.
(cd "$ROOT/apps/mobile" && AO_IT_LISTEN=1 flutter test test/sync/realtime_listen_test.dart) \
  >"$HANDOFF/listen-flutter.log" 2>&1 &
LISTEN_FLUTTER=$!
if wait_for "$HANDOFF/flutter_listening" 180; then
  run_step "2 dashboard phase 1 (Angular)" ng_it integration/dashboard-phase1.it.spec.ts
else
  record "2 dashboard phase 1 (Angular)" "FAIL (Flutter listener never joined)"
fi
if wait "$LISTEN_FLUTTER"; then record "1 live: dashboard → floor (Realtime)" PASS
else record "1 live: dashboard → floor (Realtime)" FAIL; tail -30 "$HANDOFF/listen-flutter.log" | sed 's/^/    /'; fi

# 3 + 4: the dashboard listens live while the floor writes.
(AO_IT_LISTEN=1 ng_it integration/dashboard-live.it.spec.ts) >"$HANDOFF/listen-admin.log" 2>&1 &
LISTEN_ADMIN=$!
if wait_for "$HANDOFF/admin_listening" 240; then
  # One file at a time: the files share this run's arena, and two of them run
  # sessions on the same stations (HEX), so in parallel one finds the other's.
  run_step "4 floor: two-device + cross-app (Flutter)" bash -c "cd '$ROOT/apps/mobile' && flutter test --concurrency=1 test/sync/"
else
  record "4 floor: two-device + cross-app (Flutter)" "FAIL (dashboard listener never joined)"
fi
if wait "$LISTEN_ADMIN"; then record "3 live: floor → dashboard (Realtime)" PASS
else record "3 live: floor → dashboard (Realtime)" FAIL; tail -30 "$HANDOFF/listen-admin.log" | sed 's/^/    /'; fi

run_step "5 dashboard phase 2 (Angular)" ng_it integration/dashboard-phase2.it.spec.ts

# 6: this run left the stack's own runtime (the dashboard's invitations) as it found it.
if [ "$STACK_RUNTIME" = 1 ]; then
  if [ "$(fn_status)" = 204 ]; then record "6 stack's Edge Function runtime still up" PASS
  else record "6 stack's Edge Function runtime still up" FAIL; fi
fi

fail=0
for r in "${RESULTS[@]}"; do [ "$r" = PASS ] || fail=1; done
[ $fail = 0 ] && echo "ALL INTEGRATION PHASES PASSED" || echo "SOME INTEGRATION PHASES FAILED"
exit $fail
