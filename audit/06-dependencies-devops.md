# 06 — Dependencies, supply chain, configuration, CI/CD, release & operations

Auditor area: DEP. Branch `feature/venue-generalization` @ `24a4bdd`, working tree clean. Audit date 2026-10-16.
Read-only: no installs, upgrades or file changes apart from this report. Key values are never reproduced here: they are redacted, or described only by their decoded `role` claim.

## 1. Scope and method

Read: `CLAUDE.md`, `README.md`, `docs/RELEASE.md`, `docs/DEPLOY_SUPABASE.md`, `supabase/README.md` (partial), `supabase/config.toml`, `apps/admin/{package.json,angular.json,pnpm-workspace.yaml,.mcp.json,src/index.html,src/environments/*,src/app/app.config.ts,src/app/core/supabase/supabase.ts}`, `apps/mobile/{pubspec.yaml,pubspec.lock,dart_define*.json,android/**,ios/Runner/Info.plist,ios/Runner.xcodeproj/project.pbxproj,lib/main.dart,lib/core/config/app_config.dart,lib/core/monitoring/*}`, `tool/*.sh`, `.gitignore` (root, android, ios), `.env.example`, `.mcp.json`, `skills-lock.json`.

Commands run (all read-only):

| Command | Result |
|---|---|
| `npm audit --omit=dev --json` (apps/admin) | First attempt: 403 (sandbox blocked the registry). Rerun with registry access: **0 vulnerabilities** (info/low/moderate/high/critical all 0) |
| `npm audit --json` (apps/admin, incl. dev) | **0 vulnerabilities** |
| `flutter pub outdated --no-dependency-overrides` (apps/mobile) | Ran outside the sandbox (the Flutter SDK writes its own engine stamp into `~/SDK/flutter/bin/cache`). `git status` was unchanged afterwards. Table summarised in §2. `pub outdated` does not report advisories |
| Lockfile comparison (python over `package-lock.json` / `grep` over `pnpm-lock.yaml`) | The key packages resolve to the same versions in both lockfiles (see DEP-010) |
| `package-lock.json` integrity / origins | 467 entries, **all with `integrity`**, all from `registry.npmjs.org`. Packages with install scripts: `@parcel/watcher`, `esbuild`, `fsevents`, `lmdb`, `msgpackr-extract` (all build tooling) |
| `pubspec.lock` sources | 187 `hosted` (pub.dev, all with sha256) + 5 `sdk`; **no git or path dependencies**; no `dependency_overrides` |
| `git ls-files` / `git ls-tree origin/main, origin/develop` for CI files | **No** `.github/`, GitLab, CircleCI, Codemagic, Bitrise, fastlane, Dependabot, Renovate or pre-commit/husky config on any of those branches |
| Full history blob scan (3,655 objects, 63 commits): `sb_secret_*`, JWTs (decoded `role` only), private-key blocks, signing-password lines, Sentry DSN/tokens | `sb_secret_*` only in two test files, as obvious fakes (`sb_secret_example…`, `sb_secret_SHOULD…`). One JWT in history: `apps/admin/src/environments/environment.production.ts`, **role=anon** (public key, hosted dev project). "Signing password" hits are template text in `build.gradle.kts` / `RELEASE.md`. **No service_role JWT, no private key, no Sentry DSN/token in history** |
| `git log --all --diff-filter=A --name-only \| grep key/secret/env/jks…` | Paths only: `.env.example`, `apps/admin/src/environments/environment{,.development,.production}.ts`, `apps/admin/src/integration/it-env.ts`, `apps/mobile/dart_define.local{,-android}.json`, `dart_define.example.json`, sentry setup and test files, `_pr_*key*.sql`. No keystore, `.jks`, `.p12`, `.pem` or `key.properties` was ever added |
| `git tag` | **No tags** |

Not run: `supabase --version` (its output was mangled in the sandbox), anything hosted (`supabase … --linked`), builds, tests, `verify_all.sh`.

## 2. Dependency inventory (direct dependencies)

### Admin web (`apps/admin`, npm; lockfile v3)

| Package | Spec | Locked | Notes |
|---|---|---|---|
| @angular/core, common, compiler, forms, platform-browser, router | ^22.1.0 | 22.2.2 | |
| @angular/cdk, @angular/material | ^22.2.2 | 22.2.2 | |
| @supabase/supabase-js (+ auth/postgrest/realtime-js) | ^2.117.3 | 2.117.3 | |
| leaflet | 1.9.4 (exact) | 1.9.4 | used by `shared/map/geo-map.ts` |
| rxjs | ~7.8.0 | 7.8.2 | |
| tslib | ^2.3.0 | 2.8.1 | |
| dev: @angular/build, @angular/cli, compiler-cli | ^22.1.x | 22.2.2 | |
| dev: typescript | ~6.0.2 | 6.0.3 | |
| dev: vitest / vite / jsdom | ^4.0.8 / – / ^28 | 4.1.11 / 8.3.0 / 28.1.0 | |
| dev: tailwindcss, @tailwindcss/postcss, postcss | ^4.1.12 / ^8.5.3 | 4.3.3 / 8.5.30 | |
| dev: prettier, @types/leaflet | ^3.8.1 / 1.9.22 | | |

