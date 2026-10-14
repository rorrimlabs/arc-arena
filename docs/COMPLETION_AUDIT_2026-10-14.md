# Functional completion pass — 2026-10-14

Scope: every feature of the admin dashboard (`apps/admin`), the staff app (`apps/mobile`) and the
Supabase backend (`supabase/`), traced UI → action → repository/API → `sync_push` → `op_*` →
database → other client. Inventory first (three read-only sweeps, then the code itself), then
fixes in priority order. Nothing committed, pushed or deployed; hosted Supabase untouched.

**Baseline before any change** (local stack): pgTAP 761/761, admin unit 136 + 3 skipped
(integration), drift check clean. Flutter suite not run before changes (run after: see §7).

**Pre-existing uncommitted work, left untouched:** `apps/admin/angular.json` (CLI analytics id),
`apps/admin/src/app/features/users/data/users-api.ts` + untracked `users-api.spec.ts`
(invitation failure mapping), `supabase/functions/staff-admin/index.ts` (failure logging).

## 1. Feature completeness matrix

Statuses: COMPLETE AND VERIFIED · IMPLEMENTED — TEST INCOMPLETE · PARTIALLY COMPLETE ·
BLOCKED — EXTERNAL PREREQUISITE · BLOCKED — PRODUCT DECISION · NOT IMPLEMENTED.
"IT" = the real local cross-app suite (`tool/sync_it.sh`: Angular data layer + Flutter sync stack +
Edge Function + Mailpit on one local Supabase). Nothing here was tested on a real device or on
hosted Supabase.

### Catalog and configuration

| Feature | Dashboard | Staff app | Server | Tests | Status |
|---|---|---|---|---|---|
| Game create / full edit (title, platforms, player mode, players per station, age, media) | Add + **Edit dialog (new)** | owner editor (Settings → Games), now keeps aliases | `game.upsert`: **name trimmed, 1–80, unique ignoring case (new)** | pgTAP 16, 19; admin spec; IT phase 1 | COMPLETE AND VERIFIED |
| Game archive / restore | Available switch; "Archive" offered from Delete | archived games leave every picker | `game.set_active` (no-op repeat, validated) | pgTAP 19; Flutter lifecycle test; IT 1/4/5 | COMPLETE AND VERIFIED |
| **Game delete** | **Delete (new)**: checks usage, explains, offers Archive | drops deleted games (**tombstone fix**) | **`game.delete` (new)** | pgTAP 19 (67 checks); admin spec (6); Flutter lifecycle; IT 1/4/5 | COMPLETE AND VERIFIED |
| Station compatibility | per-station select | View games (now keeps & shows notes); owner editor (only changed stations) | `game.set_compat` keeps note when not sent | pgTAP 19; admin + Flutter widget tests; IT | COMPLETE AND VERIFIED |
| Game categories | not offered | read only | **no op writes `game_categories`** (seed fixture only) | — | BLOCKED — PRODUCT DECISION |
| Game control guide | not offered | owner editor | `game.replace_controls` | pgTAP 19 (applied once) | PARTIALLY COMPLETE |
| Stations add / edit / out of service / remove | yes; **Restore removed (new)** | owner screens | **busy guard on the server (new)**; edit without status keeps it | pgTAP 15, 20; admin specs | COMPLETE AND VERIFIED |
| Station kind / order edit | not offered | owner screens | `resource.upsert` | — | PARTIALLY COMPLETE |
| Station types (activities) | add, edit, **Remove (new, was unreachable)** | read | `activity.upsert/remove` | pgTAP 15; admin spec | COMPLETE AND VERIFIED |
| Rates | yes | owner screens | `rate.*`, server re-pricing | pgTAP 08, 15; parity script (not run) | COMPLETE AND VERIFIED |
| Happy hour windows | yes; name / price change / applies-to disabled | owner screen | `settings.save business_hours` | admin spec; pgTAP 08 | PARTIALLY COMPLETE |
| Opening hours | yes; cannot cross midnight | owner screen | same | admin spec | PARTIALLY COMPLETE |
| Holidays | **no dashboard UI** | owner screen | `holiday.*` | **pgTAP 20 (new)** | PARTIALLY COMPLETE |
| Billing policy | **no dashboard UI** | owner screen | `policy.save` | none | PARTIALLY COMPLETE |
| Floor options (payment methods, presets, warning) | yes | read | `_floor_options` validation | pgTAP 16; IT phase 1 | COMPLETE AND VERIFIED |
| GST / discounts / invoices / membership plans | disabled placeholders | — | — | — | BLOCKED — PRODUCT DECISION (OWNER_CONFIRMATION.md) |
| Controller inventory | **no dashboard UI** | owner screens + board | `controller.*` | pgTAP 12, **20 (set_status, new)** | PARTIALLY COMPLETE |

