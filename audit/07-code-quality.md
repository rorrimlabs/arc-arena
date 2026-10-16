# 07 — Cross-cutting code quality and test-suite assessment

## Scope and method

Static, read-only review of the repo at `feature/venue-generalization` (clean tree, 2026-10-16). Covered: size and complexity hotspots across the three codebases, business logic duplicated across layers (pricing, IST, money, attendance, permissions), the refusal-code vocabulary, dead code and leftovers, how well `supabase/README.md`, `docs/SYNC.md` and `docs/STAFF_API.md` match the code, and an inventory of the test suites with their gaps.

Tools used: `wc`, `find`, `grep`, `git log/show`, and a heuristic script that measured function lengths. I ran no tests, builds, analyzers or installs. "VERIFIED" means I confirmed it by reading the code. It never means a test was run. Per-app quality notes come from 03 and 04, and other auditors' IDs (DB-, DEP-, BL-, SEC-, NG-) are cited where findings overlap.

## Metrics

| Area | Files | Lines | Notes |
|---|---|---|---|
| `apps/mobile/lib` (hand-written) | 215 | 43,963 | plus 33,958 generated (`*.g.dart`, `*.freezed.dart`) |
| `apps/admin/src` `.ts` (non-spec) | 218 | 42,100 | includes 17 `*.sample.ts` test fakes (3,758 lines, not imported by production code) |
| `apps/admin/src` html/css | — | 951 | most templates are inline |
| `supabase/schemas` | 288 | 17,120 | 193 public + 28 private functions, 53 tables, 4 views |
| `supabase/migrations` | 11 | 16,957 | squashed baseline `20261015054055_declarative_sync.sql` + 10 generated |
| `apps/mobile/test` | 97 | 22,323 | ~816 `test`/`testWidgets` cases; 6 support files |
| `apps/admin/src/**/*.spec.ts` | 45 (+3 `integration/*.it.spec.ts`) | 9,009 | ~427 `it(` cases |
| `supabase/tests` (pgTAP) | 27 (00, 01, 07–31; no 02–06) | 6,115 | ~1,280 assertions; every file `no_plan()` |
| `supabase/concurrency_tests` + `tool/*.sh` | 5 + 3 | 546 | station race, pad races, parity, sync IT, verify_all |
| `tool/pricing_parity` | 2 | 838 | `generate.dart` (592) + `harness.sql` (246) |

Largest hand-written files and functions:

| Location | Size | What it is |
|---|---|---|
| `apps/mobile/lib/app/controllers/group_session_actions.dart` | 1,152 | group action controller |
| `apps/mobile/lib/data/local/local_group_session_repository.dart` | 1,119 | group repository |
| `apps/mobile/lib/app/sync/cloud_root.dart` | 957 | `_openArena` alone is ~208 lines (`:308`) |
| `apps/mobile/lib/data/local/local_session_repository.dart` | 939 | single-session repository |
| `apps/mobile/lib/data/sync/sync_applier.dart` `upsert()` | 407-line function (`:243-649`) | one `switch` that maps 34 server tables to Drift companions |
| `apps/mobile/lib/features/group_sessions/presentation/group_session_screen.dart` `build()` | ~231 lines | widget |
| `apps/admin/src/app/features/setup/setup-page.ts` | 676 | setup wizard (inline template) |
| `apps/admin/src/app/features/attendance/attendance-home-page.ts` | 638 | |
| `supabase/schemas/public/functions/_pay_build_line.sql` | 276 | salary line: real complexity |
| `supabase/schemas/public/functions/_sales.sql` | 227 | session and group branches repeat the same correction subquery (`:91`, `:178`) |
| `supabase/schemas/public/functions/op_attendance_punch.sql` / `_att_day.sql` | 203 / 188 | real complexity |
| `_sync_apply.sql` / `private/sync_pull.sql` / `_pr_quote.sql` | 124 / 76 / 127 | small: the SQL side is well factored |

---

## Findings