`npm audit`: 0 known vulnerabilities (prod and dev).

### Floor app (`apps/mobile`, Dart ^3.13.5, Flutter ≥3.47.0)

| Package | Spec | Locked | Latest (pub outdated) |
|---|---|---|---|
| supabase_flutter | ^2.18.2 | 2.18.2 | 2.18.3 |
| sentry_flutter (+ dev sentry_dart_plugin) | ^10.0.0 (^3.4.0) | 10.0.0 | 10.1.0 |
| drift / drift_flutter / sqlite3 | ^2.35.1 / ^0.3.1 / ^3.5.2 | 2.35.1 / – / 3.5.2 | 2.35.2 / – / 3.7.1 |
| flutter_riverpod | ^3.4.3 | current | – |
| go_router | ^18.0.2 | 18.0.2 | 18.1.0 |
| flutter_secure_storage | ^11.2.0 | current | – |
| flutter_local_notifications | ^19.0.0 | 19.5.0 | **22.3.2** (3 majors behind) |
| timezone | ^0.10.0 | 0.10.1 | 0.11.2 |
| geolocator, flutter_map, latlong2 | ^14.1.1, ^8.3.2, ^0.10.1 | current | – |
| excel (pulls archive 3.6.1; latest is 4.5.2) | ^4.0.6 | current | – |
| share_plus, path_provider, url_launcher, uuid, intl, crypto, collection, meta, freezed_annotation, json_annotation | | current | – |
| cupertino_icons | ^1.0.8 | 1.0.9 | 2.0.0 |
| dev: build_runner, freezed, json_serializable, drift_dev, flutter_lints, http | | build_runner 2.16.1 | 2.17.1 |

`pub outdated`: 23 packages can be upgraded within the lock, and 6 are held back by pubspec constraints. No advisory data was available and none was checked against an advisory database (see "Needs verification").

### Native and toolchain

| Item | Value |
|---|---|
| Android Gradle Plugin / Kotlin plugin | 9.1.0 / 2.4.0 (`settings.gradle.kts`) |
| Gradle wrapper | 9.3.1-all, **no `distributionSha256Sum`**; `gradlew` and `gradle-wrapper.jar` are git-ignored (Flutter regenerates them) |
| minSdk / targetSdk / compileSdk | `max(flutter.minSdkVersion, 26)` / `flutter.targetSdkVersion` / `flutter.compileSdkVersion` |
| Java/Kotlin target | 17; core library desugaring `desugar_jdk_libs:2.1.4` |
| R8 / ProGuard | No explicit `isMinifyEnabled` and no `proguard-rules.pro`, so the Flutter plugin defaults apply |
| iOS | Deployment target 15.0, bundle id `in.rorrim.arenaOps`, SwiftPM (`Package.resolved` committed, no Podfile), automatic signing, no team set |
| App version | `pubspec.yaml` `1.0.0+1`; admin `package.json` `0.0.0` |
| Pinned toolchain | No `.nvmrc`, `engines`, FVM, `.tool-versions` or pinned Supabase CLI. Local machine: node v24.21.0, npm 11.19.0. `.metadata` records the Flutter revision only |

## 3. Findings

