# 04 — Flutter staff app (`apps/mobile`) pre-production audit

Auditor area: app engineering, security, lifecycle, reliability of `apps/mobile`
(pricing/billing semantics and staff-module business rules are covered by other
auditors). Read-only; no file other than this report was modified.

## Scope and method

- Hand-written Dart under `apps/mobile/lib` (~44k lines; `*.g.dart` /
  `*.freezed.dart` ignored), Android/iOS/macOS platform config, committed
  `dart_define*.json`, the Drift migration chain and its test fixtures, and the
  server functions the sync engine depends on (`supabase/schemas/private/functions/sync_push.sql`,
  `sync_pull.sql`) where needed to judge client behaviour.
- Docs skimmed: root `CLAUDE.md`, `docs/SYNC.md`, `docs/RELEASE.md`.
- Commands run:
  - `flutter analyze` (from `apps/mobile`, run once, outside the sandbox because
    the Flutter SDK cache write was blocked) → **`No issues found! (ran in 3.6s)`**.
  - `git ls-files` / `git check-ignore` on `dart_define*.json`; key prefixes and
    the legacy JWT `role` claim decoded locally (values never printed).
  - `git log -S` on `database.dart` to date the v17 column and version bump.
  - `grep` sweeps: `DateTime.now(`, `SystemClock()`, `debugPrint(`, `catch (_)`,
    `firstWhere(`, `nowProvider`, `syncOutbox`, `signOut`, `ReplayPause`,
    `dynamic`.
- Not run (by instruction / lean mode): `flutter test`, `flutter build`,
  `pub get`, migration tests, `tool/sync_it.sh`, `tool/pricing_parity.sh`.

## Architecture overview (short)

`main.dart` → `AppConfig.problemFor(releaseBuild: kReleaseMode)` gate → either
local mode (debug only: Drift file `arena_ops.sqlite`, PIN login, demo seed) or
cloud mode (`CloudRoot`: Supabase e-mail/password sign-in → `my_arenas` → one
Drift file per (arena, user) `arena_ops_cloud_<arena>_<user>.sqlite`, each opened
behind `DbSafety.protect`). Per arena a `ProviderContainer` is built with
`SyncEngine` (outbox push → rollback of refused entities → cursor pull, 10 s
poll + nudges + backoff), `RealtimeSync` (private channel nudges only, no data
applied), an `OffsetClock` following server time, and online-only attendance /
leave repositories. Writes: widget → `*Actions` (PermissionGuard, pure pricing)
→ `Local*Repository` (one Drift transaction: rows + one `sync_outbox` op) →
`Result<T>`.

---

## Findings

Severity counts: **P0: 0 · P1: 0 · P2: 6 · P3: 11**

