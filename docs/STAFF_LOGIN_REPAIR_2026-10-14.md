# Staff login & invitation flow — repair report (2026-10-14)

Scope: owner invites from the admin dashboard → the person accepts → signs in on the
Flutter staff app → works in the arena → the owner sees the result. Everything below
was verified on the **local** Supabase stack. Nothing hosted was changed; the hosted
project was only probed read-only and anonymously (see §1). Nothing is committed.

The dashboard side of this flow (the owner's own session being replaced by the
invitee's when both used one browser, which sent the owner to *Create Arena*) was
fixed in the same checkout by the parent completion session (`InviteeAuth`,
`noArenaGuard`, `/account`). This report covers the staff app and the cross-app path.

## 1. Root cause

**The two apps were talking to different Supabase projects, and the hosted project
cannot do invitations at all.**

| Build | Backend it signs in to | Source |
|---|---|---|
| Admin dashboard, `npm run dev` | local stack `127.0.0.1:54431` | `apps/admin/src/environments/environment.ts` |
| Admin dashboard, production | none (URL empty) | `environment.production.ts` |
| Staff app, release APK (cloud-only) | hosted project `ouxvtvlzhxddmqirmnxo` | `dart_define.prod.json` |
| Staff app, `dart_define.hosted-dev.json` | hosted project `ouxvtvlzhxddmqirmnxo` | same project |
| Staff app, `tool/dev_run.sh` | local stack | iOS Simulator, or Android emulator with `ANDROID=1` (10.0.2.2); **not** a physical tablet, where 127.0.0.1 is the tablet itself |

Read-only anonymous probe of the hosted project's API (2026-10-14; anon can execute
nothing, so nothing ran): `my_arenas`, `sync_pull` and `sync_push` exist (HTTP 401,
42501). `accept_invite`, `invite_member`, `create_my_arena`, `arena_invites`,
`arena_staff` and `arena_pricing` return **404 PGRST202 (absent)**. None of the
migrations after `0015` are on hosted (DEPLOY_SUPABASE.md §4a).

Observed on this machine: the staff app on the simulator was running from
`flutter run --dart-define-from-file=dart_define.prod.json` (started 12:38), so it
signed in to the hosted project. A sibling session independently found the same thing
in the local Auth logs: invite → password set → successful sign-in from the
dashboard (:4200), all on the local stack.

What a person saw: the owner invited from the local dashboard, so the login and the
membership were created on the **local** stack only. The staff member then signed
in on the counter tablet's release build, which talks to **hosted**, where that login
does not exist. Supabase answered `invalid_credentials`, and the app showed the raw
"Invalid login credentials". **The failing step is step 3 (the Supabase Auth
sign-in).** On a debug build pointed at the local stack from a physical tablet, step
3 fails instead with a network error.

**The staff app hid the cause.** It showed the raw Auth text, gave no hint that an
invitation must be accepted (and a password chosen) first, and never said which
server it was using. It also showed raw exception text: "Could not reach the server
(ClientException…)", "The server refused to list your arenas (PostgrestException…)",
"Sync failed: …".

Smaller staff-app defects found and fixed:

* **"Turned off" without a re-check.** An arena opened from an existing device file
  said "Your access is turned off" whenever the device's copy of the staff list was
  older than the server's. It never re-checked, even though `my_arenas` had just
  reported the membership active.
* **Unreadable keystore crashed the app.** A keystore that cannot be read (Android,
  after a backup restore or OS update) threw out of `Supabase.initialize`, so the app
  never started.
* **Outdated wording.** The no-arena text pointed to the removed "Staff → Add".

Checked and found sound (no change needed):

* `my_arenas` returns every profile of `auth.uid()`, inactive ones flagged.
* `accept_invite` checks the token, single use, expiry, withdrawal, the invited
  address and a confirmed e-mail, and upserts exactly one profile.
* `sync_pull` / `sync_push` require an active membership.
* RLS hides arena rows from inactive members.
* Session restore refuses to call as `anon`.
* Each (arena, person) has its own device database file.

## 2. Changes (staff app and docs)