## [P1][DEP-001] Migration history was squashed; the hosted project and the deployment runbook still expect the old history
**Status:** VERIFIED (repo); hosted state NEEDS VERIFICATION
**Category:** Release / database operations
**Location:** `supabase/migrations/` (11 files, first `20261015054055_declarative_sync.sql`); `docs/DEPLOY_SUPABASE.md:43,107-112,129-191`; `CLAUDE.md:43`; `supabase/README.md:20`
**Problem:** The hand-written `0001`–`0016` and every generated migration up to `20261014203120` were deleted. Commits `5d9e137` (2026-10-14) and `9065613` (2026-10-15) did this, and `9065613` added a single 11,817-line baseline, `20261015054055_declarative_sync.sql`. That baseline creates everything from scratch (`create schema "private"`, 39 `create table`). The docs still say `0001`–`0016` exist: CLAUDE.md calls them the "hand-written baseline", and DEPLOY_SUPABASE says `db push --dry-run` "must list exactly `0001` … `0016`". DEPLOY_SUPABASE §4a also records that the hosted dev project `ouxvtvlzhxddmqirmnxo` has 36 old migration versions applied.
**Evidence:** `ls supabase/migrations` lists 11 files. `git log --diff-filter=D -- supabase/migrations` shows the two commits above. Line 1 of the baseline sits under `set local check_function_bodies = off;` followed by `create schema "private"`.
**Impact:** The documented go-live procedure cannot be followed as written. On the existing hosted project, `supabase db push` will report that remote versions are missing locally, or it will try to apply a full-create baseline that fails on existing objects. The obvious ways to "fix" that are `migration repair` plus a hand-made diff, or `db reset --linked`. Neither is guided, and the reset destroys the data. A fresh production project does work from the baseline, but the runbook's `--dry-run` check ("must list exactly 0001…") then fails, so the operator has no reliable acceptance check.
**Failure Scenario:** The owner prepares go-live by following DEPLOY_SUPABASE §4a against hosted dev (where two phones may already have test or real takings). The push errors out. Under time pressure they run `db reset --linked` or repair the versions by hand. Data is lost, or the schema ends up different from `schemas/`.
**Recommended Fix:** Decide and document the path. Either (a) treat hosted dev as disposable and recreate it from the new baseline, or (b) write a documented `supabase migration repair` sequence plus a verified diff showing hosted equals the baseline's end state. Rewrite DEPLOY_SUPABASE §1/§4/§4a and the CLAUDE.md/`supabase/README.md` lines to match the 11-file history. Add a rule that migration history is never squashed again once a remote has applied it.
**Estimated Effort:** Medium
**Production Blocker:** Yes
**Suggested Verification:** Run `supabase migration list --linked` (read-only) and compare it with the local list. On a scratch hosted project, rehearse `db push` from the baseline.

## [P1][DEP-002] No backup / PITR policy or restore test for the hosted database (the system of record for money)
**Status:** NEEDS VERIFICATION
**Category:** Operations / data durability
**Location:** `docs/DEPLOY_SUPABASE.md:331`; `docs/RELEASE.md:12-58` (device backups only)
**Problem:** The only backup design covers the device SQLite file (`DbSafety`). For the server, the runbook says "No backups/PITR policy has been chosen for the hosted project (plan-dependent)". No restore procedure exists, no restore has been rehearsed, and no export (`pg_dump`) routine is described. In cloud mode the server holds the merged, append-only money ledger, `audit_log` and salary runs for every device.
**Evidence:** `grep -i "pitr|pg_dump|restore" docs` finds only the device restore and the line above.
**Impact:** A bad migration (see DEP-008), an operator mistake (`db reset --linked`) or a project incident could lose sales, payments, voids and payroll with no recovery point. Device copies are partial and are not a supported restore source for the server.
**Failure Scenario:** A generated migration drops or rewrites a column on live data, or the project is paused or deleted on the Free plan. There is nothing to restore from.
**Recommended Fix:** Before production, choose a plan that includes daily backups (and PITR if the RPO needs it). Add a scheduled logical export (`supabase db dump` of data and schema to off-site storage), document the RPO/RTO, and rehearse one restore into a scratch project. Take a manual dump before every `db push`.
**Estimated Effort:** Small–Medium
**Production Blocker:** Yes
**Suggested Verification:** In the dashboard, check Database → Backups (and the plan) for the project that will be production. Time one restore into a new project.

## [P2][DEP-003] No CI. Nothing gates a merge or a release build, and HEAD already has known failing suites
**Status:** VERIFIED
**Category:** CI/CD
**Location:** repo root (no `.github/`, checked on the local tree and on `origin/main` and `origin/develop`); `tool/verify_all.sh:1-91`; `CLAUDE.md:116-117`
**Problem:** All verification is manual (`tool/verify_all.sh`). No hosted pipeline runs analyze, tests, the admin production build, pgTAP, the advisors or the declarative drift check. Dependabot/Renovate are not set up either. CLAUDE.md already lists failures on HEAD: the Drift migration test fails with `duplicate column name: overtime_grace_minutes`, a possible on-device upgrade failure, and 7 admin specs fail. `verify_all.sh` also builds the admin only in the **development** configuration (step 4), so the production build (`fileReplacements`, the 1 MB budget error) is never checked.
**Evidence:** `git ls-files`/`git ls-tree` return no CI files. `verify_all.sh:72` runs `ng build --configuration development`.
**Impact:** A regression in pricing parity, RLS or the Drift migration chain can reach a release build without anyone noticing. The release process depends on one person remembering to run the script with `--with-it --with-psql`.
**Failure Scenario:** A release APK ships with the known Drift v16 step failure. On upgrade, devices hit "Data kept safe — app not started", or fall into the rebuild path.
**Recommended Fix:** Add a minimal GitHub Actions workflow: `flutter analyze` + `flutter test`, `npm ci && npm test && npm run build` (production config), and a job that starts the Supabase CLI and runs `supabase test db` plus the advisors plus `db schema declarative sync --no-apply` (asserting "No schema changes found"). Protect `main`. Enable Dependabot for npm, pub, gradle and github-actions.
**Estimated Effort:** Medium
**Production Blocker:** No (but fix the known failing Drift migration test before release, as CLAUDE.md says)
**Suggested Verification:** Run `bash tool/verify_all.sh --with-it --with-psql` locally once, plus `npm run build` (production) in `apps/admin`.

