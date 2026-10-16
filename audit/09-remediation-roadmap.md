# Remediation Roadmap

Ordered by security and money impact, then by dependencies between fixes. Effort: S = under a day, M = 1–3 days, L = more than 3 days. Every schema fix follows the declarative workflow in `CLAUDE.md` (edit `supabase/schemas/`, generate, read the migration, apply locally, re-sync shows no changes, advisors). Each fix should come with the verification named in its finding.

## 1. Critical blockers (do first; launch is impossible without them)

| Order | ID | Fix | Effort | Depends on | Regression risk / check |
|---|---|---|---|---|---|
| 1 | DEP-002 | Enable backups/PITR on the hosted plan. Take a `pg_dump` of hosted dev before any push. Run one restore drill into a scratch project. | S | — | None. Prerequisite for every hosted step below |
| 2 | SEC-002 | On hosted: list Edge Functions and delete `staff-admin`. Diff the hosted schema against `schemas/` and drop leftovers. | S | 1 | Low. Verify with `supabase functions list` and a schema diff |
| 3 | DEP-001 | Choose the path: a **fresh production project** on the new 11-file history (recommended, since nothing is live), or `migration repair` on dev. Rewrite `docs/DEPLOY_SUPABASE.md` §§3–4, `CLAUDE.md:43` and `supabase/README.md:20`. | M | 1, 2 | Medium. `db push --dry-run` must list exactly the 11 files |
| 4 | DEP-007 | Create a separate prod project and point `environment.production.ts` and `dart_define.prod.json` at it. Keep dev as staging. | S | 3 | Low |

## 2. Must fix before launch

| Order | ID | Fix | Effort | Depends on | Regression risk / check |
|---|---|---|---|---|---|
| 5 | BL-001 | In `op_session_start`, `op_session_end`, reconfigure and the group ops: refuse `started_at` or `ended_at` later than `statement_timestamp()` plus a small skew. Bound back-dating by the op's queue age (offline window) or flag it. Store the server receipt time and show it on the dashboard's late or back-dated flag. | M | — | **High (billing).** Run `supabase test db`, `tool/pricing_parity.sh` and `tool/sync_it.sh` (offline-then-reconnect case) |
| 6 | NG-001 (+ NG-003 / DEP-004) | Escape tooltip text, or pass an element with `textContent`, in `geo-map.ts:199`. Optionally add a `char_length` and character check on `name` in `op_staff_update` and invites. Ship a CSP and security headers with the admin host. | S | 4 for the host | Low. Spec: a name of `<img onerror>` renders as text |
| 7 | DB-002 | Change staff-module FKs to `staff_profiles` (`salary_run_lines`, `leave_requests`, `staff_pay_rates`, …) from `on delete cascade` to restrict. Runbook §7.7: "deactivate; never delete a login that has records". | S | 3 | Medium (FK change). Add a pgTAP case: deleting a user with a salary line is refused |
| 8 | ST-001 (+ ST-010, DB-006) | Refuse `salary_run.finalise` while `period_end >= IST today` and while entries are pending review. Take `FOR UPDATE` on the run and a period-level lock read by `_period_finalised` writers. **Alternative for launch:** hide Payroll. | S–M | — | Medium (payroll). Run pgTAP 31 plus new cases |
| 9 | FL-004 / CQ-001 | Make the fixtures build true v10…v16 schemas (drop `activities.overtime_grace_minutes`) and add a v16→v17 group. Run the Drift migration suite green. Reconsider the step-16 cursor reset. | S | — | Low. Device upgrade is the risk this covers |
| 10 | SEC-003 / ST-006 | Add `_own_record` to `op_leave_adjust`, `op_pay_rate_add`, `op_salary_adjustment_add`, `op_hr_profile_save` and `op_salary_run_set_deduction`. | S | — | Low. pgTAP: a non-owner holder is refused on their own staff id |
| 11 | NG-002 | Mint op, payment and adjustment ids once per user action and reuse them on retry. Give `leave.adjust` and `attendance.correct add` client ids. | S–M | — | Medium. Unit test: retry after a simulated timeout sends the same ids |
| 12 | BL-003, BL-002 | Server: cap waive by the discount-permission cap or make it owner-only, and require a reason. Refuse a segment whose activity is unpriced or not offered by the station. | M | 5 | Medium (billing). Parity plus pgTAP refusals |
| 13 | FL-003 | Let the server accept a revoked member's already-queued ops (op `created_at` before the revoke) or surface them to the owner. At minimum, warn the owner on the dashboard. Design choice needed. | M | — | Medium (sync). `tool/sync_it.sh` |
| 14 | FL-001 / DB-008 | Server: catch per-op errors, including the uuid cast and op-id reuse, inside the loop; distinguish transient from permanent errors; cap the batch size. Client: attempt cap with backoff, batch halving, and a dead-letter shown under Sync → Needs attention. | M | — | Medium (sync). `tool/sync_it.sh`, `supabase test db` |
| 15 | SEC-001 | Product decision: narrow `sync_pull` and `sync_fetch_entity` by permission (customers and payments only with `bill`/`members`), or accept and document it. Required before issuing attendance-only logins. | M | — | Medium. Test 18 sensitive-reads cases |
| 16 | FL-005 / DEP-006 | Set `android:allowBackup="false"` (or `dataExtractionRules` excluding the DB and prefs). | S | — | Low |
| 17 | DEP-005 / FL-006 | Add `AO_SENTRY_DSN` and `AO_ENVIRONMENT=production` to the release defines, and make `problemFor` refuse a release without the environment. Add basic admin error reporting. | S | 4 | Low |
| 18 | SEC-004 | Enable CAPTCHA (Turnstile or hCaptcha) on hosted Auth and send the token from both apps' sign-up, OTP and reset calls. | M | 4 | Low |
| 19 | DEP-003 | Minimal CI on PRs: `flutter analyze`, `npm run build -c production`, `supabase test db`, the Drift migration test. | M | 9 | None |