| File | Change |
|---|---|
| `apps/mobile/lib/app/sync/staff_access.dart` (new) | Sign-in decisions, testable without widgets: `parseMemberships` / `fetchMemberships` (`my_arenas`; tolerant, access never assumed); `cloudDbPath`; `localAccess` / `confirmAccess` (server says active but device copy is older → sync once, then decide); plain-language `signInFailureMessage`, `arenaListFailureMessage` (incl. "this server isn't set up for the staff app" for PGRST202), `firstDownloadFailureMessage`, `offlineMessage`; `serverLabel` |
| `apps/mobile/lib/app/sync/cloud_root.dart` | Uses the above. The sign-in and error screens show "Server: …". Empty fields are refused before calling the server. A refused sign-in keeps the typed e-mail and is never retried on its own. The no-arena and all-access-off texts point to the invitation. `_open` uses `confirmAccess`; a missing profile is a retryable error, not "turned off". No raw exceptions on screen. |
| `apps/mobile/lib/app/sync/secure_session_storage.dart` | An unreadable or unwritable keystore means "sign in again" (entry dropped), never a start-up crash |
| `apps/mobile/lib/main.dart` | Passes the backend URL to `CloudRoot` |
| `apps/mobile/test/app/sync/staff_access_test.dart` (new) | 18 unit tests: memberships, access and re-check, every message, keystore failures |
| `apps/mobile/test/features/auth/cloud_accounts_test.dart` | Wording updated. New: refused sign-in keeps state, empty fields, offline wording, server label, all-access-off |
| `apps/mobile/test/sync/staff_login_test.dart` (new) | Real-server test (§3), runs in `tool/sync_it.sh` phase 4 |
| `docs/SYNC.md` | "Both apps must use the same Supabase project"; start-up re-check and messages |

## 3. Test evidence (local stack only)

| Check | Result |
|---|---|
| `tool/sync_it.sh` (run `16d70a3b`) | **All 5 phases PASS.** Phase 1: the owner invites by e-mail through the `staff-admin` Edge Function; the invitee opens the Mailpit link, chooses a password and accepts; a retried accept is refused (`invite_used`); the owner stays owner. Phase 4: the two-device, cross-app and isolation specs, plus the new `staff_login_test.dart`. Phase 5: the owner's Sales list shows the staff bill with one payment, and another arena sees nothing. |
| `staff_login_test.dart` (9 tests, real server, as the invitee) | wrong password refused and worded; sign-in → exactly one active membership → first download → staff permissions `{start}`, not owner, tabs Floor + More only; server refuses `payment.record` and `rate.upsert` (`forbidden`) and RLS hides payments; owner grants Bill → device follows → lounge session started, billed, paid and pushed with 0 rejections → owner reads it `completed` / `paid` with exactly 1 payment; restart from the stored refresh token reopens the same file without a new download, and a resend of the same op ids is replayed, not applied twice; access turned off → sync refused (`accessRevoked`), `my_arenas` inactive, RLS returns no rows; turned back on → opens and syncs; another arena's feed refused; a sign-in whose session was signed out on the server → refresh refused → "sign in again" (never `anon`); another login on the device gets its own file with nothing of the previous login |
| Independent re-run on the combined tree (reported by the parent completion session) | `tool/sync_it.sh` all 5 phases PASS, including `staff_login_test.dart`; `flutter analyze` clean; `flutter test` 752 passed, 31 skipped; admin `npm test` 236 passed |
| First `sync_it.sh` run (`8e3d70d0`) | FAIL, environmental. The Edge Function container disappeared mid-run on the shared stack ("No such container: supabase_edge_runtime_arena_ops"), so no invitation was sent. Re-runs were clean. |
| `flutter analyze` | No issues |
| `flutter test` | 752 passed, 31 skipped (the live specs), 0 failed |
| Admin `npm test` | 236 passed, 3 skipped, 0 failed (run alone). Inside `verify_all.sh`, while another session ran admin tests in parallel, four first-tests-of-file timed out at 5 s (timing under load, not logic). |
| Admin build (development) | PASS |
| `supabase test db --local` | 920/920 PASS |
| `supabase db advisors --local --type all` | no issues |
| Pricing parity, concurrency races (`--with-psql`) | not run (unchanged code) |

Requirement map (task §8):