## [P2][CQ-001] The Drift migration test suite fails because its fixtures are stale, and v16→v17 has no test
**Status:** VERIFIED (static; root cause confirmed by reading, not by running)
**Category:** Test suite / data migration safety
**Location:** `apps/mobile/test/data/local/migration_test.dart:48-99, 245-282, 353-390, 452-483, 548-575, 636-709`; `apps/mobile/lib/data/local/database.dart:53-54, 651, 819-825`
**Problem:** Each `buildV10…V15Database()` fixture creates the file with the current `AppDatabase.createAll()` and then drops the columns and tables that arrived later. Commit `4fd1109` added `activities.overtime_grace_minutes` (v17), but no fixture drops it. Every upgrade test therefore reaches step `16:` with the column already present, and `m.addColumn` fails with `duplicate column name: overtime_grace_minutes`. There is also no `group('v16 -> v17 …')`.
**Evidence:** `grep overtime migration_test.dart` returns 0 hits. Groups exist for v10→v11 through v15→v16 only (`:122, 287, 395, 488, 580, 714`). Step 16 is a plain additive `addColumn` plus a cursor rewind (`database.dart:819-825`), which is correct for a real v16 file built before `4fd1109`.
**Impact:** CLAUDE.md lists this as a "possible upgrade failure on devices". Statically it is a fixture bug, not a bug in the step. Still, the whole migration suite is red, so it gives no signal. A real regression in any step, including the untested v16→v17 one, would go unnoticed. The device database is the only copy of the day's takings.
**Failure Scenario:** A future step is written wrongly, for example a rewrite instead of an addition, or a gap in `_steps`. The suite was already red, so nobody notices, and devices fall through to the destructive rebuild (`database.dart:845-856`) and lose unsynced takings.
**Recommended Fix:** In each fixture, add `ALTER TABLE activities DROP COLUMN overtime_grace_minutes`. Add a v16→v17 group that checks: sessions, charges and payments survive; the default is 0; the pull cursor is 0; `rebuiltFromVersion == 0`. Then correct the CLAUDE.md "Known limitations" line.
**Estimated Effort:** Small
**Production Blocker:** Yes (release gate: the migration safety net has to be green before shipping a v17 build)
**Suggested Verification:** `flutter test test/data/local/migration_test.dart`, then a manual upgrade of a real v16 release build to the v17 build on a device.

## [P2][CQ-002] Orphaned admin pages still have specs that navigate to redirected routes; the live Team screen has none
**Status:** LIKELY (specs not run)
**Category:** Dead code / test hygiene
**Location:** `apps/admin/src/app/features/users/users-page.ts` (181), `users/components/user-detail.ts` (234), `calendar/calendar-page.ts` (453), `pay-setup/pay-setup-page.ts` (164) and their specs; `apps/admin/src/app/app.routes.ts:81-88`
**Problem:** Commit `6dd3d18` folded Users, Calendar and Pay setup into Team and Attendance, and redirects `users`, `staff/calendar` and `staff/pay-setup`. `UsersPage`, `UserDetail`, `CalendarPage` and `PaySetupPage` are now referenced only by their own files. Their specs remain: 392 + 102 + 189 lines that navigate to the redirected URLs and assert the old markup. The calendar spec also asserts `NAV_ITEMS.find(i => i.path === 'staff/calendar')?.perm` (`calendar-page.spec.ts:20`), and that nav item no longer exists (`core/layout/nav.ts:33-66`). The routed `features/team/*` (team-page.ts 242, member-detail.ts 461) has no spec.
**Evidence:** `grep -rln "\bUsersPage\b|\bCalendarPage\b|\bPaySetupPage\b"` matches only the defining files. `users-page.spec.ts` navigates by URL and queries `section[aria-labelledby="users-…"]`, which `team-page.ts` does not render.
**Impact:** These specs almost certainly fail too. The CLAUDE.md "7 failing admin specs" list is then incomplete, and the red suite hides new regressions. About 1,030 lines of unreachable code and about 680 lines of tests guard screens nobody uses, while the real Team and access screen goes untested.
**Failure Scenario:** A bug in `member-detail.ts` permission toggling ships. No spec covers it, and the old users spec "covers" an unreachable copy.
**Recommended Fix:** Delete the four orphaned page components and their specs, keeping the shared pieces `invite-list`, `user-access`, `user-dialog` and the data layers still in use. Port the users spec's permission-toggle cases to a `team-page.spec.ts`. Update the failing-spec list in CLAUDE.md.
**Estimated Effort:** Small–Medium
**Production Blocker:** No
**Suggested Verification:** `npm test` in `apps/admin`, and record the actual failing set.