### People and access

| Feature | Dashboard | Staff app | Server | Tests | Status |
|---|---|---|---|---|---|
| Owner sign-up, confirm, create arena | yes; empty-arena copy fixed; staff logins told to use the app (new) | — | `create_my_arena` | auth specs; pgTAP 09 | COMPLETE AND VERIFIED |
| Sign-in / sign-out | yes | yes (stored session, revocation) | Supabase Auth | specs; Flutter auth tests | COMPLETE AND VERIFIED |
| Password reset | missing | — | — | — | NOT IMPLEMENTED |
| Invitations (invite, accept, withdraw) | yes (your uncommitted error mapping) | — | `invite_member`, `accept_invite`, Edge Function | pgTAP 17; IT phase 1 (real e-mail via Mailpit) | COMPLETE AND VERIFIED |
| Staff permissions / deactivate | floor perms only; **confirm on deactivate, self and owner-level guards (new)** | owner screen, **now through a guarded action (new)** | `staff.update` rules | pgTAP 07, 10, 13; admin + Flutter tests | COMPLETE AND VERIFIED |
| Grant money / reports / settings from the dashboard | not offered | owner screen | allowed for owners | — | PARTIALLY COMPLETE |
| Dashboard access for money/reports-only managers | **read-only banner, every write control disabled (new)** | — | writes need `settings` | admin suite (no dedicated test) | IMPLEMENTED — TEST INCOMPLETE |
| Members | read-only (phones masked but downloaded) | create; profile; **no edit UI** (`customer.update` unused) | `customer.*` | pgTAP 16; Flutter tests | PARTIALLY COMPLETE |

### Floor (staff app) and money

| Feature | Status | Notes |
|---|---|---|
| Start / switch / change game / change controllers / extend / end / pay | COMPLETE AND VERIFIED | unit + pgTAP 07/08/11/12 + IT two-device |
| Group sessions | IMPLEMENTED — TEST INCOMPLETE | **was hard-coded to activity `PS5`; now the arena's console type (new `groupActivityCode`, unit-tested); no widget test** |
| Bookings create / edit / check-in / cancel | COMPLETE AND VERIFIED | **edit no longer wipes party name & phone (new test)** |
| Booking no-show / missed bookings | COMPLETE AND VERIFIED | **Mark no-show (new action, server op tested in pgTAP 20); a passed slot no longer shows "Reserved"; listed as Missed** |
| Controller board, loans, returns | COMPLETE AND VERIFIED | unit + pgTAP 12 + IT |
| Session log | COMPLETE AND VERIFIED | **bill amounts only for bill/money/reports (matches RLS)** |
| Sync status strip, Sync screen | COMPLETE AND VERIFIED | **~40 refusal codes now worded (new test)** |
| Shift / Issues | NOT IMPLEMENTED | deliberate "not in this build" pages |
| Owner tabs in the staff app (Today, Money, Reports, Settings) | out of SLC scope | to be hidden later (CLAUDE.md) — not extended |
| Sales list / bill / void (dashboard) | COMPLETE AND VERIFIED | **an open bill another device changed now reloads (new test)**; IT phase 2 |
| Refunds from the dashboard | NOT IMPLEMENTED | floor app only |
| Overview | PARTIALLY COMPLETE | "Discounts given" placeholder |

### Sync, realtime, offline