| # | Requirement | Evidence |
|---|---|---|
| 1 | Valid invited staff login | `staff_login_test` sign-in + open |
| 2 | Wrong password keeps valid state | `staff_login_test`; widget test keeps the typed e-mail and re-enables the button |
| 3 | Acceptance creates the right membership | dashboard phase 1 (staff, `start`, active); `staff_login_test` (one membership); pgTAP 17 |
| 4 | Never sent to Create Arena | Staff app has none (widget test); a single active membership opens the floor; dashboard phase 1: invitee not owner level, owner not detoured |
| 5 | Membership failure recoverable | Failed screen with Try again / Sign in again; message tests; start-up classification tests |
| 6 | Restore after restart | `staff_login_test` restart |
| 7 | Expired session | `staff_login_test` (server-refused refresh); `stored_session_test` |
| 8 | Inactive / revoked | `staff_login_test` off/on; `two_device_sync_test` revoke; pgTAP |
| 9 | Other arena | `staff_login_test`; arena isolation spec; pgTAP 01 |
| 10 | Owner routing intact | dashboard phase 1, admin auth specs (parent session); staff app owner tab tests |
| 11 | Account switch / logout | `staff_login_test` own file; admin LoginScope specs (auth session) |
| 12 | Duplicate acceptance | phase 1 `invite_used`; one membership; pgTAP 17 |
| 13 | Retry without duplicates | `staff_login_test` replay; `two_device_sync_test` payment retry |
| 14 | Staff session reaches the owner | `staff_login_test` (owner reads it); phase 5 (Sales screen data layer) |
| 15 | Existing suites | all pass (above) |

Not covered by automation: the `CloudRoot` widget itself driven end to end (its
decisions are tested, the screens are tested on their own). Check that by hand.

## 4. Hosted: not verified (needs your approval)

Hosted login was **not** tested and cannot work for invited staff until:

1. **Hosted schema:** push `0016` … the latest migration in DEPLOY_SUPABASE.md §4a
   order. Dry-run first, check the hosted publication first, never
   `--include-seed`, never `reset --linked`.
2. **Edge Function:** deploy `staff-admin` with `ADMIN_SITE_URL` (and
   `ADMIN_ORIGINS`).
3. **Auth settings:** Site URL and redirect URLs `/accept-invite` and
   `/reset-password`; custom SMTP; Realtime "Allow public access" off.
4. **Dashboard production config:** the hosted URL and publishable key in
   `environment.production.ts`; deploy to an https origin.
5. **Two-phone test:** DEPLOY_SUPABASE.md §7, after steps 1–4.