## [P2][FL-001] A whole-batch push failure stalls the outbox and all pulls indefinitely (no batch shrink, attempt cap or dead-letter)
**Status:** LIKELY (code path VERIFIED; the server-timeout trigger NEEDS VERIFICATION against hosted limits)
**Category:** Reliability / sync
**Location:** `apps/mobile/lib/data/sync/sync_engine.dart:307-381`, `apps/mobile/lib/data/sync/sync_engine.dart:385-469`, `apps/mobile/lib/data/sync/sync_transport.dart:152-192`, `supabase/schemas/private/functions/sync_push.sql:35-64`
**Problem:** Per-op refusals are handled well (an op becomes `rejected`, later ops continue). But any failure of the *whole* `sync_push` call is retried forever with the same oldest-50 batch: `_push` always selects `status = pending ORDER BY seq LIMIT 50`; a non-offline exception lands in `on Object catch` → `SyncState.error` → `_backoff()` (max 60 s) → same batch again. `attempts` is incremented (line 403) but never read. Because `_reconcile` (rollback + pull) only runs when the outbox is empty (line 312), the device also stops receiving other devices' changes.
**Evidence:** `sync_engine.dart:388-393` (fixed batch selection), `:358-373` (generic error → backoff only), `:377-381` (backoff ladder, no cap), `:403` (attempts written, never consulted). Whole-batch failure sources on the server: `sync_push.sql:42` raises `op_id_reused` outside the per-op block; the uuid cast at `:36` is outside it too; and PL/pgSQL `exception when others` (line 55) does **not** catch `query_canceled`, so a statement timeout (Supabase's `authenticated` role default, no override found in `supabase/`) aborts the whole RPC — the `'57014'` retry branch at line 60 is unreachable for a timeout. Client-side, a response that fails `OpResult.fromJson` casts (`sync_transport.dart:35-44`) has the same effect.
**Impact:** One device's entire takings stream stops reaching the server and its floor view stops converging with other devices (more `resource_busy` / `stale` refusals later, including payments). Visible only as "Sync failed: …" on that device.
**Failure Scenario:** A counter tablet is offline for most of a busy evening and accumulates hundreds of ops (session ends with re-pricing, payments). On reconnect the first 50-op batch exceeds the statement timeout under load; every retry re-sends the same 50 ops and times out again. Nothing after them is pushed; nothing is pulled.
**Recommended Fix:** On a whole-batch server error/timeout, halve the batch (down to 1) before backing off; after N failures of a single-op batch, surface it as a blocked op with a clear "contact maintainer" state (not silently skipped — ordering matters). Server side (for the SQL auditor): handle `query_canceled` explicitly or cap per-call work; move the `op_id_reused` check and uuid cast into the per-op block.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** `tool/sync_it.sh` scenario with 300 offline ops against a stack with `statement_timeout` set as on hosted; unit test of `SyncEngine` with a transport that throws for batches > k.

## [P2][FL-002] A refused/adjusted catalog or staff op triggers a full-history pull (`limit: 100000` from cursor 0) that can stall pulls permanently at scale
**Status:** LIKELY (code path VERIFIED; failure threshold depends on arena history size)
**Category:** Reliability / performance / sync
**Location:** `apps/mobile/lib/data/sync/sync_engine.dart:517-564`, `apps/mobile/lib/data/local/local_controller_allocation_repository.dart:236-245`, `supabase/schemas/private/functions/sync_pull.sql:7-12,33-63`
**Problem:** When any outbox op with `entityType` `catalog` or `staff` is refused or `adjusted`, `_reconcile` re-reads the *entire arena feed from cursor `'0'`* (every session, segment, charge, payment, allocation, tombstone ever) in pages of up to 100 000 rows, then discards everything that is not a catalog table. The op keeps `needsRefetch = true` until this succeeds, so a failing full pull is repeated on every pass and, because it runs before the normal cursor pull, the device stops pulling altogether.
**Evidence:** `sync_engine.dart:527-529` (catalog/staff → `catalog = true`), `:548-563` (`transport.pull(arenaId, c, limit: 100000)` from `'0'`, filtered client-side by `catalogTables`). `sync_pull.sql` unions every `_sync_sources()` relation with `sync_xid >= cursor` — it is not table-filtered. A floor action creates such ops: `resource.set_mode` is recorded with `entityType: 'catalog'` (`local_controller_allocation_repository.dart:239-244`), as are all owner catalog edits still present in the app (`local_catalog_repository.dart:37-38`).
**Impact:** After months of history, a single refused RIFT mode switch (e.g. `mode_locked` / `stale`) makes the device download the arena's whole history in one RPC (tens of MB, likely beyond the 20 s client timeout or the server statement timeout); if it fails, the device never pulls again until the app data is reset.
**Failure Scenario:** Two staff switch the same RIFT station's mode from two tablets; the second is refused. That tablet's next passes each try to pull ~200k rows with `p_limit=100000`, time out (`SyncOfflineException` → "offline"), and repeat forever.
**Recommended Fix:** Add a catalog-only fetch (`sync_fetch_entity` type `catalog`, or a `p_tables` filter on `sync_pull`) and page it at the normal size; at minimum use the default page size and a table filter.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** Seed an arena with ~100k feed rows locally, force a refused `resource.set_mode`, observe pass duration / payload size.

## [P2][FL-003] Unsent takings are stranded in a person's device file when their access is turned off (or they never sign in on that device again)
**Status:** VERIFIED
**Category:** Reliability / money records / lifecycle
**Location:** `apps/mobile/lib/app/sync/cloud_root.dart:490-495`, `apps/mobile/lib/app/sync/cloud_root.dart:583-600`, `apps/mobile/lib/data/sync/sync_transport.dart:160-168`, `apps/mobile/lib/app/sync/staff_access.dart:43-47`, `supabase/schemas/private/functions/sync_push.sql:31-34`
**Problem:** Outbox ops live only in `arena_ops_cloud_<arena>_<user>.sqlite` and can only be pushed under that same login. When the owner turns a member's access off, `sync_push` refuses the *whole* call at its membership gate (42501), the engine marks `accessRevoked`, and `CloudRoot` signs the person out. Their pending ops (session ends, payments) stay in the file; nobody can push them unless access is restored and that same person signs in again on the same device. There is no export / hand-over path and the owner has no server-side signal that such ops exist. The voluntary sign-out path does warn (`more_screen.dart:48-71`), the automatic ones cannot.
**Evidence:** `sync_push.sql:31-34` (gate raises 42501 for non-members), `sync_transport.dart:161-167` (42501 → `SyncAuthException(revoked: true)`), `cloud_root.dart:494` (`if (s.accessRevoked) unawaited(_signOut(...))`), `staff_access.dart:43-47` (per-user file by design).
**Impact:** Money taken on the floor is missing from the server's records with no visibility — exactly the "only copy of the day's takings" case `CLAUDE.md` prioritises.
**Failure Scenario:** A staff member ends their last shift with the tablet on a flaky connection (12 ops pending incl. 4 cash payments). The owner deactivates them that night. Next morning the app shows "access turned off"; the 4 payments never reach the server.
**Recommended Fix:** Decide the business rule with the owner: e.g. let `sync_push` accept ops recorded *before* the deactivation time from a recently-deactivated member (server-validated), or provide an owner-side "recover device outbox" flow (another owner signs in on the device and pushes the stranded file's ops under an audited `recovered_from` attribution). At minimum, show the pending count on the "access turned off" screen and surface "device has N unsent ops" to the owner.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** `tool/sync_it.sh`: record ops offline, deactivate the member, reconnect; confirm ops are not lost / are surfaced.

## [P2][FL-004] Every Drift migration test fixture is invalid since v17 — the device upgrade path has no passing automated coverage
**Status:** VERIFIED (fixture defect). Real-device impact: LIKELY none (see below).
**Category:** Migration / verification gap
**Location:** `apps/mobile/lib/data/local/database.dart:651,815-826,843-863`, `apps/mobile/test/data/local/migration_test.dart:89-99,572-575,705-709`
**Problem:** The known failure `duplicate column name: overtime_grace_minutes` comes from the tests, not the app. Each fixture builds an "old" database with the *current* `AppDatabase` (`createAll`, which already has `activities.overtime_grace_minutes`), then strips the later additions it knows about (`users` PIN columns, `current_mode`, sync tables, `birth_year`, `pricing_rules`) and stamps an old `user_version`. None drops `overtime_grace_minutes` (no occurrence of `overtime_grace` anywhere under `test/`), so step 16 (`m.addColumn(activities, activities.overtimeGraceMinutes)`) hits a column that a genuine v16 file never had.
**Evidence:** `git log -S overtimeGraceMinutes` and `git log -S "expectedSchemaVersion = 17"` both point to the single commit `4fd1109`: the column and the bump shipped together, so no real v16 database contains the column and the step is correct for devices. Every later column add in history also bumped the version (scan of `database.dart` history). Step 16 also rewinds `pull_cursor` to `'0'` (line 823-825), forcing a full re-download of the arena feed on each cloud device at first open after upgrade.
**Impact:** The v10→…→v17 upgrade of "the only copy of the day's takings" is currently unverified; any future step regression would be masked by the already-red suite. The release runbook (`docs/RELEASE.md` §2) requires these tests.
**Failure Scenario:** A future additive step contains a real bug; the migration suite is already failing for a "known" reason, so the new failure is not noticed before release.
**Recommended Fix:** In every fixture builder add `ALTER TABLE activities DROP COLUMN overtime_grace_minutes` (and, generally, build fixtures from a frozen per-version schema — Drift `schema dump`/`schema steps` — instead of the current schema minus a hand-maintained list). Then re-run the migration tests.
**Estimated Effort:** Small
**Production Blocker:** Yes (verification gap: the upgrade path must be proven green before shipping v17 to devices holding real data)
**Suggested Verification:** Fix fixtures, run `flutter test test/data/local/migration_test.dart test/data/local/db_safety_test.dart`; additionally upgrade a real v16 device DB copy.

## [P2][FL-005] Android `allowBackup` defaults to true: unencrypted arena history, customer PII and DB backups are eligible for cloud/device backup
**Status:** VERIFIED (config); impact LIKELY
**Category:** Security / privacy
**Location:** `apps/mobile/android/app/src/main/AndroidManifest.xml:17-21`, `apps/mobile/lib/app/sync/staff_access.dart:46-47`, `apps/mobile/lib/app/sync/cloud_root.dart:320-326`
**Problem:** `<application>` sets neither `android:allowBackup="false"` nor `dataExtractionRules`/`fullBackupContent`, so Android Auto Backup (and device-to-device transfer) includes the app's internal files: every per-(arena, user) SQLite file (plain SQLite, no encryption) and the `arena_ops-backups/` directory holding up to 10 full copies per arena. Via `sync_pull` every active member's device holds the arena's full history — customer names/phones, all payments and bills — regardless of `money`/`reports` permissions. The Keystore-wrapped Supabase session cannot be restored on a new device (handled gracefully), but the data can.
**Evidence:** Manifest lines 17-21 (no backup attributes). `cloudDbPath` and `DbSafety.protect(backupDir: '${documentsPath}/arena_ops-backups')` both under app documents (`getApplicationDocumentsDirectory`, `main.dart:58`).
**Impact:** Business takings and customer PII copied into personal Google accounts of staff devices; restore onto another phone brings a stale DB with the same `device_id` (`sync_meta`).
**Failure Scenario:** A staff member's personal phone with the app backs up to their Google Drive; after they leave, the arena's customer list and takings remain in their account and restore onto any new phone.
**Recommended Fix:** `android:allowBackup="false"` (plus `android:dataExtractionRules` excluding everything for API 31+); consider `NSURLIsExcludedFromBackupKey` for the DB/backup directory on iOS; longer-term evaluate SQLCipher for the device DB.
**Estimated Effort:** Small
**Production Blocker:** No (recommended before go-live)
**Suggested Verification:** `adb shell bmgr backupnow in.rorrim.arena_ops` on a test device and inspect; check merged manifest of the release APK.

## [P2][FL-006] Release builds without `AO_ENVIRONMENT=production` record 100 % of sessions with Session Replay and 100 % traces
**Status:** VERIFIED
**Category:** Privacy / configuration
**Location:** `apps/mobile/lib/core/config/app_config.dart:70-78,180-183,198`, `apps/mobile/lib/core/monitoring/sentry_setup.dart:17-41`, `docs/RELEASE.md` §3
**Problem:** `environment` defaults to `'development'`; `replaySessionSampleRate` is 1.0 and `tracesSampleRate` 1.0 whenever it is not `'production'`. `problemFor` does not check it for release builds, and `docs/RELEASE.md` describes `dart_define.prod.json` as holding only `AO_BACKEND`, URL and key (only `dart_define.example.json` lists `AO_ENVIRONMENT`/`AO_SENTRY_DSN`; no doc mentions them). Adding a DSN to the prod file without the environment key ships full-session replay of a floor app that shows customer names and money (masked text/images, but tap positions, navigation and timing are recorded), tagged as "development".
**Evidence:** `app_config.dart:72-74` (`isProduction ? 0.1 : 1.0`), `:180-183` (default `'development'`), `sentry_setup.dart:20,38-41`.
**Impact:** Privacy exposure beyond the intended 10 % sample, Sentry quota exhaustion, production errors filed under the wrong environment.
**Failure Scenario:** Release built with a prod file containing `AO_SENTRY_DSN` only → every staff session on every device is replayed.
**Recommended Fix:** In `problemFor(releaseBuild: true)` require `environment == 'production'` when a DSN is set (or default to production when `kReleaseMode`); document the Sentry keys in `docs/RELEASE.md`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Unit test for `problemFor`/`configureSentry` in release mode without `AO_ENVIRONMENT`.

## [P3][FL-007] Repository catch-alls turn any write failure into "station in use" and hide it from telemetry
**Status:** VERIFIED
**Category:** Error handling / observability
**Location:** `apps/mobile/lib/data/local/local_session_repository.dart:360-371,491-502`, `apps/mobile/lib/data/local/local_group_session_repository.dart:293,400,529`
**Problem:** `start` and `reconfigure` end with `catch (_) { return Err(_busyFailure(...)); }` — this also catches `Error`s (TypeError, StateError), SQLITE_BUSY/disk-full, FK failures and outbox insert failures, reports them to staff as "in use", and never calls `AppTelemetry.captureException`.
**Evidence:** cited lines. The transaction rolls back, so no data corruption.
**Impact:** A production bug in session start/switch is invisible in Sentry and misleading on the floor.
**Failure Scenario:** A schema/data bug makes `session.start` throw on one station; staff see "in use" on a free station, nothing reaches Sentry.
**Recommended Fix:** Map only the unique-index violation to busy; for anything else return a generic `Failure` with a stable code and report the exception.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Code review + a repository unit test with a forced non-constraint exception.

## [P3][FL-008] Outbox history is never pruned; every launch backs up the growing file
**Status:** VERIFIED
**Category:** Performance / storage
**Location:** `apps/mobile/lib/data/sync/sync_engine.dart:431-456`, `apps/mobile/lib/data/local/db_safety.dart:124-140,362-370`
**Problem:** Applied ops (each `session.start` carries the full `pricing_snapshot` JSON) stay in `sync_outbox` forever (no delete anywhere: only `sync_recorder.dart:48` inserts and `sync_screen.dart:124` reads). `DbSafety.protect` copies, integrity-checks and byte-compares the whole file on every arena open and keeps up to 10 copies.
**Evidence:** `grep syncOutbox` shows no delete; `_identicalExisting` reads full files (`db_safety.dart:364-367`).
**Impact:** Steady growth of DB and 10× backup storage; slower start-up integrity checks on low-end tablets over months.
**Recommended Fix:** Prune `applied` ops older than N days (keep `rejected` until resolved + retention); keep the backup cadence but consider skipping when unchanged by size+mtime.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Measure DB size after a simulated month of ops.

## [P3][FL-009] Cloud backups share one label per arena across users; restore is not reachable from the app
**Status:** VERIFIED
**Category:** Data safety
**Location:** `apps/mobile/lib/app/sync/cloud_root.dart:321-326`, `apps/mobile/lib/data/local/db_safety.dart:293-306,380-397`
**Problem:** Backups use `label: 'arena_ops_cloud_<arenaId>'` although the DB is per (arena, user); two people on one device prune each other's backups (keep 10 shared) and a manual restore by label can pick the wrong person's file. `DbSafety.restore` has no caller in `lib/` (restore is manual only, per RELEASE.md).
**Recommended Fix:** Include the user id in the label; document the manual cloud restore procedure.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Unit test on `listBackups`/`_prune` with two labels.

## [P3][FL-010] `_open` has no re-entrancy guard; subscriptions are overwritten without cancel
**Status:** NEEDS VERIFICATION (requires two triggers within one frame)
**Category:** Lifecycle
**Location:** `apps/mobile/lib/app/sync/cloud_root.dart:272-298,490-505`
**Problem:** `_open` / `_retry` can run concurrently (pick list tap + "Try again", or rapid double tap before the `opening` frame). A second run opens a second `AppDatabase` on the same file, a second engine and channel, and assigns `_statusSub`, `_dataSub`, `_db`, `_binding`, `_container` without cancelling/closing the first.
**Impact:** Two engines pushing the same outbox (idempotent on server, but duplicate traffic), Drift streams on one connection not seeing the other's writes, leaked DB handle.
**Recommended Fix:** Guard with an `_opening` future/flag; cancel existing subscriptions before reassigning.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Widget test invoking `onPick` twice synchronously.

## [P3][FL-011] Enum parsers throw on values unknown to this build (forward-compatibility of synced data)
**Status:** VERIFIED (current server and app value sets match)
**Category:** Robustness
**Location:** `apps/mobile/lib/domain/value/enums.dart:15,88,98,109,119,129,139,170,183,226,238,384,401`, `apps/mobile/lib/domain/entities/resource.dart:61`
**Problem:** `fromCode` uses `firstWhere` without `orElse`. If the server (admin web) introduces a new payment method, session status, rounding mode, etc., every Drift stream mapping such a row throws `StateError` on older floor apps (the sync applier stores the string without validation, so the failure appears in screens, e.g. Floor/Money).
**Recommended Fix:** Add `orElse` fallbacks (e.g. `PaymentMethod.other`) or reject unknown values in the applier with a visible "update the app" state.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Unit tests with an unknown code.

## [P3][FL-012] Cloud mode has no screen lock / staff switch on a shared counter device
**Status:** VERIFIED (design gap; `CLAUDE.md` lists the shared clock-in tablet as not built)
**Category:** Security / audit attribution
**Location:** `apps/mobile/lib/app/auth/auth_controller.dart:63-102`, `apps/mobile/lib/app/sync/cloud_root.dart:111-130`
**Problem:** In cloud mode the signed-in account stays signed in across launches with no PIN/idle lock (`CloudAuthController.signIn` returns `PinUnavailable`). On a shared counter tablet every action (`created_by`, `sync_ops.user_id`, refunds, voids) is attributed to whoever signed in last.
**Recommended Fix:** Confirm with owner that each staff member uses their own device; otherwise add an idle lock / quick-switch.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** Owner confirmation of device policy.

## [P3][FL-013] Floor screen rebuilds entirely every second
**Status:** VERIFIED
**Category:** Performance
**Location:** `apps/mobile/lib/features/floor/presentation/floor_screen.dart:85-260`, `apps/mobile/lib/features/floor/presentation/widgets/station_card.dart:87,146,175`
**Problem:** `FloorScreen.build` watches `nowProvider` (1 s tick) and rebuilds all maps, zones and cards in a non-lazy `ListView(children: …)`; each card also watches `nowProvider` and recomputes `liveBill` (full segment billing) per second.
**Impact:** Acceptable for ~20 stations; CPU/battery cost grows with station count on low-end tablets.
**Recommended Fix:** Move the `now` watch into the timer/bill sub-widgets only; compute `endingSoon` in a small dedicated widget.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** DevTools rebuild counts with 30 stations.

## [P3][FL-014] Lock-screen alarms show customer names publicly
**Status:** VERIFIED
**Category:** Privacy
**Location:** `apps/mobile/lib/app/notifications/session_reminders.dart:158-168`, `apps/mobile/lib/core/notifications/notification_service.dart:251`
**Problem:** Session alerts use `'$stationName ($customerName)'` and alarm-style alerts set `NotificationVisibility.public`, so customer names appear on a locked device screen.
**Recommended Fix:** Use station only on public visibility, or `private` with a redacted public version.
**Estimated Effort:** Small
**Production Blocker:** No

## [P3][FL-015] `USE_EXACT_ALARM` may be rejected by Google Play policy
**Status:** NEEDS VERIFICATION (depends on distribution channel)
**Category:** Release / store policy
**Location:** `apps/mobile/android/app/src/main/AndroidManifest.xml:5-9`
**Problem:** Play restricts `USE_EXACT_ALARM` to apps whose core function is an alarm clock or calendar; the app also declares `SCHEDULE_EXACT_ALARM`. Irrelevant if APKs are side-loaded (RELEASE.md builds split APKs).
**Recommended Fix:** If publishing on Play, drop `USE_EXACT_ALARM` and rely on `SCHEDULE_EXACT_ALARM` + the existing permission request path.
**Estimated Effort:** Small
**Production Blocker:** No (Yes only for Play distribution)

## [P3][FL-016] macOS release entitlements lack `network.client`
**Status:** VERIFIED
**Category:** Platform config
**Location:** `apps/mobile/macos/Runner/Release.entitlements`, `apps/mobile/macos/Runner/DebugProfile.entitlements`
**Problem:** Sandboxed macOS builds have no `com.apple.security.network.client`, so cloud mode cannot reach Supabase. macOS is not a documented release target; flag only so nobody ships it as-is.
**Recommended Fix:** Add `network.client` if macOS is ever shipped, or remove the target.
**Estimated Effort:** Small
**Production Blocker:** No

## [P3][FL-017] Online-only helpers do not catch `Error`s from response parsing
**Status:** VERIFIED
**Category:** Error handling
**Location:** `apps/mobile/lib/data/remote/online_calls.dart:26-39,53-70`, `apps/mobile/lib/data/remote/supabase_attendance_repository.dart:156-199`
**Problem:** `onlineRead` catches `Exception` only, and `pushNow` uses `results.single`; a malformed/unexpected server shape (`TypeError` from `as` casts, `StateError` from `.single`) escapes the `Result` contract as an uncaught error instead of a `Failure` with a stable code.
**Recommended Fix:** Catch `Object` at these boundaries and map to a `parse_failed`/`server_error` `Failure`, reporting to telemetry.
**Estimated Effort:** Small
**Production Blocker:** No

---

## Controls verified as sound

- **Release gate enforced in code.** `main.dart:35-47` evaluates `problemFor(releaseBuild: kReleaseMode)` before anything opens; `app_config.dart:144-172` refuses local mode, unknown `AO_BACKEND`, missing URL/key, `sb_secret_`/`service_role` keys (JWT role decoded without echoing the key) and dev/non-https hosts. Android Gradle refuses release tasks without `AO_BACKEND=supabase` or `key.properties` (`android/app/build.gradle.kts:83-106`); never signs with the debug key. Demo seed refuses in release (`seed_data.dart:21,30`).
- **Committed defines contain only local-stack keys.** Tracked: `dart_define.example.json` (placeholders), `dart_define.local.json`, `dart_define.local-android.json` (`sb_publishable_…`, `http://127.0.0.1`/`10.0.2.2`, would be refused by a release build). `dart_define.dev.json` is untracked (git-ignored) and its key decodes to `role: anon`, `iss: supabase-demo`. No `dart_define.prod.json` in the repo. Note: the two local files are tracked despite the `dart_define*.json` ignore rule (force-added); harmless.
- **Session token storage.** Supabase session persisted via `flutter_secure_storage` (Keychain / Keystore) keyed per backend host (`secure_session_storage.dart:13-65`); keystore failures degrade to "sign in again" without deleting; legacy shared key removed. No token, password or PIN is logged (`debugPrint` sweep: only `runtimeType`, codes or generic errors).
- **No cross-login pushes.** One Drift file per (arena, user) (`staff_access.dart:46-47`); recorder actor fixed at open (`cloud_root.dart:368-373`); transport refuses to call without a session (`sync_transport.dart:155-157`); post-open check that the session user is unchanged (`cloud_root.dart:512-514`); voluntary sign-out warns about unsent ops (`more_screen.dart:48-71`, `sync_screen.dart:62-72`); alerts cancelled on sign-out/switch (`cloud_root.dart:614-632`).
- **Startup / auth restoration.** `checkStoredSession` + `classifyStartupFailure` distinguish offline (open last arena from disk) vs refused (sign in) vs server error; never call as `anon` (`stored_session.dart:29-98`, `cloud_root.dart:113-254`).
- **Outbox semantics.** Op + local change in one transaction (`sync_recorder.dart:40-60`, nudge scheduled from the root zone); ordered pushes; server idempotency by `op_id` with advisory lock (`sync_push.sql:38-47`); per-op refusals don't block later ops; `retry` stops the batch to preserve order; pull/rollback only with an empty outbox and re-checked inside the transaction (`sync_engine.dart:570-573`); offline errors filtered from Sentry (`sentry_setup.dart:44-50`).
- **Lifecycle.** Pause flushes once then stops polling; resume restarts engine + realtime and rebuilds alerts (`cloud_root.dart:154-191`); teardown is ordered with timeouts (`cloud_root.dart:536-581`); realtime start/stop is idempotent and resubscribes with catch-up (`realtime_sync.dart:95-144`); realtime events never apply payloads (nudge only), DELETE events deliberately not subscribed.
- **Clock discipline.** No `DateTime.now()` outside `core/clock` except telemetry breadcrumbs, backup filenames and the debug demo seed; all repositories receive `clockProvider` (`data_providers.dart:42-92`); cloud mode overrides it with a server-offset `OffsetClock`. Timers derive from stored timestamps (`SessionTimer(startedAt, scheduledEndAt)` in widgets).
- **DbSafety.** Backup taken in an isolate before open, WAL/SHM copied and checkpointed into the copy, `integrity_check` + row counts, refuse to open when a migration is pending without a verified backup, prune protects newest per schema version (`db_safety.dart:124-248,380-397`); used in both local (`main.dart:68-80`) and cloud (`cloud_root.dart:320-341`) paths.
- **Migration chain.** Contiguous steps 10–16, additive (the v10 step hashes PINs and drops plaintext, with VACUUM after commit); `_createIndexes` re-run idempotently; one-open-segment / one-open-allocation unique indexes; `ix_outbox_status` index exists (`database.dart:659-717,734-826`).
- **Local PINs (debug/local mode only).** PBKDF2-HMAC-SHA256, 60k iterations, 16-byte random salt, constant-time compare, lockout ladder that does not reset on expiry, verify in one transaction (`pin_credential.dart`, `local_user_repository.dart:136-196`). Not used in cloud mode.
- **Platform.** Release Android manifest has no `usesCleartextTraffic` (only the debug manifest, documented); receivers `exported=false`; only the launcher activity exported. iOS `Info.plist` has no ATS exceptions and no `UIFileSharingEnabled`. Replay masks all text/images and pauses on credential screens (`replay_privacy.dart`, used in login, cloud sign-in, change password, staff PIN editor); `sendDefaultPii = false`.
- **Static analysis.** `flutter analyze`: no issues.

## Not reviewed

- Pricing / billing correctness (`domain/pricing`, `segment_billing`, `group_billing`, extension planner) and staff-module rules (attendance/leave semantics) — other auditors.
- Server SQL beyond `sync_push` / `sync_pull` headers (RLS, `op_*` bodies, realtime policies).
- `features/` screens individually (only floor, station card, take-payment, sync, more sign-out paths sampled); `group_session_actions.dart` / `local_group_session_repository.dart` read only at catch sites.
- Owner screens still present in the app (Today, Money, Reports, Settings/catalog editing) — out of SLC scope per `CLAUDE.md`.
- Runtime behaviour (no tests, builds or device runs); Drift's transactional behaviour of a failing migration step on device; Supabase hosted `statement_timeout` values.
- iOS Xcode project settings (signing, bitcode, capabilities), Android ProGuard/R8 output.

## Code-quality notes for 07

- Largest hand-written files: `apps/mobile/lib/app/controllers/group_session_actions.dart` (1152), `apps/mobile/lib/data/local/local_group_session_repository.dart` (1119), `apps/mobile/lib/app/sync/cloud_root.dart` (957; mixes lifecycle orchestration with three screen widgets), `apps/mobile/lib/data/local/local_session_repository.dart` (939), `apps/mobile/lib/data/local/database.dart` (881).
- `apps/mobile/lib/features/sync/presentation/sync_screen.dart:122-128` builds a Drift query in the feature layer (`_outboxProvider`) and `jsonDecode`s payloads inside `build` (`:139`); move behind the engine/repository.
- `apps/mobile/lib/features/floor/presentation/sheets/take_payment_sheet.dart:217-232` does money math (remaining balance / change) in the widget, and treats a not-yet-loaded payments stream as "nothing collected" (`?? const <Payment>[]`) → can cap at the full bill instead of the balance; move into `SessionActions` (flag to pricing/money auditor).
- `take_payment_sheet.dart:214` falls back to `active.session.startedAt` when `nowProvider` has no value; elsewhere the fallback is `clockProvider.now()` — inconsistent.
- `apps/mobile/lib/data/sync/sync_engine.dart:370` and `:340` put raw exception text into user-visible status (`'Sync failed: $e'`, `'Server unreachable ($e)'`) contrary to the "UI never invents/raw error copy" rule; map to `Failure` copy.
- `apps/mobile/lib/data/sync/sync_engine.dart:358-373`: if the DB is closed mid-pass (sign-out timeout), `_counts` inside the catch throws and the `unawaited(syncNow())` future errors unhandled — wrap the emit in try/catch.
- `apps/mobile/lib/data/local/local_controller_allocation_repository.dart:218-235` checks "station busy" outside the write transaction (TOCTOU; server re-validates).
- `apps/mobile/lib/data/sync/sync_transport.dart:185-190` and `apps/mobile/lib/app/sync/staff_access.dart:200-204` detect `ClientException` by `toString().contains(...)` — brittle.
- `apps/mobile/lib/core/monitoring/app_telemetry.dart:185-187` uses `dynamic` for throwable/stackTrace (only `dynamic` in hand-written code).
- `apps/mobile/lib/main.dart:90-94`: `LocalSeed.applyIfEmpty(...).timeout(4s)` does not cancel the seed — UI can start while seeding continues (debug/local only).
- `apps/mobile/lib/domain/auth/pin_credential.dart`: 60k-iteration PBKDF2 runs synchronously on the UI isolate inside a transaction (local mode only) — jank on low-end tablets.
- `apps/mobile/lib/data/sync/realtime_sync.dart:53-89`: 29 tables × 2 Postgres-Changes bindings per device; consider broadcast-only nudges at scale.
- Release commands in `docs/RELEASE.md` omit `--obfuscate --split-debug-info` (and Sentry symbol upload for obfuscated builds).
- `apps/mobile/analysis_options.yaml` uses only `flutter_lints` defaults (no `unawaited_futures`, `avoid_dynamic_calls`, `cast_nullable_to_non_nullable` etc.).
- Report exports accumulate in app Documents (`apps/mobile/lib/features/reports/application/report_export.dart:51-54`) and are never cleaned up.
