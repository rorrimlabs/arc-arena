# Executive Summary — Pre-Production Audit

**Repository:** `arena_ops` (branch `feature/venue-generalization`, HEAD `24a4bdd`) · **Date:** 2026-10-16
**Type:** read-only, evidence-based audit. No application code, schema, migration, dependency or configuration was changed. Only `audit/` was written.

## Recommendation: **NO-GO today → CONDITIONAL GO after the blockers in §5**

There is **no P0**. No cross-tenant read or write path, auth bypass, exposed service-role key or client-executable privileged function was found. The database security model is unusually disciplined (see §3).

Launch is still blocked by **6 distinct P1s** and by **controls on the hosted project that cannot be verified from the repo**:

* Two P1s are about the **release process**. The squashed migration history cannot be pushed to the existing hosted project, and no backup or PITR is configured.
* One P1 is a **money-integrity gap the team has already documented as blocking** (`docs/SYNC.md:486-489`). Session start and end times come from the device, so a staff member can lower a bill by changing the tablet clock.
* One P1 is a **stored XSS** in the admin. A member with the `settings` permission can take over the owner's session.
* Two P1s are **staff-module data hazards**: deleting a login cascades through payroll and leave history, and a salary run can be finalised before its period ends.

Most fixes are Small to Medium. Payroll can be held back at launch (hide the Payroll nav item) if ST-001 and the payroll P2s are not ready.

## 1. Architecture overview

| Layer | What | Trust |
|---|---|---|
| Flutter staff app (`apps/mobile`, ~44k LOC Dart) | Riverpod, go_router and Drift (offline device DB). An outbox sends writes through `sync_push`; `sync_pull` and realtime nudges bring changes back. The staff module (attendance, leave) is online-only. | Untrusted client; the publishable key ships |
| Angular admin (`apps/admin`, ~42k LOC TS) | Owner dashboard: sales, pricing, settings, team, attendance, payroll. Reads come from RLS selects and RPCs; all writes go through `sync_push`. | Untrusted client |
| Supabase (`supabase/schemas`, ~17k LOC SQL) | 53 tables, ~220 functions and 4 views. Writes go `sync_push` → `_sync_apply` → `op_*` (SECURITY DEFINER, `_need(arena, perm)`). RLS is select-only. 25 client RPCs are invoker wrappers. | Security boundary |
| Auth | Supabase Auth. Owners self-register; everyone else joins only by invitation (hashed single-use token tied to the confirmed e-mail). | — |
| Not used | Edge Functions (repo), Storage buckets, CI | — |

The tenant is the **arena**. Permissions are a `text[]` on `staff_profiles`, and `role='owner'` holds every permission.

## 2. Findings by severity

| Severity | Raw (all reports) | Distinct after de-duplication |
|---|---|---|
| P0 Critical | 0 | **0** |
| P1 High | 8 | **6** |
| P2 Medium | 45 | **39** |
| P3 Low | 59 | **54** |
| **Total** | 112 | **99** |

Merged duplicates (canonical ID first): DEP-001 = DB-001 · DEP-002 = DB-003 · SEC-003 = ST-006 · FL-004 = CQ-001 · FL-005 = DEP-006 (≈ SEC-010) · DEP-004 = NG-003 (≈ SEC-011) · DB-008 ≈ FL-001 · DEP-005 ≈ FL-006 · DEP-007 = NG-011 · DEP-003 = DB-016 · DB-006 ≈ ST finalised-lock race (P3).

## 3. Security assessment

**Strong, with no P0 or P1 security defect at the database boundary** (`01-security-audit.md`):

* **Privileges:** every table, view, function and sequence file revokes PUBLIC and anon. No public SECURITY DEFINER function is client-executable, and the client API matches the allow-list in test 13 exactly. Every definer function pins `search_path`.
* **Writes:** RLS is select-only, with no insert, update or delete policies. Each `op_*` scopes lookups to `arena_id = p_arena`, and 30 tables also carry `_assert_same_arena` triggers.
* **Escalation:** nobody can change their own permissions, and only owner-level members can grant owner-level permissions.
* **Secrets:** none in the repo or git history (3,655 objects scanned). The only committed hosted key decodes to `role: anon`.

Material security risks that remain:

* **NG-001 (P1):** stored XSS through the map tooltips, with no CSP to limit it.
* **SEC-001 (P2):** any member can page the whole customer and payment ledger out of `sync_pull`. This is an open product decision that must be settled before attendance-only logins are issued.
* **SEC-002 (P2, NEEDS VERIFICATION, blocker until checked):** the hosted project may still run the old `staff-admin` Edge Function. It holds the service-role key, was deployed with `--no-verify-jwt`, and allows any origin.
* **SEC-003 (P2):** the own-record rule is missing on the leave-adjust and pay ops.

## 4. Major risks (top 10)