## [P2][DEP-004] Admin web hosting is undefined: no security headers, CSP, HSTS, SPA fallback or caching config
**Status:** NEEDS VERIFICATION
**Category:** Configuration / deployment
**Location:** `apps/admin/angular.json:24-58`; `apps/admin/src/index.html:9-17`; `docs/DEPLOY_SUPABASE.md:285-290`
**Problem:** The only deployment instruction is "Serve it at the https URL you set as Site URL". The repo contains no hosting config at all: no `_headers`, `vercel.json`, `netlify.toml`, `firebase.json` or nginx config. Per §4a the dashboard currently runs locally against hosted. Nothing therefore sets a CSP, HSTS, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy` or `Permissions-Policy`, the deep-link SPA fallback that `/accept-invite` and `/reset-password` need, or cache rules (immutable hashed bundles, no-cache `index.html`). The page also loads Google Fonts and Material Symbols from `fonts.googleapis.com` at runtime, and OSM tiles from `{s}.tile.openstreetmap.org` (`shared/map/geo-map.ts:53`). Any CSP must allow these.
**Evidence:** `find` / `git ls-files` turned up no hosting config. `index.html` has no CSP meta. The production config does not enable source maps (Angular's default is off, which is good).
**Impact:** This is the owner console for money, voids, payroll and staff permissions, with the Supabase session in browser storage. Without CSP and frame protection, any XSS or clickjacking has full owner reach. Without the SPA fallback, invitation and reset links return 404. Without cache rules, owners can run a stale bundle after a deploy.
**Failure Scenario:** The dashboard goes onto a static host with defaults. An invited staff member opens `/accept-invite?...` and gets the host's 404, so onboarding breaks. Or an old cached `index.html` keeps calling RPC shapes that a migration removed.
**Recommended Fix:** Choose the host and commit its config with: a strict CSP (`default-src 'self'`; `connect-src` the Supabase https and wss origin; fonts and OSM origins, or self-host the fonts); HSTS; `frame-ancestors 'none'`; `Referrer-Policy: strict-origin-when-cross-origin`; an SPA rewrite to `index.html`; and cache headers. Document it in DEPLOY_SUPABASE §6.
**Estimated Effort:** Small–Medium
**Production Blocker:** Yes for the admin go-live (the SPA fallback is functional; the headers are hardening)
**Suggested Verification:** After deploying, run `curl -I` against `/`, `/accept-invite` and a hashed bundle, and check the headers in securityheaders.com or Mozilla Observatory.

## [P2][DEP-005] Production observability: the release runbook ships without crash reporting; the admin web has none
**Status:** VERIFIED
**Category:** Monitoring / operations
**Location:** `docs/RELEASE.md:102-110`; `apps/mobile/lib/core/config/app_config.dart:179-198`; `apps/mobile/lib/core/monitoring/sentry_setup.dart:17-41`; `apps/mobile/pubspec.yaml:134-138`; `apps/admin/src/app/app.config.ts:8-11`
**Problem:**
(1) RELEASE.md describes `dart_define.prod.json` as holding only `AO_BACKEND`, the URL and the key. A release built from it gets an empty `AO_SENTRY_DSN`, which disables Sentry entirely, so crash, timer-anomaly and sync errors from the floor go nowhere.
(2) If a DSN is added but `AO_ENVIRONMENT` is left out, `environment` defaults to `'development'`. Production devices then report as development, with 100 % tracing and 100 % Session Replay of every session (`isProduction` is false).
(3) The `sentry:` upload block in the pubspec (debug symbols, source maps) needs a separate `dart run sentry_dart_plugin` step with `SENTRY_AUTH_TOKEN`. The runbook does not mention it, and builds are not made with `--split-debug-info`.
(4) No Sentry `release` is set, and the version never changes (DEP-009), so events cannot be tied to a build.
(5) The admin web has only `provideBrowserGlobalErrorListeners()` (console). There is no error reporting for owner-side failures such as voids, payroll or pushOps refusals.
No server-side structured logging or alerting is described beyond the Supabase dashboard logs.
**Evidence:** The quoted lines. `dart_define.example.json` does show `AO_SENTRY_DSN`/`AO_ENVIRONMENT`, but the runbook's prod file does not.
**Impact:** The first production incidents (sync refusals, timer anomalies, startup configuration errors) are invisible unless staff report them. If replay is misconfigured, staff screens are recorded at 100 % (text masked) and Sentry quota is used up fast.
**Failure Scenario:** A release build hits a migration or config problem on the counter tablet. Nobody sees it remotely, and the venue runs on paper until someone calls.
**Recommended Fix:** Add `AO_SENTRY_DSN` and `AO_ENVIRONMENT=production` to the documented `dart_define.prod.json`. Consider having `problemFor(releaseBuild: true)` refuse, or at least warn, when `AO_ENVIRONMENT` is not `production`. Set `options.release`/`dist` from the build. Document the symbol-upload step. Add a minimal admin `ErrorHandler` that reports to Sentry or another tracker, and set up Supabase log alerts for 5xx and `sync_push` refusal spikes.
**Estimated Effort:** Small
**Production Blocker:** No (but strongly recommended before the first venue)
**Suggested Verification:** Build a release with the prod defines and `AO_SENTRY_DEBUG=true` and confirm that an event arrives tagged `production`.

## [P2][DEP-006] Android Auto Backup is left on: the device database and secure-storage prefs go to staff members' personal Google backups
**Status:** LIKELY
**Category:** Configuration / data protection
**Location:** `apps/mobile/android/app/src/main/AndroidManifest.xml:17-21` (no `android:allowBackup`, `fullBackupContent` or `dataExtractionRules`); `apps/mobile/lib/app/sync/secure_session_storage.dart:19`
**Problem:** `android:allowBackup` defaults to `true`, so Android Auto Backup uploads app files (up to 25 MB) to the device owner's Google account. That includes the Drift databases (`arena_ops_cloud_<arena>_<user>.sqlite`: customers, payments, sessions), the `arena_ops-backups/` copies and the SharedPreferences that `flutter_secure_storage` uses. The README targets an Android phone that is the staff member's personal device. `FlutterSecureStorage()` uses default options, and the plugin's docs advise turning backup off or excluding its prefs, because a restored ciphertext cannot be decrypted on a new device (its Keystore key is not backed up).
**Evidence:** The manifest has no backup attributes. `FlutterSecureStorage()` is constructed with no options.
**Impact:** Arena customer and payment data leaves the venue's control, landing in personal cloud backups that persist after the person leaves the job. On restore, decryption errors at startup are likely.
**Failure Scenario:** A staff member who has left restores their phone. The old arena DB copy comes back on a device that no longer has access, and the secure-storage read throws on first launch.
**Recommended Fix:** Set `android:allowBackup="false"`, or add `dataExtractionRules` / `fullBackupContent` that exclude the database, backups and secure-storage prefs. The server is the backup in cloud mode.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Run `adb shell bmgr backupnow in.rorrim.arena_ops` on a test device, then inspect the backup, or check `adb shell dumpsys backup`.

## [P2][DEP-007] The committed admin production config points at the hosted DEV project; there is no prod/staging separation
**Status:** VERIFIED
**Category:** Environment separation / configuration
**Location:** `apps/admin/src/environments/environment.production.ts:1-19`; `docs/DEPLOY_SUPABASE.md:12-13,139-140,285-290`
**Problem:** The file's comment says "Left empty on purpose…", but lines 17–18 hold the hosted dev project's URL and its legacy anon JWT (decoded role `anon`, so a public key, not a secret). Every `npm run build`, the default production configuration, therefore produces a dashboard wired to the dev project. Only "local" and "hosted dev" environments exist. The runbook defers a production project to "later", and nothing describes a staging tier or how the prod values are injected without editing a tracked file.
**Evidence:** The decoded claim is `role=anon, iss=supabase`. The file was last changed in `5d9e137`.
**Impact:** The production dashboard and the dev database can be mixed up: real sales could be written into the dev project (which is reset and experimented on, see DEP-001), or a dev build could reach real data later. Committing hosted values also contradicts the documented process.
**Failure Scenario:** The first production deploy runs `npm run build` from `main`. The owner configures a venue in what turns out to be the dev project, which is later recreated to fix DEP-001.
**Recommended Fix:** Return the file to its empty state, and inject the URL and key at build time (CI secrets, or a git-ignored `environment.production.local.ts` via `fileReplacements`). Create separate dev and prod Supabase projects with separate keys. Keep the existing `configProblem` checks.
**Estimated Effort:** Small
**Production Blocker:** Yes (production must not point at the dev project)
**Suggested Verification:** Run `npm run build`, then `grep -o 'https://[a-z0-9]*\.supabase\.co' dist/**/*.js` (by the user), and confirm it is the prod ref.

## [P2][DEP-008] Forward-only migrations with no rollback plan; a generated migration drops a column without moving its data
**Status:** VERIFIED
**Category:** Database release / rollback
**Location:** `supabase/migrations/20261015114137_overtime_grace_per_type.sql:3-10`; `CLAUDE.md:45-52`
**Problem:** Nothing documents how to roll back a bad migration: no down scripts, no "restore from pre-push dump" procedure (see DEP-002), and no compatibility window for older floor-app builds. The overtime-grace migration drops `billing_policies.overtime_grace_minutes` and adds `activities.overtime_grace_minutes default 0` with no `update … set` carrying the old value over. On a database where grace minutes are set, they silently go back to 0. That changes billing (overtime is charged sooner). CLAUDE.md says "No destructive migrations without explicit approval", but the generator produced one and nothing caught it.
**Evidence:** Lines 3–10 of the migration. A `grep -i "drop "` over all migrations finds only this one.
**Impact:** A wrong billing configuration after deploy can only be fixed by hand, and a broken migration has no tested way back.
**Failure Scenario:** This migration is pushed to a project where an owner set a 10-minute grace. Every station type now has 0, and customers are billed overtime they were not billed before.
**Recommended Fix:** Before any push, review generated migrations for `drop`. Here, add a data-carrying step (expressed declaratively or approved explicitly) or confirm that no live project has non-default values. Document a rollback procedure: a pre-push dump plus a forward-fix migration, and the oldest app build the schema must still serve.
**Estimated Effort:** Small
**Production Blocker:** No (hosted has not received it yet, but it must be reviewed before it is pushed)
**Suggested Verification:** On the target project, run `select overtime_grace_minutes from billing_policies where overtime_grace_minutes <> 0;` read-only, before pushing.

## [P3][DEP-009] No release versioning: app 1.0.0+1, admin 0.0.0, no git tags
**Status:** VERIFIED
**Category:** Release process
**Location:** `apps/mobile/pubspec.yaml:19`; `apps/admin/package.json:3`; `git tag` (empty)
**Problem:** The mobile version and build number have never been bumped. The admin is `0.0.0`. No tags mark what was shipped. Android `versionCode` comes from `+1`. Play distribution needs an increasing code, and support needs to know which build a device runs.
**Impact:** Crash reports and support issues cannot be tied to a commit, and the floor-app version cannot be matched to a schema/server version.
**Recommended Fix:** Bump `version:` (or pass `--build-name/--build-number`) on every release, tag the commit, and show the version on the More screen and in Sentry `release`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Run `aapt dump badging` on the release APK.

## [P3][DEP-010] Two lockfiles for the admin (npm and pnpm); they are consistent now but nothing keeps them in step
**Status:** VERIFIED
**Category:** Supply chain
**Location:** `apps/admin/package-lock.json`, `apps/admin/pnpm-lock.yaml`, `apps/admin/pnpm-workspace.yaml`, `apps/admin/angular.json:4`
**Problem:** Both lockfiles are committed and were updated in the same commit (`6dd3d18`). Every key package resolves identically in both (Angular 22.2.2, supabase-js 2.117.3, vitest 4.1.11, typescript 6.0.3, tailwind 4.3.3, esbuild 0.28.2, leaflet 1.9.4). `angular.json` says `packageManager: npm`, `node_modules` was installed by npm (`.package-lock.json`, no `.pnpm`), and the docs use `npm`. So npm's lockfile is in practice the authoritative one. `pnpm-workspace.yaml` exists only to allow-list build scripts.
**Impact:** Sooner or later one lockfile changes without the other, and different machines or CI install different trees.
**Recommended Fix:** Keep `package-lock.json`. Delete `pnpm-lock.yaml` and `pnpm-workspace.yaml`, or switch fully to pnpm. Use `npm ci` in CI.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `npm ci` in a clean clone.

## [P3][DEP-011] Toolchain versions are not pinned (Node, Flutter, Supabase CLI, Gradle checksum)
**Status:** VERIFIED
**Category:** Build reproducibility / supply chain
**Location:** `apps/admin/package.json` (no `engines`); repo root (no `.nvmrc`/FVM/`.tool-versions`); `apps/mobile/android/gradle/wrapper/gradle-wrapper.properties:5`
**Problem:** Node, the Flutter SDK and the Supabase CLI are whatever is on the developer's machine. The CLI version matters because migrations are generated by `pg-delta` (`[experimental.pgdelta]`), and output can differ between CLI versions. The Gradle wrapper has no `distributionSha256Sum`. RELEASE.md records an NDK that was installed by hand.
**Impact:** Builds and generated migrations are not reproducible across machines, and a tampered Gradle distribution would not be detected.
**Recommended Fix:** Add `.nvmrc`/`engines`, `.fvmrc` (or record the Flutter version in RELEASE.md), the Supabase CLI version in `supabase/README.md`/CI, and `distributionSha256Sum`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Rebuild in a clean environment.

## [P3][DEP-012] Mobile dependencies lag behind (one plugin three majors behind); advisories not checked
**Status:** VERIFIED (versions) / NEEDS VERIFICATION (advisories)
**Category:** Dependencies
**Location:** `apps/mobile/pubspec.yaml:31-68`, `pubspec.lock`
**Problem:** `flutter_local_notifications` is at 19.5.0 (latest 22.3.2) and `timezone` at 0.10.1 (latest 0.11.2). Patch updates are available for `supabase_flutter`, `sentry_flutter`, `drift`, `sqlite3` and `go_router`. `excel` pins `archive` 3.6.1 (4.x is current). No Dart advisory database was consulted, so **no confirmed vulnerable version** is reported. The admin has none (`npm audit` is clean).
**Impact:** Upgrading later will be harder, and fixes to OS integration (Android 15/16 alarm and notification behaviour) are missed.
**Recommended Fix:** Schedule a dependency refresh with the regression suite, and add Dependabot `pub` updates (DEP-003).
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** `flutter pub outdated`, then `flutter test`, then the Drift migration tests.

## [P3][DEP-013] Local `config.toml` auth settings differ from the hosted requirements; hosted auth is configured only by hand
**Status:** NEEDS VERIFICATION
**Category:** Configuration
**Location:** `supabase/config.toml:151-156` (`site_url = http://127.0.0.1:3000`, localhost redirects), `:238` (`secure_password_change = false`), `:320,325` (MFA TOTP off); `docs/DEPLOY_SUPABASE.md:73-93`
**Problem:** `config.toml` is the local stack's config, and the runbook says the hosted values are set in the dashboard. Those are: Site URL = the dashboard's https URL, the `/accept-invite` and `/reset-password` redirects, Confirm email ON, Secure password change ON, leaked-password protection, custom SMTP, Realtime public access OFF, and CAPTCHA later. §4a records several of them as still to do on hosted dev (redirect URLs, SMTP, leaked-password protection). Running `supabase config push` while linked would overwrite hosted auth with the local values (a localhost Site URL, secure password change off). Owner accounts can void, run payroll and change permissions with no MFA available.
**Impact:** Invitation and reset links break, e-mails do not arrive (the built-in SMTP sends only to team members), and the hardening that was assumed is missing.
**Recommended Fix:** Before go-live, produce a short "hosted auth settings" checklist with the observed values. Never run `config push` (or maintain a `[remotes.<env>]` section with the prod values). Consider TOTP MFA for owners.
**Estimated Effort:** Small
**Production Blocker:** No (the SMTP and redirect items are functional blockers for invitations; see "Needs verification")
**Suggested Verification:** Compare each dashboard setting with DEPLOY_SUPABASE §3, and check `supabase db advisors --linked` for `auth_leaked_password_protection`.