| Feature | Status | Notes |
|---|---|---|
| Push (outbox, exactly once, replay) / pull (cursor, tombstones) | COMPLETE AND VERIFIED | pgTAP 07; Flutter engine tests; IT |
| Realtime nudges both ways, private channel, arena isolation | COMPLETE AND VERIFIED | IT phases 1 and 3; pgTAP 18 |
| Device drops deleted games / station types | COMPLETE AND VERIFIED | **was ignored**; Flutter lifecycle test + IT (game deleted after the device had it) |
| Dashboard catch-up after a dropped socket | IMPLEMENTED — TEST INCOMPLETE | **now refreshes every screen (new unit test); not exercised live** |
| Dashboard `retry` answers | COMPLETE AND VERIFIED | **resent with the same op ids, then "Busy right now" (new tests)** |
| Edit conflicts on games (offline queue, two owners) | COMPLETE AND VERIFIED | `base_active` from both clients; pgTAP 19; admin + Flutter tests |
| Dashboard data-layer races | COMPLETE AND VERIFIED | one failing read no longer blanks other screens; arena switch race in Pricing/Users/Floor options fixed (new test) |

## 2. Bugs and gaps found (all confirmed in code)

Fixed in this pass (file paths in §3):

1. No way to delete a game; the dashboard's "Remove" (delete icon) only hid it.
2. The staff app ignored `games` and `activities` tombstones: deleted rows stayed on every device and selectable.
3. A queued or stale game edit (both apps send the whole row incl. `active`) silently un-archived a game.
4. A queued edit after a delete would re-create the deleted game (`game.upsert` is an upsert).
5. Game names: server accepted blank names and case-only duplicates; the dashboard checked only on create.
6. Dashboard games were created single-player/1 controller with no way to edit title, platforms, player mode or players per station (multiplayer games unusable on the floor).
7. Dashboard station-status saves sent `notes: null`, wiping notes staff wrote on the floor.
8. Phone game editor wiped aliases and re-sent every station's status with no note.
9. Phone "Manage" / "Add a game" opened the owner editor for staff without Settings.
10. Editing a booking on the phone wiped its party name and phone.
11. Group sessions only worked for an activity coded `PS5`.
12. Session log showed bill money to staff without bill/money/reports.
13. Floor header hard-coded "404 Arena · Koratty" in every arena.
14. Missed bookings held a station as "Reserved" forever; no way to mark a no-show.
15. View games status editor started empty, so any change wiped the note.
16. ~40 server refusal codes shown to staff as "refused (code)".
17. Staff & roles wrote `staff.update` from the widget, no guard, uncaught exception in cloud mode (and the message pointed at a screen that no longer exists).
18. Dashboard admitted money/reports-only managers to editors the server refuses.
19. One failed read hid the Games/Members lists; "Try again" did not retry it.
20. An open Sales bill did not refresh when another device voided/paid it.
21. Removed stations could never be restored (name stays taken; confirm text promised otherwise).
22. Station-type removal built but unreachable.
23. Users: deactivate without confirmation; own access / owner-level members editable though the server refuses.
24. Dashboard showed the SQLSTATE ("40001") for a busy server and never retried.
25. Dashboard reconnect caught up only on floor data; nudges force-loaded 90 days of plays for unopened screens.
26. Arena-switch race in Pricing/Users/Floor-options stores.
27. A busy station could be taken out of service or removed by any client (client-only rule), and a stale rename could flip a station's status.
28. The create-arena page promised a sample catalog that no longer exists.
29. Tooling: `tool/sync_it.sh` ran the floor test files in parallel in one arena; two of them use the same station, so the run could fail at random.

Found, not fixed (see §8): password reset; dashboard UIs for holidays, billing policy,
controllers, refunds, members edit, granting money/reports/settings; `policy.save`,
`group.switch`, `group.end_player` still have no pgTAP test; members' phone numbers downloaded
in full; dashboard stores not cleared on sign-out and `signOut` uses scope `local`; game
categories; renaming a played game renames it on past bills.

## 3. Changes (actual paths)