## [P2][CQ-003] Discounts can be configured and are enforced on the server, but no client can apply one
**Status:** VERIFIED
**Category:** Dead or incomplete feature / cross-layer consistency
**Location:** `supabase/schemas/public/functions/_discount_apply.sql`, `op_session_end.sql:82-90`, `op_group_end.sql:87-95`; `apps/admin/src/app/features/pricing/components/discount-detail.ts`; `apps/mobile/lib` (absent)
**Problem:** Owners create presets and coupons on the dashboard (decision #21), and the server validates and records them in `session.end` / `group.end`. The floor app never sends a `discount` object: `grep -i discount apps/mobile/lib` finds only the permission, the waive guard and comments. The admin web never ends sessions. Nine refusal codes are raised but mapped by neither client: `coupon_expired`, `coupon_unknown`, `coupon_used_up`, `discount_inactive`, `discount_min_bill`, `discount_not_started`, `discount_over_limit`, `discount_reason_required`, `discount_scope`. The discount logic exists only in SQL, so `tool/pricing_parity.sh` does not cover it.
**Evidence:** In the code map I built (SQL `raise exception` codes against Dart/TS references), 12 of 136 codes are unmapped, and 9 of those are discount codes.
**Impact:** Owners can set up coupons and limits that have no effect at the counter. When a floor UI is added, the device must compute `amount_paise` exactly as `_discount_apply` does (round-half-up, cap, scope base). There is no Dart implementation and no parity harness for that yet.
**Failure Scenario:** The owner announces a "WEEKEND20" coupon. Staff have no field to enter it, so they use waive or nothing, and the discount reporting (`arena_discount_usage`) shows zero uses.
**Recommended Fix:** Either hide discount configuration until the floor flow exists, or build it. If building: add a pure Dart discount calculator, extend `generate.dart` and `harness.sql` with a discount case kind, and map the nine codes.
**Estimated Effort:** Medium (floor flow + parity) / Small (hide)
**Production Blocker:** No
**Suggested Verification:** `supabase test db` (test 25) and `tool/pricing_parity.sh` once discounts are added.

## [P2][CQ-004] The mobile owner screens duplicate admin owner features with diverging logic and are reachable in production
**Status:** VERIFIED (code read); the impact on reported numbers is LIKELY
**Category:** Duplicated business logic
**Location:** `apps/mobile/lib/app/router/app_router.dart:56-98, 126-141`; `apps/mobile/lib/domain/reports/reports_service.dart:105-126`; `apps/mobile/lib/features/more/presentation/settings_screen.dart:45-81`; `staff_screen.dart:296-312`; `apps/mobile/lib/app/controllers/catalog_actions.dart:128-158`; compare `supabase/schemas/public/functions/_sales.sql:21-25, 91-102` and `op_payment_correct.sql:87-99`
**Problem:** CLAUDE.md says owner features are admin-only and that the mobile Today, Money, Reports and Settings screens "will be hidden later". Today they are routed for any owner-level user. Settings pushes `rate.upsert`, `policy.save`, `game.upsert`, `resource.upsert` and `staff.update`, which is a second editor for the same data. Two divergences found:
1. **Refund totals.** `ReportsService` counts every `is_refund` / negative payment as "refunded" and every row as a transaction. The dashboard's `_sales` excludes `payment.correct` pairs, which it identifies by the ids in `audit_log`. Devices do not sync `audit_log`, so the mobile "Refunded" figure and per-method counts include method corrections. Net collected agrees.
2. **Permissions.** `StaffScreen` offers all 12 permissions as chips, and `saveStaff` only blocks self-edits. It has no owner-level gate for `money`, `reports`, `payroll` or `payroll_finalise`. The server refuses the change (`op_staff_update.sql:56-67`), so the op lands in Sync → Needs attention instead of failing in place.
**Evidence:** In `reports_service.dart:115-118`, `if (isRefund || amount < 0) refunded += amount.abs();`. Correction legs are inserted with `kind 'refund'` / `is_refund true` and note `'Method correction'` (`op_payment_correct.sql:87-99`).
**Impact:** An owner who compares the phone's Money or Reports tab with the dashboard sees different refund totals for the same day. Validation of config edits lives in two UIs.
**Failure Scenario:** The owner corrects ₹500 from Cash to UPI on the dashboard. The phone's Reports tab now shows ₹500 "refunded" and two extra transactions for that day.
**Recommended Fix:** Hide these routes and the Settings sub-screens in cloud mode now (a router `requires` flag plus a `more_screen` gate). That matches the stated direction and removes the second editor. If they stay, exclude rows whose note is `Method correction` from the refund totals.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Manual check: correct a payment's method on the dashboard and compare the phone's Reports figures for that day.

## [P2][CQ-005] The server↔Drift column contract is unguarded: pgTAP 00 is frozen at Drift v11, and `sync_applier.upsert` is a 407-line hand mapping
**Status:** VERIFIED
**Category:** Cross-layer consistency / tests
**Location:** `supabase/tests/00_schema_parity_test.sql:1-25`; `apps/mobile/lib/data/sync/sync_applier.dart:243-649`
**Problem:** Test 00 says "a strict superset of Drift v11" and hard-codes that era's tables. It has no `pricing_rules` (v16), `customers.birth_year` (v15), `activities.overtime_grace_minutes` (v17) or `discounts`. The real contract is the hand-written `upsert()` switch, which casts server JSON (`r['sort_order'] as int`, `r['active'] as bool`, …) for 34 tables. A renamed or nullable server column causes a runtime `TypeError` during pull. The only automated check against the real schema is `tool/sync_it.sh`, which runs manually on a live local stack.
**Evidence:** `grep -c 'pricing_rules|birth_year|discounts' 00_schema_parity_test.sql` returns 0. The unit tests in `test/data/sync/*` feed scripted rows (`support/scripted_transport.dart`), not real server rows.
**Impact:** A schema change made only in `supabase/schemas` can break every device's sync with no failing pgTAP or unit test. That leaves devices "offline" and the takings stuck on them.
**Failure Scenario:** A column on `rates` becomes nullable on the server. The first null row throws in `upsert`, every pull fails, and all devices show Offline.
**Recommended Fix:** Have test 00 assert the column list per table that the applier reads, generated from or kept next to `sync_applier.dart`. At minimum, extend it to v17. Also make `tool/sync_it.sh` a release gate.
**Estimated Effort:** Small–Medium
**Production Blocker:** No
**Suggested Verification:** `supabase test db`, `tool/sync_it.sh`.

## [P2][CQ-006] The reference docs contradict the code: table counts, permission list, client API, migration history, Users page
**Status:** VERIFIED
**Category:** Docs accuracy
**Location:** `supabase/README.md:12, 19, 20, 76-77, 89, 165`; `CLAUDE.md:43`; `docs/SYNC.md:45-50, 261-263, 278, 312, 334, 474`; `docs/DEPLOY_SUPABASE.md:52, 310, 312`; `op_session_end.sql:6-7` / `op_group_end.sql:9-10`
**Problem:** I spot-checked 10 claims in `supabase/README.md`, 8 in SYNC.md and 8 in STAFF_API.md. Wrong:
- README: "35 tables" (actually 53); "The 29 tables in the publication" (actually 33; SYNC.md says 33 correctly); "`0001`–`0016` are the original hand-written history" (squashed into `20261015054055_declarative_sync.sql` in `5d9e137`; see DB-001/DEP-001). **Security model:** "`perms` ⊆ start, bill, discount, members, stations, money, reports, settings" omits the four staff permissions, including the owner-only `payroll` / `payroll_finalise`. The client API row omits `attendance_days` and `leave_balances` (they are in test 13's allow-list). It also says "dashboard Users → Invite".
- CLAUDE.md:43 repeats the `0001`–`0016` baseline claim.
- SYNC.md: links `supabase/migrations/0016_integrity_and_authz.sql` (deleted); "`t_same_arena` triggers on 19 tables" (now 30); "dashboard → Users"; section titles keyed to deleted migrations (0013, 0016).
- DEPLOY_SUPABASE.md (the go-live runbook) tells the owner to use "Users → Invite user / Deactivate". The nav item is now Team; `/users` still redirects.
- `op_session_end` / `op_group_end` headers say "billed = cash-rounded subtotal − discount". The code (`op_session_end.sql:82-89`) and decision #21 round **after** subtracting.

Correct: SYNC.md 800 ms dashboard debounce, 0.3 s push / 10 s poll, uuid lock order and the published table list. STAFF_API.md `work_hours` / `leave_rules` defaults and ranges, the 62-day `attendance_days` limit and its permissions, and the staff op refusal sets, except as noted in CQ-010.
**Impact:** The README is the security map named in CLAUDE.md. A reader auditing permissions from it misses the payroll permissions. Operators following the go-live runbook look for screens and migrations that no longer exist.
**Failure Scenario:** During go-live, an operator follows DEPLOY_SUPABASE and expects `0001`–`0016` in the migration history.
**Recommended Fix:** Correct the listed lines. Make the counts non-numeric ("every table in `schemas/public/tables`") so they cannot go stale. Fix the two function headers.
**Estimated Effort:** Small
**Production Blocker:** No (the runbook part is covered by DB-001/DEP-001)
**Suggested Verification:** Re-read the docs after the edit; `grep -n "0016\|Users" docs/*.md supabase/README.md`.

## [P2][CQ-007] Test-suite signal is weak at HEAD: known-red suites, all-`no_plan` pgTAP, and the parity and concurrency checks are manual opt-ins
**Status:** VERIFIED (structure); pass/fail state comes from CLAUDE.md, not from a run
**Category:** Test infrastructure
**Location:** `tool/verify_all.sh:9-10, 62-81`; all `supabase/tests/*.sql` (`select * from no_plan()`); CLAUDE.md:116-117
**Problem:** There is no CI (DEP-003). `verify_all.sh` runs pricing parity and both concurrency races only with `--with-psql`, and `sync_it` only with `--with-it`. It builds the admin with `--configuration development`, so the production budget and AOT settings are not exercised. All 27 pgTAP files use `no_plan()`, so an assertion block that silently stops running (for example, an early `rollback` or a refactor that drops a `select is(...)`) cannot be detected. Two suites are known red (CQ-001, CQ-002).
**Impact:** The strongest money checks (parity with self-tests, two-connection races) depend on someone remembering to opt in. Red suites train people to ignore failures.
**Failure Scenario:** A `_pr_*` edit passes `supabase test db` and ships. Parity was never run.
**Recommended Fix:** Make `--with-psql --with-it` the release-checklist default (`docs/RELEASE.md`). Fix the two red suites. Optionally switch the money-critical pgTAP files (08, 22, 24, 25, 31) to `plan(n)`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `bash tool/verify_all.sh --with-psql --with-it` before release.

## [P3][CQ-008] The `stations` permission is dead: defined in SQL and Dart and grantable on the phone, but nothing checks it
**Status:** VERIFIED
**Category:** Dead code / permissions consistency
**Location:** `supabase/schemas/public/functions/_known_perms.sql:15-16`; `apps/mobile/lib/domain/auth/permission.dart:12`; `apps/mobile/lib/domain/auth/permission_guard.dart:92`; `apps/mobile/lib/features/more/presentation/staff_screen.dart:304`
**Problem:** Across all `_need` / `app_has_perm` / `app_arena_ids_with` calls in `supabase/schemas`, the permissions checked are start (14), settings (38), payroll (10), discount (4), leave_approve (4), attendance_review (3), bill (3), members (2), payroll_finalise (2) and money (1). `stations` is never checked; station ops use `settings`. In the apps, only the guard's label table mentions it. The admin cannot grant it (`FLOOR_PERMS`, `user.models.ts:25`). The phone's staff screen can.
**Impact:** An owner who grants "Manage stations" on the phone gives nothing, which is confusing but not a security hole.
**Recommended Fix:** Either remove it from `_known_perms`, the Dart enum and docs, or wire it to the station ops. Removing it touches the permissions in existing rows, so take it as a deliberate decision, not a cleanup.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `supabase test db` (tests 13 and 29 assert the permission set).

## [P3][CQ-009] Permission sets, the IST offset and rupee parsing are duplicated as literals across and within layers
**Status:** VERIFIED (all copies currently agree; no cross-layer test detects drift)
**Category:** Duplicated logic
**Location:**
- Permissions: `_known_perms.sql:15-16`, `apps/mobile/lib/domain/auth/permission.dart:7-19` (same 12 codes, same order, verified), `apps/admin/.../users/data/user.models.ts:25-53` (subset of 8 plus `OWNER_ONLY_PERMS`). Owner-level sets: `op_staff_update.sql:13, 56-67`, `private/functions/invite_member.sql:65`, `private/functions/app_is_owner.sql:25`, `apps/mobile/lib/domain/auth/app_user.dart:27`.
- IST offset: `apps/admin/src/app/shared/time/ist.ts:5`, `features/attendance/data/attendance.models.ts:316`, `features/overview/data/overview.models.ts:19`, `shared/staff/staff-format.ts:62` (magic `330 * 60_000`), plus Dart `core/time/ist.dart` and SQL `_pr_ist_date` (see also DB-014).
- Rupees→paise: exact regex `features/sales/data/sale.models.ts:426` (imported by payroll and pay-setup from the *sales* feature), float+epsilon `pricing/components/discount-detail.ts:91-96` and `rule-detail.ts:401-402`, whole-rupee `type-detail.ts:326-335` and `setup/setup-page.ts:586-597`.
- Display mirrors of server rules: `apps/mobile/lib/domain/attendance/attendance_rules.dart` (`previewPunch` mirrors `op_attendance_punch` / `_geo_distance_m`), `apps/admin/.../pay-setup/data/pay-setup.models.ts:102-111` (`derivedHourlyPaise`, labelled ≈).
**Problem / Impact:** Every rule change has to be made in 3–6 places. The float parsers are correct for two-decimal input, and the previews are labelled as estimates, so nothing is wrong today. Pricing is the exception: its Dart↔SQL duplication is guarded by `tool/pricing_parity.sh` (a strength).
**Recommended Fix:** In admin, import `shared/time/ist.ts` everywhere, and move `parseRupees` / `rupeesText` to `shared/money`. Add one pgTAP assertion that `_known_perms()` equals a literal list, and one Dart test pinning `Permission.values` codes, so drift needs two deliberate edits. No new abstraction layer.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `npm run build`; `flutter analyze`.

## [P3][CQ-010] The refusal-code vocabulary is spread across about 20 tables; a few codes are mapped nowhere and STAFF_API omits some
**Status:** VERIFIED
**Category:** Consistency
**Location:** `apps/mobile/lib/features/sync/presentation/sync_screen.dart:160-249`; admin `*_MESSAGES` maps in `core/sync/push-ops.ts:144`, `core/floor/floor-api.ts:109`, `features/{sales,pricing,payroll,leave,attendance,shifts,pay-setup,users,accessories}/data/*`, `features/settings/data/*` (about 20); `docs/STAFF_API.md`
**Problem:** SQL raises 136 distinct `raise exception '<code>'` codes. 124 are referenced by at least one client. Besides the 9 discount codes (CQ-003), these are unmapped: `op_id_reused` (`private/functions/sync_push.sql:42`), `not_a_controller` (`_pad_allocate.sql:44`, `_pad_borrow.sql:34`) and `no_account` (`create_my_arena.sql:37`). Both apps fall back to a generic text (`'refused ($code)'`), so the fallback is safe. `period_finalised` copy is duplicated in `attendance.models.ts:309` and `leave.models.ts:325`. STAFF_API.md claims "All refusal codes are listed" but omits `reason_too_long` (`op_attendance_correct`, `op_leave_request`) and the punch codes `already_clocked_in`, `not_clocked_in`, `outside_geofence`, `mock_location` and `location_required`. The first two appear only in STAFF.md; the last three appear in no doc.
**Impact:** Inconsistent wording, and copy has to be kept in sync by hand.
**Recommended Fix:** Add the missing codes to STAFF_API.md. Give `op_id_reused` a message in both apps, since it signals a device-id bug.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Re-run the code map: `grep -rhoE "raise exception '[a-z_]+'" supabase/schemas` against both apps.

## [P3][CQ-011] Single-session and group pipelines are parallel copies across every layer, and the largest files come from that split
**Status:** VERIFIED
**Category:** Size / complexity hotspot
**Location:** `apps/mobile/lib/app/controllers/{session,group_session}_actions.dart` (775 / 1,152); `apps/mobile/lib/data/local/local_{session,group_session}_repository.dart` (939 / 1,119); SQL `op_session_*` / `op_group_*`, `_pr_session_bill` / `_pr_group_bill`, `_sales.sql:91, 178`; tables `payments`/`group_payments`, `session_charges`/`group_charges`
**Problem:** Every money rule exists twice: waive, void, discount, correction, refund cap, overtime grace. The copies agree today. For example, the end/void refusal sets match, and the differences are explained by `_group_active`. Group-specific branches carry the extra size. Other size is plain verbosity: `sync_applier.upsert` (407 lines, CQ-005), `cloud_root._openArena` (~208 lines), and widget `build()` methods of 200–230 lines. SQL is well factored (largest function 276 lines, real complexity).
**Impact:** Changes cost more, and fixing one side only is easy. Pricing parity covers both bill kinds (`g`, `gx` cases), which mitigates this for pricing.
**Recommended Fix:** No rewrite. When a money rule changes, check the twin as part of review. Splitting `upsert` into per-table helpers and `_openArena` into phases is optional.
**Estimated Effort:** Small (review discipline) / Medium (splits)
**Production Blocker:** No
**Suggested Verification:** Code review checklist.

## [P3][CQ-012] Dead mobile repository methods: `voidSession` / `voidGroup`
**Status:** VERIFIED
**Category:** Dead code
**Location:** `apps/mobile/lib/data/local/local_session_repository.dart:660-690`; `local_group_session_repository.dart:723`; `domain/repositories/session_repository.dart:46`, `group_session_repository.dart:42`
**Problem:** SYNC.md says the floor app never voids, and no controller or widget calls these methods. Only 4 test files do. They still enqueue `session.void` / `group.void`. The server requires a reason and owner level, so a stray call is refused.
**Recommended Fix:** Remove them, or leave a comment saying they are retained for tests only.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `flutter analyze`.

Other dead-code checks were clean. There are **0** TODO/FIXME/HACK/XXX markers in `apps/mobile/lib`, `apps/admin/src`, `supabase/schemas` and `tool`, and grep found no commented-out code. `DateTime.now()` appears only in `core/clock`, telemetry, `db_safety` stamps and demo seeding. Admin `*.sample.ts` fakes are not imported by production code.

---

## Test suite assessment

**Inventory.** Mobile: 97 files, about 816 cases, covering domain (pricing 4, services 9, attendance/leave 3), data/local 11 (incl. `migration_test.dart`, `db_safety_test.dart`), data/sync 5, app controllers and permissions 14, features 21, integration 3, and `test/sync/` 5 that need a live stack and skip themselves without one. Admin: 45 unit specs plus 3 `integration/*.it.spec.ts` (run by `sync_it.sh`). pgTAP: 27 files, each in its own arena and rolled back. Scripts: `concurrency_tests/run.sh` (station race), `run_pads.sh` (pad race and same-op-id race), `tool/pricing_parity.sh` (3,000 random cases plus a boundary corpus plus two self-tests proving it can fail), `tool/sync_it.sh` (dashboard ↔ floor ↔ Mailpit, arena isolation), and `tool/verify_all.sh`.

| Area | Tests present | Gaps |
|---|---|---|
| Tenant isolation | Structural: test 13 (RLS on every table, select-only policies for `authenticated`, client-API allow-list, invoker views). Data: 18 (money, customer and audit rows; Realtime topic), 28 (punches vs. another arena), 14/26 (admin reads), 17 (invite only for its arena), 19/21 (cross-arena ops), `sync_it` phase 5. | No generic "member of arena B sees 0 rows of arena A" sweep over **every** table and read RPC. No assertion that every policy's `USING` filters by arena. The staff tables in tests 29–31 have **no** cross-arena checks (grep: 0). `sync_pull` over-sharing is SEC-001. |
| Role escalation | 10, 13 (owner-level grants, self-edit), 17 (inviter authority), 29 (payroll owner-only), 31 (payroll vs payroll_finalise, staff read no pay). | Own-record bypass on five staff ops is untested (SEC-003). Nothing pins `_known_perms()` against the Dart enum (CQ-009). |
| Removed / deactivated member | 18 (reads, Realtime), 28 (punch), 17 (inactive inviter), 13 (inactive manager `staff.update` refused), mobile `app/sync/staff_access_test.dart`. | No deactivated-member cases in 29–31 (`attendance_days`, leave, payroll RPCs). Nothing covers the up-to-3600 s Realtime window after revocation. |
| Duplicate submissions / op replay | 07, 19, 21, 22 (`payment.correct` replay), 28 (replay and duplicate ids), `run_pads.sh` race 2 (same op id concurrently), mobile `sync_engine_test`. | Leave ops: 0 replay checks in test 30. Payroll: 2. Admin regenerates ids per attempt (NG-002), and no test covers a retry after an ambiguous failure. |
| Concurrency | `run.sh` (one station), `run_pads.sh` (one pad, same op id). | Manual, opt-in (`--with-psql`). None for: two devices racing an overpayment, a double clock-in (relies on the unique partial index), a finalise racing a correction (DB-006), concurrent leave approvals (DB-007). |
| Drift migrations | `migration_test.dart` v10→v16 groups, `db_safety_test.dart`. | **Suite red** (CQ-001: stale fixtures). No v16→v17 group. Not verified on a real device upgrade. |
| Offline recovery | `sync_engine_test`, `two_device_sync_test`, `db_safety_test`, `money_and_durability_test`, integration `counter_shift_test`. | Rejected-op rollback across a schema change is untested, as is the applier against real server rows (CQ-005). |
| Financial calculations | Strong for pricing: `pricing_parity.sh` (q/x/s/g/gx cases, through real `sync_push`), pgTAP 08, 22, 24, 25, 31 (three STAFF.md worked examples to the paisa), mobile pricing 4 files. | Discounts have no Dart implementation and no parity (CQ-003). Overtime grace has no parity (BL-004). Mobile report totals vs `_sales` have no parity (CQ-004). Admin money parsers have no specs beyond `sale.models`. |
| IST boundaries | pgTAP 08, 25, 26, 29 (midnight shifts); mobile 5 files and admin 3 specs mention 18:30Z / midnight / +05:30; parity corpus includes IST midnight. | Test 30 dates are "relative to today" (`current_date` is UTC in Postgres). Runs between 00:00 and 05:30 IST may flip planned/backdated outcomes. NEEDS VERIFICATION. |
| Staff module (28–31) | 28: punch at server time, geofence/mock/accuracy rules, one open entry, auto-close, replay, own vs review vs other arena, anon. 29: permissions, settings validation, shifts, `_att_day` statuses/break/rounding/split/midnight, corrections, `attendance_days` access. 30: leave years, splits, cancel, adjustments, finalised lock, `leave_balances`. 31: worked examples, keep/waive, adjustments/reversal, finalise/discard, overlap, `net_negative`. | No cross-arena or deactivated-member cases in 29–31. No races (finalise vs correction, double approval). Own-record bypass (SEC-003). No Flutter↔server contract test for `attendance_days` JSON beyond `sync/attendance_punch_test.dart`. Admin staff screens: Team has no spec (CQ-002). |
| Admin UI | 45 specs over most features. | Known 7 failing (wording), plus LIKELY the orphaned users, calendar and pay-setup specs. Nothing for `setup-page.ts` (676 lines), `team/*` or `accessories`. |

Known limitations confirmed against the code. The Drift failure is in `apps/mobile/test/data/local/migration_test.dart`, caused by fixtures that never drop `activities.overtime_grace_minutes` (CQ-001). I could not confirm the "7 admin specs" count without running the suite, and the real number is likely higher (CQ-002).

## Strengths (evidence-based)

- **Pricing parity is a real gate.** `tool/pricing_parity.sh` generates Dart-priced cases (seeded random plus a boundary corpus), re-prices them in SQL both as functions and through real `sync_push` ops, and runs two deliberate one-paisa skews that must be caught (`pricing_parity.sh:15-21`).
- **Security posture is asserted, not just documented.** Test 13 checks the client-API allow-list, that no definer function is client-executable, RLS on every table, select-only policies and secure default privileges.
- **SQL is well factored and documented.** One object per file, a header on every function, a matching `comment on`, and refusal codes stated in headers. The largest function is 276 lines, and it is real salary logic.
- **One day calculation.** Neither app recomputes `_att_day`. The mobile `attendance_day.dart` and the admin calendar only map server JSON. The admin `entryMinutes` is raw out−in for display.
- **Clock discipline.** `DateTime.now()` and `new Date()` are confined to clock providers, telemetry and stamps. Timers derive from stored timestamps.
- **The permission enum matches exactly.** Dart `Permission` and SQL `_known_perms()` hold the same 12 codes in the same order. The owner-level rule (money or reports) is identical in SQL `app_is_owner`, Dart `isOwner` and the admin `isOwnerLevel`.
- **No TODO/FIXME debt, no commented-out code**, and sample fakes are kept out of production bundles.
- **The admin refusal fallback is safe.** Unmapped codes degrade to a generic message instead of crashing.

## Per-app notes (merged from 03/04)

### Angular admin (from 03-angular-audit.md)

- **Largest production files** (lines):
  - Over 600: `features/setup/setup-page.ts` 676, `features/attendance/attendance-home-page.ts` 638.
  - 500–600: `features/pricing/components/discount-detail.ts` 596, `features/pricing/components/rule-detail.ts` 557, `core/floor/floor-api.ts` 547, `features/attendance/attendance-page.ts` 514, `features/auth/accept-invite.ts` 514, `core/sync/realtime-sync.ts` 501.
  - Just under 500: `features/payroll/components/run-detail.ts` 495, `features/sales/sales-page.ts` 483, `features/pricing/data/pricing-api.ts` 482.
  - Several components combine template, form logic, validation and export code.
- **CSV download code duplicated 4×** (Blob, BOM, anchor, revoke, slug): `features/attendance/attendance-page.ts:500-512`, `features/attendance/attendance-home-page.ts:620-632`, `features/sales/sales-page.ts:470-480`, `features/payroll/components/run-detail.ts:478-490`. Extract a `shared/csv/download.ts`.
- **`textCell` lives in `features/sales/components/sales-csv.ts`** but is imported by the payroll and attendance exporters. Move it to `shared/csv`.
- **Two CSV money formatters:** `sales-csv.ts:41` `(paise/100).toFixed(2)` (float, correct for integer paise) vs `payroll-csv.ts:27` integer `moneyCell`. Use one.
- **Rupee input parsing implemented 4+ ways:**
  - `sale.models.ts:426` `parseRupees` (string-exact; also used by pay-setup and payroll).
  - `discount-detail.ts:91` `paise()` (float plus epsilon).
  - `rule-detail.ts:401` (float plus epsilon).
  - `type-detail.ts:326` and `setup-page.ts:586` (whole rupees).
  - Consolidate into `shared/money`.
- **IST constants duplicated:** `IST_OFFSET_MS` in `shared/time/ist.ts:5`, `features/attendance/data/attendance.models.ts:316` and `features/overview/data/overview.models.ts:19`; `DAY_MS` twice. `istInstant`/`istParts` belong in `shared/time/ist.ts`.
- **Dead code:**
  - `features/users/users-page.ts` is not routed (`/users` redirects to `staff/team`); only its spec references it.
  - The `ScreenPlaceholder` branch in `app.routes.ts:94-108` is unreachable while every `NAV_ITEMS` path is in `BUILT`.
- **Layering:** `core/sync/realtime-sync.ts` depends on 11 feature folders (NG-004). There are mutual feature dependencies: `pricing↔sales`, `overview↔sales`, `attendance↔calendar`, `settings↔shifts` (e.g. `sales-api.ts:6` imports `overview/data/overview.models`).
- **`dbError` re-exported** from `core/arena/arena-api.ts:52-55` and imported via both paths (e.g. `sales-api.ts:2` uses the arena-api path).
- **22 per-feature `*_MESSAGES` maps** for refusal codes, with overlapping entries (`forbidden`, `invalid_payload`, `not_found`). Consider one central code → copy table with per-feature overrides.
- **Test-awareness in production code:** `realtime-sync.ts:257-264` sniffs `process.env.VITEST`. Prefer an injectable toggle provided by tests.
- **`*.sample.ts` fakes** (3,758 lines) sit beside production code under `features/*/data`. They are test-only (only `testing/page-test.ts` imports them), so they are not in the bundle, but they inflate the feature folders.
- **Inconsistent submit guard:** 2 of 68 `busy` handlers check `busy()` on entry (NG-005).
- **Stacked doc comments:** `features/sales/data/sales-store.ts:93-101` has two JSDoc blocks; the first describes `refresh()` but is attached to `stale()`.
- **Inconsistent amount display:** `formatRupees` (whole-rupee) is used 34× vs exact `formatPaise` 16× (NG-006). Document which one is for which purpose.
- **Edge cases:**
  - `discount-detail.ts:530` sets `validUntil` to `23:59:59+05:30`, so a coupon expires one second early. Prefer an exclusive next-day midnight.
  - `announcePush` (`push-ops.ts:131`) calls `client.channel(topic)` when not joined, which registers a channel object on the client that is never removed. This is minor and NEEDS VERIFICATION against the realtime-js version.

### Flutter app (from 04-flutter-audit.md)

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