## [P3][DEP-014] Developer-tooling supply chain: Angular CLI telemetry is on and an MCP server runs an unpinned `npx -y`
**Status:** VERIFIED
**Category:** Supply chain (dev only)
**Location:** `apps/admin/angular.json:3-6` (`"analytics": "3ebd4fa9-…"`); `apps/admin/.mcp.json` (`npx -y @angular/cli mcp`); `skills-lock.json`, `.agents/`
**Problem:** The committed `angular.json` opts every developer into Angular CLI usage analytics. `verify_all.sh` sets `NG_CLI_ANALYTICS=false`, but `npm run dev`/`build` do not. `apps/admin/.mcp.json` fetches and runs the latest `@angular/cli` from the registry each time, instead of the locked local copy that the root `.mcp.json` uses (`npx --no-install`). Agent skills are pinned by content hash in `skills-lock.json`, which is good.
**Impact:** Small. The first sends telemetry; the second runs unreviewed registry code on developer machines.
**Recommended Fix:** Set `"analytics": false`. Point `apps/admin/.mcp.json` at `npx --no-install ng mcp`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Review both files.

## [P3][DEP-015] Store and distribution readiness of the native builds has gaps
**Status:** NEEDS VERIFICATION
**Category:** Release / native configuration
**Location:** `apps/mobile/android/app/src/main/AndroidManifest.xml:6-7`; `apps/mobile/android/app/build.gradle.kts:36-37,62-70`; `apps/mobile/ios/Runner/` (no `PrivacyInfo.xcprivacy`); `docs/RELEASE.md:181-186`
**Problem:**
(a) The manifest requests both `USE_EXACT_ALARM` and `SCHEDULE_EXACT_ALARM`. Google Play limits `USE_EXACT_ALARM` to alarm and calendar apps, so a Play submission may be rejected. Sideloading over `adb`, as RELEASE.md does today, is unaffected.
(b) R8 shrinking uses Flutter's defaults with no app keep rules. Whether scheduled notifications (flutter_local_notifications' serialized payloads) survive shrinking in a release build has not been documented as tested.
(c) iOS has no app-level privacy manifest, and no `DEVELOPMENT_TEAM` is set. Signing is pending on both platforms (RELEASE.md §4: "the remaining release blocker").
(d) The `TODO: Specify your own unique Application ID` comment remains, although the ID is set.
(e) The keystore lives only on one Mac (`~/arena_ops-upload.jks`) with no documented backup. Losing it makes future updates impossible.
**Impact:** Submission delays. Possible silent loss of booking reminders in release builds. Permanent inability to ship updates if the keystore is lost.
**Recommended Fix:** Pick the distribution channel. Drop `USE_EXACT_ALARM` if it goes through Play. Test a reminder in a release APK. Add `PrivacyInfo.xcprivacy`. Store the upload keystore and its passwords in the password manager with an off-machine backup, and use Play App Signing.
**Estimated Effort:** Small–Medium
**Production Blocker:** Signing is (already known); the rest are not
**Suggested Verification:** On a release APK, schedule a reminder, reboot, and confirm it fires.