**Backend** (declarative schema → generated migrations, applied locally only):
`supabase/schemas/public/functions/op_game_delete.sql` (new), `op_game_upsert.sql`,
`op_game_set_active.sql`, `op_game_set_compat.sql`, `op_resource_set_status.sql`,
`op_resource_upsert.sql`, `_sync_apply.sql` (`game.delete`), `tables/games.sql` (docs);
generated `supabase/migrations/20261014053857_game_lifecycle_delete_archive.sql` and
`20261014065708_station_status_guard.sql`; tests `supabase/tests/19_game_lifecycle_test.sql` (new),
`20_floor_and_config_ops_test.sql` (new), `15_catalog_from_scratch_test.sql` (closes its session
before retiring the station, as the new rule requires).

**Dashboard** (`apps/admin/src/app/`): `core/floor/floor-api.ts`, `floor-api.sample.ts`,
`floor-store.ts`, `floor.models.ts`; `core/sync/push-ops.ts`, `realtime-sync.ts`;
`core/arena/arena-context.ts` (`canEdit`); `core/layout/shell.html` (view-only notice);
`shared/list-detail/unsaved-bar.ts`, `shared/confirm/confirm-dialog.ts` (info-only variant);
`features/games/*` (page, detail, stations, dialog, view helpers); `features/stations/*`
(restore, rename keeps status); `features/pricing/components/type-detail.ts` (Remove),
`features/pricing/data/pricing-store.ts`; `features/users/components/user-detail.ts`,
`invite-list.ts`, `users-page.ts`, `data/users-store.ts`; `features/settings/data/floor-options.ts`;
`features/sales/data/sales-store.ts`; `features/members/members-page.ts`;
`features/auth/create-arena.ts`; specs for games, sales, stations, pricing, users, push-ops,
realtime-sync; `src/integration/dashboard-phase1.it.spec.ts`, `dashboard-phase2.it.spec.ts`.

**Staff app** (`apps/mobile/lib/`): `data/sync/sync_applier.dart` (games/activities tombstones);
`data/local/local_catalog_repository.dart` (`base_active`, notes in `gamesForResource`),
`local_user_repository.dart` (message); `domain/repositories/catalog_repository.dart`;
`domain/services/group_activity.dart` (new); `app/controllers/catalog_actions.dart`
(changed-stations-only save, `saveStaff`), `booking_actions.dart` (party details kept,
`markNoShow`); `features/games/presentation/game_edit_screen.dart`, `no_games_state.dart`;
`features/new_session/presentation/game_picker_sheet.dart`;
`features/floor/presentation/floor_screen.dart`, `sheets/change_game_sheet.dart`,
`sheets/view_games_sheet.dart`; `features/group_sessions/presentation/group_session_screen.dart`,
`sheets/group_assign_sheet.dart`; `features/bookings/presentation/upcoming_bookings.dart`;
`features/reports/presentation/session_log_screen.dart`, `session_history_screen.dart`;
`features/sync/presentation/sync_screen.dart`; `features/more/presentation/staff_screen.dart`.
Tests: `test/data/sync/catalog_lifecycle_sync_test.dart` (new),
`test/domain/services/group_activity_test.dart` (new),
`test/features/sync/refusal_reasons_test.dart` (new), additions in
`test/app/booking_permissions_test.dart`, `test/app/catalog_actions_test.dart`,
`test/features/floor/view_games_sheet_test.dart`, `test/sync/cross_app_test.dart`.

**Tooling / docs:** `tool/sync_it.sh` (`--concurrency=1` for the floor phase), `supabase/README.md`,
`docs/SYNC.md`, `docs/DEPLOY_SUPABASE.md` (§4a: the two new migrations).

## 4. Game lifecycle — design and evidence