## 3. Fix shortly after launch (first 2–4 weeks)

* **Money and records:** DB-004 (guard triggers blocking UPDATE/DELETE on payments, charges and `audit_log`; restrict instead of cascade) · DB-009 (audit permission, price, pay and run changes) · BL-005 (booking vs session on the server) · BL-004 (overtime-grace parity cases, and fix the SQL/Dart divergence).
* **Staff module:** ST-002 (filter `shifts.active` in `_att_blocks`) · ST-003 (respect `tracks_attendance` and deactivation in pay lines) · ST-004 (recompute the leave split at read time) · ST-005, ST-007, ST-008 · DB-007 (lock the balance on approve).
* **Scale:** DB-005 (paginate `sync_pull` before serialising) · FL-002 (no 100k full pull) · DB-010 (index `closed_at`, trim the overview JSON).
* **Operations:** DEP-008 (rollback notes per migration; never ship a data-dropping migration without a copy step) · DEP-004 hosting config in the repo.
* **Quality:** CQ-002 (remove orphaned admin pages and specs; spec for Team) · CQ-004 (hide the mobile owner screens as planned) · CQ-003 (either implement discounts on the floor or hide coupon creation) · NG-004 (break the `realtime-sync.ts` eager import graph to get under the 500 kB budget).

## 4. Long-term improvements

* A tenant-isolation pgTAP sweep: a member of arena A reads zero rows of B for every table and RPC, plus deactivated-member cases (07 test gaps).
* Concurrency scripts for overpayment, double clock-in, finalise vs correction, and concurrent leave approvals.
* One shared refusal-code → copy table per app (CQ-010); consolidate IST and rupee helpers (07 per-app notes).
* A guard for the server ↔ Drift column contract (CQ-005); `plan(n)` instead of `no_plan()` in pgTAP.
* Make `arenas.timezone` real or drop it (DB-014); retention for `sync_ops`, tombstones and punch GPS (DB-012, ST P3).
* Docs accuracy pass (CQ-006).
* Dependency hygiene: drop the pnpm lockfile, pin toolchains, upgrade `flutter_local_notifications` (DEP-010…012).

## Sequencing notes

* Steps 1–4 are operational and unblock everything hosted. They can run in parallel with the code fixes in steps 5–19.
* Steps 5 and 12 both change billing and should ship together behind one parity and sync_it run.
* Steps 8, 10 and the payroll P2s can be skipped for launch if Payroll is hidden. Attendance and leave can still launch.
* Re-run this audit's P1 checks after the fixes, and do the hosted verifications in `08-production-checklist.md` (S17, S19, O3, O9).