## 4. Controls verified as sound

- **No secrets in the repo or its history.** The full blob scan found no `service_role` JWT, no real `sb_secret_*` (only test fakes), no private keys, keystores, `key.properties`, Sentry DSNs or tokens. The only JWT is a role=`anon` key (DEP-007 covers where it points).
- **`.gitignore` is thorough.** It covers `dart_define*.json` (with explicit allow-lists for `.example`, `.local`, `.local-android`), `.env*`, keystores and certificates, `key.properties`, `google-services.json`, `supabase/.temp`, `.sentryclirc`/`sentry.properties`, `*.sqlite*` and backups. `git check-ignore` confirms the untracked `apps/mobile/dart_define.dev.json` (local URL) is ignored.
- **Committed config files hold only local or example values.** `.env.example` and `dart_define.example.json` are placeholders. `dart_define.local{,-android}.json` and `apps/admin/src/environments/environment.ts` hold the local stack's URL (127.0.0.1 / 10.0.2.2) and its `sb_publishable_` key.
- **Release backend gate (mobile).** `AppConfig.problemFor` (`app_config.dart:144-172`) refuses local mode, an unknown backend, a missing URL or key, `sb_secret_`/`service_role` keys and development hosts in release builds. Gradle (`build.gradle.kts:85-106`) refuses release `assemble`/`bundle`/`package` tasks without `AO_BACKEND=supabase` or a complete `key.properties`, and never signs a release with the debug key. Signing values are read only from the git-ignored `key.properties`.
- **Release backend gate (admin).** `configProblem` (`core/supabase/supabase.ts:26-79`) refuses non-https or local URLs in production and secret or `service_role` keys, and shows "Setup needed".
- **Cleartext HTTP only in the debug manifest** (`src/debug/AndroidManifest.xml`). The release manifest has `INTERNET` and https-only defaults. iOS has no ATS exceptions. The location permission strings are present and scoped to "when in use".
- **Local-only tooling.** `tool/sync_it.sh:38-48` refuses any non-local `API_URL`, reads the local service-role key from `supabase status` into a non-exported variable, and never prints it. `pricing_parity.sh` and `verify_all.sh` talk only to the local container. No service-role key appears anywhere else.
- **Lockfile hygiene.** All 467 npm entries have `integrity` hashes and come from `registry.npmjs.org`. `npm audit` reports 0 issues (prod and dev). The pubspec lock is all pub.dev-hosted with sha256, with no git or path dependencies and no `dependency_overrides`. Native build scripts are limited to the tooling packages allow-listed in `pnpm-workspace.yaml`.
- **Admin production build** does not emit source maps (no `sourceMap` in production, Angular default off), uses `outputHashing: all`, and has budgets.
- **Sentry privacy defaults** (when enabled): `sendDefaultPii=false`, all text and images masked in replay, offline sync errors filtered out.
- **Edge Functions** are disabled in `config.toml` (`[edge_runtime] enabled = false`), as designed.