| # | ID | Sev | Risk | Location |
|---|---|---|---|---|
| 1 | BL-001 | P1 | Device-asserted session times: a forward-dated start or back-dated end lowers bills and still passes server re-pricing | `supabase/schemas/public/functions/op_session_start.sql:16`, `op_session_end.sql:27` |
| 2 | NG-001 | P1 | Stored XSS (staff name → Leaflet tooltip `innerHTML`) → owner session takeover | `apps/admin/src/app/shared/map/geo-map.ts:199`, `features/attendance/components/punch-map.ts:20` |
| 3 | DEP-001 | P1 | Squashed migrations vs. the hosted history (36 old versions applied); the runbook is stale, and the obvious recovery (`db reset --linked`) destroys data | `supabase/migrations/`, `docs/DEPLOY_SUPABASE.md:107-191` |
| 4 | DEP-002 | P1 | No backup, PITR or restore test for the system of record for money | `docs/DEPLOY_SUPABASE.md:331` |
| 5 | DB-002 | P1 | Deleting a login cascades away leave, pay rates and finalised salary lines (or fails if punches exist), and the runbook tells operators to delete logins | `supabase/schemas/public/tables/staff_profiles.sql:27-28`, `salary_run_lines.sql:31` |
| 6 | ST-001 | P1 | Payroll can be finalised before the period ends; unworked days are frozen and later days are never paid | `supabase/schemas/public/functions/op_salary_run_finalise.sql:19-37` |
| 7 | SEC-002 | P2 | Hosted leftovers (service-role Edge Function) not verified | `docs/DEPLOY_SUPABASE.md:136-139` |
| 8 | FL-003 | P2 | Unsent takings are stranded on the device when a member's access is revoked | `apps/mobile/lib/app/sync/cloud_root.dart:490-495`, `supabase/schemas/private/functions/sync_push.sql:31-34` |
| 9 | NG-002 | P2 | Admin retries mint new ids, so an ambiguous network failure can duplicate payments or payroll adjustments | `apps/admin/src/app/core/sync/push-ops.ts:78` |
| 10 | FL-004 | P2 | Drift migration suite red (stale fixtures); the device upgrade path, which guards the only copy of the day's takings, has no passing coverage | `apps/mobile/test/data/local/migration_test.dart` |

## 5. Blockers before launch

1. **BL-001:** bound client timestamps against `statement_timestamp()`. Refuse future starts and ends, and refuse ends earlier than the server receipt minus an allowed offline window, or flag them for review. Record the server receipt time.
2. **NG-001:** pass text to Leaflet, not HTML (`bindTooltip` with a text node or escaped string). Add a CSP at the host.
3. **DEP-001:** decide how the hosted project gets onto the new history (repair the history or a fresh project), and rewrite the go-live runbook.
4. **DEP-002:** enable backups or PITR on the hosted plan, take a pre-push dump, and run one restore drill.
5. **DB-002:** replace `on delete cascade` from `staff_profiles` on staff-module tables with restrict, and change the runbook to "deactivate, never delete".
6. **ST-001:** refuse finalise (and warn on create) while `period_end >= IST today`. Alternatively, hide Payroll for launch.
7. **Hosted verification (§6):** confirm `staff-admin` is deleted, compare the hosted schema with `schemas/`, and check the Auth settings.
8. **FL-004:** fix the migration test fixtures and run the Drift migration suite green before shipping a build to devices.

## 6. Unverified critical controls (NEEDS VERIFICATION, outside the repo)

* The hosted project: deployed Edge Functions, leftover SQL objects, migration list, Auth settings (confirmations, redirect URLs, OTP expiry, leaked-password protection, CAPTCHA), Realtime public-access setting, role `statement_timeout`, and backup/PITR.
* Admin hosting: headers, CSP, HSTS, SPA fallback for `/accept-invite`.
* Runtime behaviour: whether GoTrue revokes other sessions on a password change, Realtime DELETE event payloads, and `EXPLAIN` timings of `sync_pull` and `arena_overview` at production volume.
* Test suites were **not run** (pgTAP was blocked because the Docker daemon was not responding; Flutter and admin unit tests were not requested by the lean-mode rules). "Existing tests pass" is not established.

## 7. Report index

| File | Content |
|---|---|
| `01-security-audit.md` | Auth, authorization, RLS, tenant isolation, secrets, realtime, storage (SEC-001…012) |
| `02-supabase-database-audit.md` | Schema, migrations, constraints, indexes, query cost, integrity (DB-001…016) |
| `03-angular-audit.md` | Admin security, architecture, async, performance (NG-001…011) |
| `04-flutter-audit.md` | Mobile security, sync, lifecycle, Drift, performance (FL-001…017) |
| `05-business-logic-audit.md` | Part A, floor and money (BL-001…012); Part B, staff module (ST-001…017) |
| `06-dependencies-devops.md` | Dependencies, CI/CD, config, release and operations (DEP-001…015) |
| `07-code-quality.md` | Cross-cutting maintainability, test-suite assessment, per-app notes (CQ-001…012) |
| `08-production-checklist.md` | Launch checklist (PASS / FAIL / NEEDS VERIFICATION / N/A) |
| `09-remediation-roadmap.md` | Prioritised fix plan |