Until then, test the whole flow on **one** backend: the local dashboard (`npm run
dev`) with the staff app from `tool/dev_run.sh` (iOS Simulator, or Android emulator
with `ANDROID=1`). (The "Server: …" line on the sign-in screen was removed again
later at the owner's request; a debug build prints the server in the log instead.)

## 5. Open items (not changed here)

* **Device feed scope.** `sync_pull` sends every arena row (payments and customers
  included) to every active member's device. The staff app hides Money / Reports /
  Today and RLS blocks direct reads, but the device copy exists. This is an open
  product decision (DEPLOY_SUPABASE.md §1).
* **Physical devices on the local stack.** `tool/dev_run.sh` has no option to point
  a physical device at the Mac's local stack (LAN address).

## 6. Invitation service: "name resolution failed" (local stack)

**Symptom.** Users → Invite user answered `503 {"message":"name resolution failed"}`, and the
dashboard showed "The invitation service is not running, so nothing was sent."

**Root cause (evidence).**

* `name resolution failed` comes from the local API gateway (Kong 2.8.1), not from the database,
  Auth or the mail provider. Kong routes `/functions/v1/*` to
  `http://supabase_edge_runtime_arena_ops:8081` (from the gateway's own config), and that
  container did not exist.
* `supabase status` listed `supabase_edge_runtime_arena_ops` under *Stopped services*.
* `supabase start` on a running stack did not recreate it.
* Controlled reproduction: no container → 503. While `supabase functions serve` ran → 204.
  Seconds after it exited → the container was removed and the gateway answered
  `name resolution failed` again. `functions serve` takes over the stack's runtime container and
  removes it on exit. `tool/sync_it.sh` started and stopped such a server on every run, so every
  integration run (and any hand-started `functions serve`) left the dashboard unable to invite.
* `config.toml` itself was right: `[edge_runtime] enabled = true`, `[functions.staff-admin]
  verify_jwt = false`, both dashboard origins in `additional_redirect_urls`. The function needs
  no extra configuration locally: it takes the link base from the dashboard's `Origin`, and the
  stack's URL and keys from the runtime.

**Fix.**

| Change | Why |
|---|---|
| `supabase stop && supabase start` (done; data kept) | Brings the stack's runtime back. Since then `staff-admin` answers directly (`401 unauthorized` without a session). |
| `tool/sync_it.sh` | Uses the stack's runtime when it answers. Serves its own only when the stack has none, and then says how to repair the stack. One run at a time (lock in `supabase/.temp`). New step 0, and step 6 checks the runtime is still up after the run. `AO_IT_KEEP_LOGS=1` keeps the logs of a passing run. |
| `tool/it_invitations.sh` (new, step 0) | The function over HTTP as the dashboard calls it (see the evidence below) |
| `supabase/functions/staff-admin/index.ts` | Every call to Auth or the database times out after 10 s. Auth or the database not answering is now `503 service_unavailable` with nothing created; before, it read as "session expired" or a generic error. A failed withdraw of an unsent invite is logged. |
| `apps/admin/src/integration/it-env.ts` | The dashboard specs send the `Origin` header a browser sends (Node's `fetch` sends none), so the stack's own runtime builds the link exactly as for a real browser |
| `apps/admin/.../users-api.ts` (+ spec) | A gateway 404 (function not deployed, e.g. hosted) says "Invitations are not set up on the server yet" instead of a generic error |
| `docs/SYNC.md` | How the local stack serves invitations, the symptom, `supabase stop && supabase start`, and no hand-run `functions serve` |

**Evidence (local).** `tool/sync_it.sh` run `8473fde2`: all steps PASS. Step 0, 31 checks:

* **Who may invite:** no session or a bare API key → 401. Floor staff without Settings, a
  login with no membership, an owner naming another arena → 403. Nothing is created or
  e-mailed.
* **What is accepted:** a bad e-mail, unknown role, a password field or a blank name → 400
  `invalid_input`. An unknown permission → 400 `invalid_permission`.
* **The owner invites:** 200 sent; it expires in 7 days; it is pending; the e-mail arrives.
* **Re-invite:** inviting the same address again leaves one pending invite, the first link is
  refused (`invite_revoked`), the newest link signs the person in and is accepted, and a second
  accept is refused (`invite_used`).
* **Mail catcher stopped:** 502 `email_failed` and nothing pending (withdrawn). Once it is back,
  the retry is sent.
* **Database API stopped:** 503 `service_unavailable`; nothing is created or e-mailed.

Steps 1–5 still pass (invitation by e-mail, acceptance, staff app sign-in and session, Sales),
and step 6 confirms the runtime is still up. `verify_all.sh` all PASS: `flutter analyze` clean;
`flutter test` 752 passed, 31 skipped; admin 238 passed, 3 skipped; admin build; pgTAP 920/920;
advisors clean.

**Hosted.** Not touched. The hosted project has no `staff-admin` deployed (its gateway would
answer 404, which the dashboard now words as "not set up"). Deploying the updated function is
part of the approval-gated hosted bring-up in §4.

## 7. Staying signed in, and session timers with the app in the background

**What the owner asked.** Staff stay signed in across app restarts, and a running session's
timer and its alerts keep working while the app is in the background or closed.

**How it works now.** A session's timer is computed from its stored start and end times, so it
is right the moment the app comes back; nothing has to "run" in the background for that. The
5-minute, 1-minute and time-up alerts are handed to the phone's OS (Android exact alarms, iOS
scheduled notifications), so they ring with the app in the background, swiped away, or after a
reboot (Android boot receiver). The sign-in is kept in the phone's secure storage and refreshed
by Supabase.

**Defects found and fixed (staff app).**

| # | Defect | Fix |
|---|---|---|
| 1 | Every app start cancelled **all** scheduled alerts (booking reminder clean-up) and never put the session alerts back: a running session restarted or reopened after the app was killed rang nothing. | `reminder_startup.dart`: start-up and every refresh reschedule booking reminders and the alerts of every running session and group **in place** (same ids replace the old ones, so nothing due is cancelled first); only at start-up, what an earlier run left that is no longer wanted is swept afterwards. |
| 2 | Cloud mode (hosted, release builds) never asked for notification permission: on Android 13+ / iOS no alert could ever show. | `startReminders` asks once, in both modes. |
| 3 | A session ended, extended or moved on **another** device kept its old alerts here (stale "time up", or none after an extension). | After every sync that brings changes, and on resume, alerts are rebuilt from the database (debounced, one rebuild at a time). |
| 4 | A refresh that read a session (or booking) just before this device extended or cancelled it could put the old alert back (time-up early, or a reminder for a cancelled booking). | All alert work runs one at a time and re-reads the session or booking when it runs. Alerts are set latest-first (iOS keeps only the 64 most recently set, so the soonest are kept). |
| 5 | Phone clock off by more than the warning threshold: the app follows server time, the OS rings by the phone's clock — alerts early or late by the difference. | `device_time.dart`: alert times are converted to the phone's clock, and rescheduled when the measured offset changes (e.g. staff fix the clock). |
| 6 | Phone clock slow: the server counts the access token as expired while the phone thinks it is valid. Sync stopped with "Sign in again", and at start-up the app **signed the person out**. | The API refusing the token → refresh once and retry (`rpcWithFreshToken`, used by sync and by the arena list). Only a refusal after a fresh token means "sign in again". |
| 7 | A weak or captive network could leave start-up on the spinner (no time limit on the stored-sign-in check or the arena list). | 8 s / 10 s limits; then it opens the last arena from this phone offline, still signed in. |
| 8 | A person in several arenas got the arena list on every start. | The last arena worked in on this phone reopens (while still active); More → **Switch arena** goes back to the list. "Try again" after a failed open retries that arena, not the last one. If one arena's database cannot open safely, the list is shown so another can be used. |
| 9 | A change made just before the phone was locked waited until the app was opened again (the 300 ms send was cancelled on pause), so other devices did not see a just-started session. | `SyncEngine.pause()` sends what is waiting, then stops; sign-out and switching arena do the same before closing the database. |
| 10 | Android 12+ with "Alarms & reminders" off: scheduling threw and the alert was lost. | Falls back to an inexact alarm (may be a little late) instead of none. |
| 11 | Signing out (or access turned off) left that arena's alerts scheduled, which this phone could no longer move or stop. | Leaving an arena cancels its scheduled alerts; signing in again reschedules them. Delivered alerts stay in the tray. |
| 12 | Sign-out showed the sign-in form while the old arena was still closing: a quick next sign-in (shift handover on a shared tablet) could be signed out again, its database closed and its alerts cancelled. | "Signing out…" until the old arena is closed and signed out; only then the sign-in form. |
| 13 | A sign-in the server refused while the arena was opening (after an offline start) left the app open with no sign-in and sync silently stopped. | Checked right after opening: back to Sign in. The arena list of a previous login is never reused. |
| 14 | "Turn reminder off" on a booking was undone by the next refresh. | Reminders skip bookings whose reminder is off; turning it on sets the status first. |
| 15 | A booking or session alert that had already rung could be removed from the tray by a refresh, and an alert due that very moment cancelled. | Only alerts this run set to ring **later** are ever cancelled (a moved booking, an extension the server refused); one due or rung is left alone. |
| 16 | Checking in a booking started a session with **no** timer alerts (older bug). | Check-in schedules them like a walk-in start. |
| 17 | Opening an arena that threw (disk full, a failing migration step) left a dead "Opening…" spinner. | Clean-up and a "Try again" that repeats the open (or the whole start after an offline start). |
| 18 | Sign out from the arena list or the failure screen skipped the safe sign-out path. | Every sign-out goes through one path ("Signing out…", alerts cancelled). |

Also: a station switch reschedules the alerts (their title names the station); Sync → **Sync now**
also resumes background syncing if it had stopped on a token problem.

**Limits that remain (platform rules, not bugs).**

* iOS suspends apps in the background: sync and Realtime pause until the app is opened again.
  The alerts still ring (they are with the OS); changes from other devices arrive on resume.
* Android may delay exact alarms in deep battery saving (Doze: at most one every ~9 minutes per
  app). A counter tablet that is plugged in or in use is not in Doze. If phones carried in pockets
  must ring exactly, the time-up alert can use Android's alarm-clock mode (exempt from Doze; shows
  an alarm icon in the status bar) — an owner decision, not done.
* iOS time-sensitive notifications (break through Focus modes) need an entitlement on the signing
  identity — not done (the owner holds the signing account).
* Force-stopping the app in Android settings cancels its alarms until it is opened again (Android
  rule); opening it reschedules everything.

**Review.** Two adversarial review rounds (independent reviewers per area, each finding checked by
a skeptic) found rows 4 and 12–18; all fixed. Left as is (low): booking actions wait for a queued
alert rebuild before returning (a fraction of a second); `CloudRoot` itself has no widget test (its
decisions are tested separately — `arenaToOpen`, `classifyStartupFailure`, `confirmAccess`).

**Tests.** `test/app/session_reminders_test.dart` (restart + sweep, sweep skipped after a failed
rebuild, refresh never cancels first, ended/extended on another device, the extension race, a
refused extension, an alert due right now, check-in, station switch, slow phone clock),
`test/app/booking_reminders_test.dart` (in-place reconcile, reminder off stays off, rung reminder
stays in the tray, moved booking), `test/data/sync/sync_engine_test.dart`
(pause sends / keeps offline), `test/data/sync/sync_transport_test.dart` (token refresh-and-retry,
second refusal, refresh offline, `my_arenas`), `test/app/sync/stored_session_test.dart` (Auth never
answers), `test/app/sync/staff_access_test.dart` (which arena reopens).
