#!/usr/bin/env bash
# tool/sync_it.sh step 0 — the invitation service (the staff-admin Edge Function) over HTTP,
# called exactly as the dashboard's Users page calls it (Bearer = the signed-in user's session,
# Origin = the local dashboard), on the LOCAL stack only. Each check names the HTTP status and
# the error code it expects:
#
#   * who may invite: no session or a bare API key → 401; floor staff without Settings, a login
#     with no membership, an owner naming an arena they do not belong to → 403; none of these
#     leaves an invitation behind;
#   * what is accepted: a bad e-mail, an unknown role, a password field, a blank name → 400
#     invalid_input; an unknown permission → 400 invalid_permission; nothing is created;
#   * the owner invites → 200 sent, the e-mail reaches the mail catcher, the invite is pending
#     and expires in 7 days; inviting the same address again leaves ONE pending invite and the
#     first link is refused (invite_revoked); the invited person accepts once with their own
#     session, and a second accept is refused (invite_used);
#   * dependencies down: the mail catcher stopped → 502 email_failed and no pending invite (it
#     was withdrawn: nothing claims an e-mail went out), and a retry after it is back succeeds;
#     the database API stopped → 503 service_unavailable and nothing created.
#
# The two outages stop and restart one local container each for a few seconds (restarted on any
# exit), so run this only through tool/sync_it.sh, which holds the stack's run lock and provides:
#   AO_SUPABASE_URL, AO_SUPABASE_ANON_KEY (publishable key), AO_IT_* (run id, password, logins,
#   arena, Mailpit URL), AO_IT_PROJECT (the stack's project_id), AO_IT_DASHBOARD_ORIGIN.
# Nothing secret is printed: tokens stay in shell variables.
set -uo pipefail
API=${AO_SUPABASE_URL:?}
PUB=${AO_SUPABASE_ANON_KEY:?}
case "$API" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "refusing: $API is not a local stack" >&2; exit 1 ;;
esac
RUN=${AO_IT_RUN:?}
ARENA=${AO_IT_ARENA:?}
MAILPIT=${AO_IT_MAILPIT_URL:?}
ORIGIN=${AO_IT_DASHBOARD_ORIGIN:-http://127.0.0.1:4200}
MAIL_CONTAINER="supabase_inbucket_${AO_IT_PROJECT:?}"
REST_CONTAINER="supabase_rest_${AO_IT_PROJECT}"
FN="$API/functions/v1/staff-admin"
OUT=$(mktemp)
failures=0

py() { python3 -I -c "$1" "${@:2}"; }
token() { # email → access token (password grant)
  curl -sS -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $PUB" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$AO_IT_PASSWORD\"}" |
    py 'import sys,json; print(json.load(sys.stdin).get("access_token",""))'
}
rpc_as() { # bearer fn body → body (HTTP status in $OUT.status)
  curl -sS -o "$OUT" -w '%{http_code}' -X POST "$API/rest/v1/rpc/$2" -H "apikey: $PUB" \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "$3" >"$OUT.status"
  cat "$OUT"
}
invite() { # bearer|- body → HTTP status; the reply is in $OUT
  local auth=()
  [ "$1" != - ] && auth=(-H "Authorization: Bearer $1")
  # ${auth[@]+…}: macOS bash 3.2 treats an empty array as unset under `set -u`.
  curl -sS -o "$OUT" -w '%{http_code}' --max-time 60 -X POST "$FN" -H "apikey: $PUB" \
    -H 'Content-Type: application/json' -H "Origin: $ORIGIN" ${auth[@]+"${auth[@]}"} -d "$2"
}
field() { py 'import sys,json; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$OUT" "$1"; }
body() { # email name role perms-json [extra-json]; ARENA_FOR overrides the arena
  local extra='{}'
  [ $# -ge 5 ] && extra=$5
  py 'import json,sys; a=sys.argv; d=dict(arena_id=a[1],email=a[2],name=a[3],role=a[4],perms=json.loads(a[5])); d.update(json.loads(a[6])); print(json.dumps(d))' \
    "${ARENA_FOR:-$ARENA}" "$1" "$2" "$3" "$4" "$extra"
}
check() { # description expected actual
  if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1 (expected $2, got $3)"; failures=$((failures + 1)); fi
}
pending() { # email → number of pending invitations for it in the arena (owner's view)
  rpc_as "$OWNER" arena_invites "{\"p_arena\":\"$ARENA\"}" |
    py 'import sys,json; e=sys.argv[1]; print(sum(1 for i in json.load(sys.stdin) if i.get("email")==e))' "$1"
}
mails() { # email → number of messages the mail catcher holds for it
  curl -sS "$MAILPIT/api/v1/search?query=$(py 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "to:\"$1\"")" |
    py 'import sys,json; print(len(json.load(sys.stdin).get("messages") or []))'
}
link() { # email index → the n-th newest Auth link e-mailed to it
  local id
  id=$(curl -sS "$MAILPIT/api/v1/search?query=$(py 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "to:\"$1\"")" |
    py 'import sys,json; m=json.load(sys.stdin).get("messages") or []; i=int(sys.argv[1]); print(m[i]["ID"] if len(m)>i else "")' "$2")
  [ -n "$id" ] || return 0
  curl -sS "$MAILPIT/api/v1/message/$id" |
    py 'import sys,json,re; m=json.load(sys.stdin); b=((m.get("Text") or "")+" "+(m.get("HTML") or "")).replace("&amp;","&"); r=re.search(r"https?://[^\s\"<>]+/auth/v1/verify\?[^\s\"<>]+", b); print(r.group(0) if r else "")'
}
invite_of() { # verify link → "<invite id> <token>" from its redirect_to
  py 'import sys,urllib.parse as u; q=u.parse_qs(u.urlparse(sys.argv[1]).query); r=u.parse_qs(u.urlparse(q["redirect_to"][0]).query); print(r["invite"][0], r["token"][0])' "$1"
}
session_of() { # verify link → the access token the link signs its owner in with
  curl -sS -o /dev/null -w '%{redirect_url}' "$1" |
    py 'import sys,urllib.parse as u; f=u.parse_qs(u.urlparse(sys.stdin.read()).fragment); print(f.get("access_token",[""])[0])'
}
wait_up() { # url label — answered by the service itself (no gateway 5xx, no connection error)
  local code
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $PUB" "$1")
    [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 500 ] && return 0
    sleep 1
  done
  echo "FAIL  $2 did not come back" >&2
  failures=$((failures + 1))
}
restore() { # restart anything this script stopped, whatever happens
  docker start "$MAIL_CONTAINER" >/dev/null 2>&1
  docker start "$REST_CONTAINER" >/dev/null 2>&1
  rm -f "$OUT" "$OUT.status"
}
trap restore EXIT

for c in "$MAIL_CONTAINER" "$REST_CONTAINER"; do
  docker inspect "$c" >/dev/null 2>&1 || { echo "refusing: container $c not found" >&2; exit 1; }
done

OWNER=$(token "$AO_IT_OWNER_EMAIL")
STAFF=$(token "$AO_IT_STAFF_EMAIL")
OUTSIDER=$(token "$AO_IT_OUTSIDER_EMAIL")
[ -n "$OWNER" ] && [ -n "$STAFF" ] && [ -n "$OUTSIDER" ] || { echo "could not sign the test logins in" >&2; exit 1; }
A1="it-svc1-$RUN@arena.test"   # invited twice, then accepts
A2="it-svc2-$RUN@arena.test"   # invited while the mail catcher is down, then again
A3="it-svc3-$RUN@arena.test"   # attempts that must leave nothing behind

echo "-- who may invite"
check "no session: 401 unauthorized" "401 unauthorized" "$(invite - "$(body "$A3" X staff '["start"]')") $(field error)"
check "a bare API key as the session: 401 unauthorized" "401 unauthorized" "$(invite "$PUB" "$(body "$A3" X staff '["start"]')") $(field error)"
check "floor staff without Settings: 403 forbidden" "403 forbidden" "$(invite "$STAFF" "$(body "$A3" X staff '["start"]')") $(field error)"
check "a login with no membership: 403 forbidden" "403 forbidden" "$(invite "$OUTSIDER" "$(body "$A3" X staff '["start"]')") $(field error)"
OTHER=$(py 'import uuid; print(uuid.uuid4())')
check "the owner naming an arena they do not belong to: 403 forbidden" "403 forbidden" \
  "$(invite "$OWNER" "$(ARENA_FOR=$OTHER body "$A3" X staff '["start"]')") $(field error)"

echo "-- what is accepted"
check "a bad e-mail: 400 invalid_input" "400 invalid_input" "$(invite "$OWNER" "$(body "not-an-email" X staff '["start"]')") $(field error)"
check "an unknown role: 400 invalid_input" "400 invalid_input" "$(invite "$OWNER" "$(body "$A3" X admin '["start"]')") $(field error)"
check "a password field: 400 invalid_input" "400 invalid_input" "$(invite "$OWNER" "$(body "$A3" X staff '["start"]' '{"password":"x"}')") $(field error)"
check "a blank name: 400 invalid_input" "400 invalid_input" "$(invite "$OWNER" "$(body "$A3" ' ' staff '["start"]')") $(field error)"
check "an unknown permission: 400 invalid_permission" "400 invalid_permission" "$(invite "$OWNER" "$(body "$A3" X staff '["root"]')") $(field error)"
check "none of those left an invitation behind" 0 "$(pending "$A3")"
check "nor sent any e-mail" 0 "$(mails "$A3")"

echo "-- the owner invites"
check "invite: 200 sent" "200 sent" "$(invite "$OWNER" "$(body "$A1" "Svc One" staff '["start","bill"]')") $(field status)"
check "it expires in 7 days" 7 "$(py 'import json,sys,datetime as d; e=d.datetime.fromisoformat(json.load(open(sys.argv[1]))["expires_at"].replace("Z","+00:00")); print(round((e-d.datetime.now(d.timezone.utc)).total_seconds()/86400))' "$OUT")"
check "it is pending" 1 "$(pending "$A1")"
for _ in $(seq 1 30); do [ "$(mails "$A1")" -ge 1 ] && break; sleep 1; done
check "the e-mail arrived" 1 "$(mails "$A1")"
check "inviting the same address again: 200 sent" "200 sent" "$(invite "$OWNER" "$(body "$A1" "Svc One" staff '["start","bill"]')") $(field status)"
check "still ONE pending invitation for it" 1 "$(pending "$A1")"
for _ in $(seq 1 30); do [ "$(mails "$A1")" -ge 2 ] && break; sleep 1; done
NEWEST=$(link "$A1" 0); FIRST=$(link "$A1" 1)
read -r FIRST_ID FIRST_TOKEN <<<"$(invite_of "$FIRST")"
read -r NEW_ID NEW_TOKEN <<<"$(invite_of "$NEWEST")"
check "each e-mail carries its own invitation" yes "$([ -n "$FIRST_ID" ] && [ "$FIRST_ID" != "$NEW_ID" ] && echo yes)"
INVITEE=$(session_of "$NEWEST")
check "the newest link signs the invited person in" yes "$([ -n "$INVITEE" ] && echo yes)"
rpc_as "$INVITEE" accept_invite "{\"p_invite\":\"$FIRST_ID\",\"p_token\":\"$FIRST_TOKEN\"}" >/dev/null
check "the first (replaced) link is refused: invite_revoked" invite_revoked "$(field message)"
rpc_as "$INVITEE" accept_invite "{\"p_invite\":\"$NEW_ID\",\"p_token\":\"$NEW_TOKEN\"}" >/dev/null
check "the newest link is accepted" "200 staff" "$(cat "$OUT.status") $(field role)"
rpc_as "$INVITEE" accept_invite "{\"p_invite\":\"$NEW_ID\",\"p_token\":\"$NEW_TOKEN\"}" >/dev/null
check "accepting it again is refused: invite_used" invite_used "$(field message)"
check "an accepted invitation is no longer pending" 0 "$(pending "$A1")"
unset INVITEE

echo "-- the mail catcher down"
docker stop "$MAIL_CONTAINER" >/dev/null
check "invite: 502 email_failed" "502 email_failed" "$(invite "$OWNER" "$(body "$A2" "Svc Two" staff '["start"]')") $(field error)"
check "and nothing is pending: the invitation was withdrawn" 0 "$(pending "$A2")"
docker start "$MAIL_CONTAINER" >/dev/null
wait_up "$MAILPIT/api/v1/info" "the mail catcher"
check "back up, the retry: 200 sent" "200 sent" "$(invite "$OWNER" "$(body "$A2" "Svc Two" staff '["start"]')") $(field status)"
check "and it is pending" 1 "$(pending "$A2")"

echo "-- the database API down"
docker stop "$REST_CONTAINER" >/dev/null
check "invite: 503 service_unavailable" "503 service_unavailable" "$(invite "$OWNER" "$(body "$A3" "Svc Three" staff '["start"]')") $(field error)"
docker start "$REST_CONTAINER" >/dev/null
wait_up "$API/rest/v1/" "the database API"
check "and nothing was created" 0 "$(pending "$A3")"
check "nor e-mailed" 0 "$(mails "$A3")"

[ "$failures" = 0 ] && echo "all invitation-service checks passed" || echo "$failures check(s) failed"
exit $((failures > 0))