## 5. Needs verification (outside the repo)

1. The hosted dev project's migration list (`supabase migration list --linked`) compared with the squashed local history (DEP-001), and whether hosted dev holds any data worth keeping.
2. The Supabase plan and the backup/PITR configuration of the future production project, and one restore rehearsal (DEP-002).
3. Hosted Auth settings: Site URL, redirect URLs, Confirm email, Secure password change, password policy, leaked-password protection, custom SMTP, both e-mail templates, Realtime "Allow public access" OFF, `pg_graphql` exposure (DEP-013).
4. Where the admin dashboard will be hosted, and its response headers (DEP-004).
5. Whether the deleted `staff-admin` Edge Function was removed from hosted (`supabase functions list`), as DEPLOY_SUPABASE §4a asks.
6. Whether Sentry projects and DSNs exist, the alert rules, who receives them, and the quota for Session Replay (DEP-005).
7. That the Android upload keystore exists, is backed up off-machine, and its passwords are in the password manager; the Apple developer team setup (DEP-015).
8. Advisory status of the Dart/Flutter dependencies (OSV / GitHub advisory search for the locked versions); not available from `pub outdated` (DEP-012).
9. Whether the GitHub repo (`origin`) has branch protection, secret scanning or Dependabot alerts enabled server-side (no repo-level config found).