What the schema already had: `games.active` (archive), tombstone triggers on `games`,
`game_resources`, `game_controls`; `session_segments`, `group_assignments`,
`controller_allocations` → `games` with **no cascade** (history pins the row);
`bookings.game_id` **on delete set null** (a delete would silently strip a booking's game);
no game name snapshot anywhere (bills show the live name); no op deleted games. No table change was
needed.

Rules now (server-enforced, every client):

| Case | Result |
|---|---|
| Never used (no segment, group player, pad allocation or booking) | `game.delete` deletes it with its station statuses and control guide; devices get tombstones |
| Being played now | `game_in_play`; archive allowed, the sessions continue (end/extend/reconfigure don't check `active`) |
| Past sessions, group play, pads or bookings | `game_has_history` (hint says which); archive instead; bills and bookings keep it |
| Archived | hidden from every picker on every device; kept for history; restore any time |
| Retry / duplicate request | same op id replays; a new op id on a gone game returns `{deleted: true}` |
| Delete racing a start | row lock + re-check after it; FK backstop (a direct delete of a used game fails with 23503) |
| Edit queued before a delete | refused `not_found` (tombstone check) — never re-created |
| Edit made over a newer archive/restore | refused `stale` (`base_active`), device converges |
| Wrong arena / no `settings` | `not_found` / `forbidden`; non-member's `sync_push` fails `forbidden` |

Why the server does not refuse a session start on an archived game: a device offline when the
game was archived may already have started it, and a refused start rolls the session off that
device's floor. Residual risk, documented: an offline device that starts a session on a game the
owner *deletes* (possible only if it had never been used anywhere) gets `not_playable` on
reconnect; the session lands in Sync → Needs attention.

Evidence: pgTAP `19_game_lifecycle_test.sql` 67/67; admin `games-page.spec.ts` (delete, history,
in play, archived info-only, race between check and delete, edit, stale edit, select revert);
Flutter `catalog_lifecycle_sync_test.dart` (tombstones, archive, `base_active`, changed-stations
save, alias-preserving form); IT phase 1 (archive + delete + duplicate + no-resurrection on the
real server), phase 4 (floor device: archived hidden, deleted absent, a game deleted after the
device had it disappears with its station status), phase 5 (after the floor played it: delete
refused `game_has_history`, archive applied, the bill untouched, another arena refused).

## 5. Authorization and security

Unchanged guarantees re-verified: no client writes outside `sync_push`; every new/changed op is
SECURITY DEFINER with pinned `search_path`, server-only (generated migration revokes `public`,
`anon`, `authenticated` from `op_game_delete`); pgTAP 13 (client surface) passes; advisors: no
issues. New server rules: station busy guard; game name rules; stale/resurrection guards.
Client gating now matches the server for Settings-level writes on the dashboard and for the game
editor on the staff app. No secrets were printed; the integration suite used only the local demo
key inside its own script.

## 6. Offline and conflicts

Conflicting offline work is still refused, never merged (SYNC.md). New in this pass: game edits
carry `base_active`; station edits from the dashboard carry no status; the phone's game form
writes only changed stations. Known limit: `game.set_active` toggles are last-writer-wins
(an A→B→A sequence across two owners is not detected).

## 7. Tests run (all local; nothing hosted, nothing on a real device)

| Suite | Result |
|---|---|
| pgTAP `supabase test db --local` | 887/887 PASS (16 files; baseline 761) |
| `supabase db advisors --local --type all` | no issues |
| Declarative drift check (`sync --no-apply`) | "No schema changes found" after each migration |
| Admin unit (`ng test`) | 158 passed, 3 skipped (the live integration specs) |
| Admin build (development config) | PASS |
| Flutter `flutter analyze` | no issues |
| Flutter `flutter test` | 730 passed, 22 skipped (the live integration specs, which run inside `sync_it.sh`) |
| Cross-app integration `tool/sync_it.sh` (local) | ALL 5 PHASES PASSED (the first run failed on the parallel-files race, fixed) |
| `bash tool/verify_all.sh --with-it` | NO FAILURES: steps 1–7 PASS |
| Pricing parity, concurrency races (`--with-psql`) | SKIP (they drive `docker exec psql`); no pricing code changed |

## 8. Blocked or pending

Product decisions: game categories (add a write op, or drop categories); renaming a played game
renames it on past bills (snapshot the name, or steer owners to archive + new); whether the
server should ever refuse a start on an archived game; discounts / GST / invoices / membership
plans (OWNER_CONFIRMATION.md); billing policy per segment (billing-segment-policy.md); whether
floor devices should keep receiving all customers and payments in the sync feed; groups across
several console types; password reset; dashboard UIs for holidays, billing policy, controllers,
refunds, members edit, owner-level permissions.

External prerequisites (none done; each needs your approval and access):
* Hosted schema: push `0016` … `20261014065708` in DEPLOY_SUPABASE.md §4a order (dry-run first,
  check the hosted publication first, never `--include-seed`, never `reset --linked`).
* Auth: Site URL and redirect `https://<dashboard>/accept-invite`; confirm-signup template with
  `{{ .Token }}`; custom SMTP (the built-in sender only reaches team members); leaked-password
  protection; password policy.
* Edge Function: deploy `staff-admin` with `ADMIN_SITE_URL` (and `ADMIN_ORIGINS`) right after the
  push. Locally the edge runtime is **enabled** in `config.toml`, so the stack serves the function
  itself. Correction: an earlier version of this line said it was disabled. The local
  edge-runtime container disappears whenever a `supabase functions serve` exits, because that
  command takes over the same container; `supabase start` on a running stack does not recreate it.
  Every `tool/sync_it.sh` run served the function itself and exited, mine included. That left
  `ng serve` with no invitation service, and the dashboard showed "name resolution failed" (a
  gateway 503, which your uncommitted change words as "The invitation service is not running").
  `supabase stop` then `supabase start` brings it back. The staff-login session changed
  `tool/sync_it.sh` to reuse the stack's runtime, serve its own only when there is none, and hold
  a run lock.
* Realtime: turn off "Allow public access".
* Dashboard production config: the hosted URL and publishable key in the production environment
  file; deploy to an https origin.
* Floor app: `dart_define.prod.json` with `AO_BACKEND=supabase`, the https URL and the
  publishable key.
* Signing: Android `android/key.properties` + keystore, iOS team/profiles — yours to create.
* Hosted integration: the two-phone test (DEPLOY_SUPABASE.md §7) after the push.

## 9. Auth flow and Sales repair (second pass, 2026-10-14)

The staff app side of the same flow (sign-in, memberships and error wording on the floor app,
and why a locally invited person could not sign in on the counter tablet) was repaired in a
parallel session: see [STAFF_LOGIN_REPAIR_2026-10-14.md](STAFF_LOGIN_REPAIR_2026-10-14.md).

### Reported bug

After an owner invited staff and the invitee accepted (in the same browser, on `localhost:4200`),
the owner found the dashboard showing **Create your arena**.

### Root cause (reproduced before the fix)

1. The dashboard has one Supabase client whose session is stored in `localStorage`. Every tab of
   the origin shares that session, and supabase-js broadcasts sign-ins to the other tabs.
2. `/accept-invite` signed the invitee in **on that client** (`AuthApi.signInFromLink` →
   `setSession`). The invitee's session replaced the owner's in the whole browser.
3. The owner's tab followed the change (Shell: "another login signed in"). The guards then saw the
   staff login, which has no owner-level arena.
4. `arenaGuard` sent any login without an owner-level arena to `/create-arena`. That included
   floor staff, a login whose access was turned off, and a failed membership read.

Reproduction: `accept-invite.spec.ts` › "an owner signed in on this browser stays themselves while
someone accepts here". Before the fix it failed with
`expected 'farah@404arena.in' to be 'arjun@404arena.in'`. It passes now, and the same check runs
against the real local stack in integration phase 1.

### Fix

* **The invitee signs in apart from the dashboard**: `core/auth/invitee-auth.ts` (new). It runs on a
  separate in-memory client (`Supabase.isolatedClient()`): never stored, never refreshed, never
  broadcast. The page uses it for the link session, for sign-in with a password, for choosing a
  password, for `accept_invite`, and for checking whether the invitee may manage the arena
  (`my_arenas` as the invitee).
  * The owner's session is never touched. Staff press **Done**, which ends only the invitee's
    session; the owner is back on their dashboard.
  * An owner-level invitee takes over this browser's dashboard only by choosing **Open
    dashboard**. If someone else is signed in there, the page names them first.
* **One access state from server memberships** (`accessOf` in `core/arena/arena-api.ts`, used
  through `ArenaContext.access`). It reads only `staff_profiles` through `my_arenas`; e-mail and
  user metadata play no part.

  | State | Rule | Where it goes |
  |---|---|---|
  | `owner` | an active owner-level membership (role owner, or money/reports) | dashboard |
  | `staff` | active memberships, none owner level | `/account`: "Use the 404 Arena staff app" |
  | `off` | memberships, none active | `/account`: access turned off (owner: the operator restores it) |
  | `none` | no membership at all | `/create-arena` (the only state that can reach it) |
  | read failed | — | `/account`: "We couldn't check your access" + Try again (never Create Arena) |
  | restoring | — | guards wait for the stored session and the read (shared, one request) |
  | signed out | — | `/sign-in?next=<where they were going>`; after sign-in, back there (in-app paths only) |

* Guards: `arenaGuard` covers the dashboard and every owner screen, including direct URLs.
  `noArenaGuard` covers `/create-arena`. The new `/account` page is `features/auth/account-access.ts`.
* The Shell's live reaction now routes by access state, never to Create Arena for staff.
  `ArenaContext.load` shares an in-flight read, so concurrent guards make no duplicate requests.
* Sign-out and account switching clear in-memory data (`LoginScope`, added by the sign-out
  session); the new state builds on it.
* Removed the dead `AuthApi.acceptInvite`, so no future caller can accept on the shared session.
* Server: nothing needed to change. `accept_invite` already checks the token's hash and that the
  invitation is unused, unwithdrawn and unexpired. It requires the invited, confirmed e-mail and
  checks the inviter still holds the authority. It creates exactly one membership in that arena
  and never demotes an owner. pgTAP 17 gained three assertions: a repeated accept leaves exactly
  one membership; accepting staff creates no arena or ownership; the invitee's `my_arenas` is
  staff-only.

Files: `core/auth/invitee-auth.ts` (new), `core/auth/auth-api.ts`, `auth-api.sample.ts`,
`session.ts`; `core/arena/arena-api.ts`, `arena-context.ts`; `core/supabase/supabase.ts`;
`core/layout/shell.ts`; `app.routes.ts`; `features/auth/accept-invite.ts`,
`account-access.ts` (new), `create-arena.ts`, `sign-in.ts`; specs `accept-invite.spec.ts`,
`auth-flow.spec.ts`, `core/layout/shell.spec.ts`; `src/integration/dashboard-phase1.it.spec.ts`,
`dashboard-phase2.it.spec.ts`; `supabase/tests/17_staff_invites_test.sql`; `supabase/README.md`.

### Invitation behaviour (evidence)

| Case | Result | Where |
|---|---|---|
| Owner invites; invitee opens the link in the owner's browser and joins | owner stays signed in; Done returns the owner to the dashboard | admin spec; IT phase 1 (real stack) |
| New login sets a password, then accept fails (network) | Try again joins once; password not asked again | admin spec |
| Invitee signs in with another login | `invite_wrong_account`, nothing changes; "Sign in as someone else" | admin spec; pgTAP 17 |
| Expired / withdrawn / replaced / unknown token / used link | explained, nothing changes | admin spec; pgTAP 17 |
| Duplicate accept | `invite_used`, exactly one membership | pgTAP 17; IT phase 1 |
| Unconfirmed e-mail | refused | pgTAP 17 |
| Co-owner invite | dashboard only after Open dashboard | admin spec |

Routing (auth-flow spec):
* An owner refreshing on `/sales` stays there.
* An owner opening `/create-arena` lands on `/overview`.
* A new owner is sent to `/create-arena`.
* Staff opening `/`, `/sales`, `/users` or `/create-arena` all land on `/account`, with no form.
* A login whose access is off lands on `/account`.
* A failed membership read shows a retry and never Create Arena.
* A slow read: the guards wait, there is no detour, and one request is made.
* Sign-in returns to `?next=`; a crafted `//evil` link stays in the app.

### Sales and bills

Every value on Sales traced to its source. The bill and its status come from `sessions` /
`group_sessions` (completed or voided; `at` is the actual end, or the void time for a bill voided
while it ran). Stations, games and players come from segments and assignments, the total from
`billed_amount_paise`. Paid, refunded and per-method figures are the net of the
`payments` / `group_payments` ledger: refunds are stored negative, which the table's check
constraint enforces. Due is billed minus net paid, zero when waived or voided. Date filters are IST
calendar days, half-open on both sides.

* **Fixed:** the summary dropped voided bills entirely, so money already taken on them (voiding
  never refunds) was invisible. It now ends with "₹X on voided bills", so the day reconciles with
  the till. *Takings* keep their documented meaning (bills not voided), on both Sales and Overview.
* **Evidence:**
  * A unit test reconciles refunds, part-paid, waived and voided bills; the per-method totals add up
    to the takings.
  * IT phase 2 covers a bill completed on the staff app (Flutter):
    * it appears on Sales with the server-priced total and exactly one payment;
    * it matches the raw `sessions` row and the `payments` ledger per method, read through RLS;
    * the staff login that ran it is refused `arena_sales` / `arena_sale` (`forbidden`);
    * another arena's owner sees nothing.
* **Not offered on purpose:** manual historical entries and editing billed fields. Corrections go
  through `session.void` / `group.void` (owner level, reason and who recorded) and append-only
  refunds.

### Tests run (this pass)

| Suite | Result |
|---|---|
| Admin unit (`ng test`) | 236 passed, 3 skipped (live specs) |
| Admin build (development) | PASS |
| pgTAP | 920/920 (17 files; includes the other session's new test 21) |
| Advisors | no issues |
| `tool/sync_it.sh` | ALL 5 PHASES PASSED on the combined tree (this pass + the staff-login session's floor-app fixes and its 9 real-server tests). Earlier attempts failed only when two runs shared the local edge-function container, and once on the staff-login test before that session fixed it. |
| Flutter analyze / test | no issues; 752 passed, 31 skipped (live specs). This pass changed no Flutter code. |

### Remaining

* **Two backends, so staff could not sign in on the tablet.** The dashboard in development
  (`ng serve`) and `tool/dev_run.sh` use the local stack. A release build of the staff app
  (`dart_define.prod.json`) and `dart_define.hosted-dev.json` use the hosted project, where
  nothing after `0015` is deployed: `accept_invite`, `invite_member` and `create_my_arena` do not
  exist there. A person invited on the local dashboard has a login only on the local stack, so the
  tablet's release build answers "Invalid login credentials". This is not fixable in code; it ends
  with the hosted push (§8, DEPLOY_SUPABASE.md §4a). Until then, test the floor app with
  `tool/dev_run.sh` (STAFF_LOGIN_REPAIR_2026-10-14.md §1).

* `create_my_arena` still lets any confirmed login with no owned arena create one; that is
  server-side by design (one arena per login). The dashboard never offers it to staff. Refusing it
  on the server for logins that are staff elsewhere is a product decision.
* Hosted: the same prerequisites as §8. Also add `https://<dashboard>/reset-password` and
  `/accept-invite` to the Auth redirect URLs.

### Manual check that the original bug is gone (`ng serve`, local stack)

The local stack serves the `staff-admin` function itself (`[edge_runtime] enabled = true`). Do
**not** run `supabase functions serve` for this check: when it exits it removes the stack's
runtime container, and invitations then fail with `name resolution failed` until
`supabase stop && supabase start` (corrected 2026-10-14, see STAFF_HANDOVER_AUDIT_2026-10-14.md
§2.4 I2).

1. Sign in as the owner → Users → Invite a new e-mail as staff. A staff invitation from the
   dashboard grants Start, Bill and Members. Bill is what step 6 needs: ending a session and
   taking a payment both require it, so keep it if you change permissions later.
2. In the **same browser**, open the invitation from Mailpit (`http://127.0.0.1:54434`), choose a
   password and join. The page says to use the staff app.
3. Switch to the owner's tab and refresh. It is still the owner's dashboard; no Create Arena.
4. Press Done on the invitation tab. You are back on the owner's dashboard.
5. Sign out, then sign in as the invitee on the dashboard. You land on "Use the 404 Arena staff
   app". Typing `/sales` or `/create-arena` in the address bar lands there too.
6. Sign in as the invitee on the staff app run with `bash tool/dev_run.sh` (iOS Simulator; for an
   Android emulator use `ANDROID=1`). This runs against the same local stack. Do not use a
   release build or the physical counter tablet: a release build signs in to the hosted project,
   and on a tablet 127.0.0.1 is the tablet itself. The arena opens. End a session and take a
   payment.
7. As the owner, open Sales → Today. The bill is there with its payment; void it and the summary
   shows "on voided bills".
