# Production Launch Checklist

Status values: **PASS** · **FAIL** · **NEEDS VERIFICATION** · **NOT APPLICABLE**. Evidence cites repo paths or finding IDs from the other reports. Nothing outside the repo was inspected, so every hosted-project item is NEEDS VERIFICATION unless the repo proves otherwise.

## Security — tenant isolation and authorization

| # | Item | Status | Evidence |
|---|---|---|---|
| S1 | `anon` reaches no table, view, function or sequence | PASS | Every schema file ends with `revoke … from anon`; asserted by `supabase/tests/13_security_hardening_test.sql` (01 §Controls) |
| S2 | No public SECURITY DEFINER function is client-executable | PASS | Client API = 25 invoker wrappers, allow-list at `13_security_hardening_test.sql:89-97` |
| S3 | All definer functions pin `search_path` | PASS | 01 §Controls |
| S4 | RLS on every table; no client write policies | PASS | Select-only policies, writes via `sync_push` → `op_*` with `_need` (01) |
| S5 | Cross-arena writes impossible | PASS | `arena_id = p_arena` lookups in `op_*`, plus `_assert_same_arena` triggers on 30 tables (01, 02) |
| S6 | Cross-arena reads impossible | PASS (static) | RLS through `private.app_arena_ids*`; no runtime A-vs-B sweep exists (07 test gaps) |
| S7 | Least privilege inside an arena | FAIL | SEC-001: any member can pull every customer and payment through `sync_pull` |
| S8 | No self-dealing on own records | FAIL | SEC-003: `op_leave_adjust`, `op_pay_rate_add`, `op_salary_adjustment_add`, `op_hr_profile_save`, `op_salary_run_set_deduction` skip `_own_record` |
| S9 | Nobody changes their own permissions; owner-level permissions only granted by owner level | PASS | `op_staff_update` (01) |
| S10 | Invitation flow safe (hashed single-use token, confirmed e-mail match) | PASS | 01 §Controls; P3 caveats SEC-005 and SEC-006 |
| S11 | Deactivated or removed members lose access | PASS (static) | `sync_push.sql:31-34` refuses non-members; Realtime access lasts up to the JWT expiry (documented) |
| S12 | No XSS sink in the admin | **FAIL** | NG-001: `apps/admin/src/app/shared/map/geo-map.ts:199` `bindTooltip(string)` → Leaflet `innerHTML` |
| S13 | CSV export formula injection neutralised | PASS | `textCell` used by all three exporters (03 §Controls) |
| S14 | No open redirect in auth flows | PASS | `safeNext` (03, 01) |
| S15 | Content-Security-Policy / security headers | FAIL | NG-003 / DEP-004: none in `index.html`, and no hosting config in the repo |
| S16 | No service-role or secret key in clients or git history | PASS | 3,655 git objects scanned (06); build refuses secret keys (`core/supabase/supabase.ts` configProblem, `AppConfig.problemFor`) |
| S17 | Hosted project free of removed objects (`staff-admin` Edge Function with service-role key) | NEEDS VERIFICATION | SEC-002; `docs/DEPLOY_SUPABASE.md:136-139` |
| S18 | Auth bot protection (CAPTCHA) on sign-up, OTP and reset | FAIL | SEC-004: neither app sends a CAPTCHA token; `supabase/config.toml:205` |
| S19 | Hosted Auth settings match policy (confirmations, redirect URLs, OTP expiry, leaked-password check) | NEEDS VERIFICATION | SEC-012, DEP-013 |
| S20 | Realtime channels authorised per arena | PASS (static) / NEEDS VERIFICATION (runtime) | `supabase/schemas/realtime/policies.sql`; SEC-008: members can broadcast, DELETE events may leak PKs |
| S21 | Storage buckets and policies | NOT APPLICABLE | No buckets defined (01) |
| S22 | Edge Functions | NOT APPLICABLE (repo) / NEEDS VERIFICATION (hosted) | None in the repo; see S17 |
| S23 | Mobile tokens in the platform keystore | PASS | `apps/mobile/lib/app/sync/secure_session_storage.dart` (04) |
| S24 | Device data not exported to personal cloud backups | FAIL | FL-005 / DEP-006: `allowBackup` default true, `AndroidManifest.xml:17-21` |
| S25 | Release builds refuse local or dev backends and secret keys | PASS | Gradle gate plus `AppConfig.problemFor` (04 §Controls) |

## Data integrity and business logic

| # | Item | Status | Evidence |
|---|---|---|---|
| D1 | Money in integer paise / exact numeric, rounded once | PASS | 02, 05 (no floats in SQL money; admin parsing string-exact, except NG-006 display rounding) |
| D2 | Server re-prices bills, extensions and discounts; forged price lists refused | PASS | 05 Part A invariants table |
| D3 | Session times authoritative | **FAIL** | BL-001: `op_session_start.sql:16`, `op_session_end.sql:27` take `started_at` / `ended_at` from the client, unbounded |
| D4 | Ops idempotent per op id; payments unique | PASS | `sync_ops` replay, payment id PK (02, 05) |
| D5 | Client retries reuse ids | FAIL | NG-002: admin mints new op and payment ids per attempt |
| D6 | One open segment per station; one open allocation per pad; one open clock-in per person | PASS | Unique partial indexes and locks (02, 05) |
| D7 | Payments cannot overpay; refunds ≤ collected; void blocks payments; locked parent rows | PASS | 05 Part A |
| D8 | Money tables append-only | PASS (clients) / FAIL (defence in depth) | No client write grants; DB-004: cascades and no guard trigger |
| D9 | Voids need a reason and are audited | PASS | 05 Part A |
| D10 | Waive and discount caps enforced on the server | FAIL | BL-003: waive is uncapped, reason optional |
| D11 | Unpriced or unoffered activity refused | FAIL | BL-002 |
| D12 | Booking vs live-session conflict on the server | FAIL | BL-005 (device-only) |
| D13 | IST day boundaries correct in reports | PASS | 05 Part A, 03 (no browser-local date maths) |
| D14 | Punch time server-stamped; punching only for oneself | PASS | 05 Part B invariants |
| D15 | Geofence trustworthy | FAIL (documented limitation) | ST-009: position and mock flag are self-reported |
| D16 | Payroll period lock correct | **FAIL** | ST-001 (finalise before period end), DB-006 (check-then-act race), ST-010 (pending reviews ignored) |
| D17 | Leave balance concurrency | FAIL | DB-007 |
| D18 | Staff history survives member removal | **FAIL** | DB-002 |
| D19 | Audit trail for permission, price and pay changes | FAIL | DB-009 |

## Reliability

| # | Item | Status | Evidence |
|---|---|---|---|
| R1 | Outbox recovers from poison or oversized batches | FAIL | FL-001 / DB-008: no attempt cap, batch shrink or dead-letter |
| R2 | Unsent money survives access revocation | FAIL | FL-003 |
| R3 | Device DB backed up before migration | PASS | `DbSafety.protect` (04 §Controls) |
| R4 | Drift upgrade path verified | **FAIL** | FL-004 / CQ-001: migration suite red, no v16→v17 case |
| R5 | First sync bounded at scale | NEEDS VERIFICATION | DB-005: `sync_pull` quadratic paging; FL-002: full pull with `limit: 100000` |
| R6 | Admin stores clear on sign-out or arena switch; stale responses dropped | PASS | 03 §Controls |
| R7 | Floor device data cleared or isolated per login | PASS (isolated) / FAIL (retention) | One DB file per (arena, user) (04); data kept after revoke (SEC-010) |

## Operations

| # | Item | Status | Evidence |
|---|---|---|---|
| O1 | Crash reporting in production (mobile) | FAIL | DEP-005: `dart_define.prod.json` in `docs/RELEASE.md:102` omits `AO_SENTRY_DSN`; FL-006 sample rates |
| O2 | Error reporting (admin) | FAIL | None (DEP-005) |
| O3 | Database backups / PITR enabled | NEEDS VERIFICATION (treated as FAIL) | DEP-002, `docs/DEPLOY_SUPABASE.md:331` |
| O4 | Restore tested | FAIL | No drill documented (DEP-002) |
| O5 | Migration rollback plan | FAIL | DEP-008: forward-only; one migration drops data |
| O6 | Hosted migration path valid | **FAIL** | DEP-001 |
| O7 | Separate production and staging projects | FAIL | DEP-007: `environment.production.ts:17-18` points at the dev project |
| O8 | CI gating merges and releases | FAIL | DEP-003: no CI; `verify_all.sh` manual |
| O9 | Admin hosting defined (headers, SPA fallback, caching) | NEEDS VERIFICATION | DEP-004 |
| O10 | Versioning and release tagging | FAIL (P3) | DEP-009 |
| O11 | Dependency vulnerabilities (npm) | PASS | `npm audit`: 0 known (06) |
| O12 | Dependency vulnerabilities (Dart) | NEEDS VERIFICATION | No advisory DB checked; `flutter_local_notifications` 19.5 vs 22.3 (DEP-012) |
| O13 | Lockfiles consistent | PASS (P3 note) | npm and pnpm lockfiles agree; pnpm redundant (DEP-010) |

## Quality gates

| # | Item | Status | Evidence |
|---|---|---|---|
| Q1 | `flutter analyze` clean | PASS | "No issues found!" (04) |
| Q2 | Admin production build compiles | PASS | `npm run build` OK, 6.3 s (03) |
| Q3 | Admin bundle budget | FAIL | 790 kB initial vs the 500 kB budget; cause NG-004 (`realtime-sync.ts` pulls 15 stores eagerly) |
| Q4 | pgTAP suite green | NEEDS VERIFICATION | Not run: local Docker daemon not responding |
| Q5 | Flutter tests green | FAIL (known) | Drift migration tests fail on HEAD (CLAUDE.md; FL-004) |
| Q6 | Admin specs green | FAIL (known) | 7 known failures (CLAUDE.md), probably more (CQ-002) |
| Q7 | Pricing parity, including overtime grace | NEEDS VERIFICATION | Not run; BL-004: grace path never exercised |
| Q8 | Cross-device sync (`tool/sync_it.sh`) and real two-phone test | NEEDS VERIFICATION | Not run; `docs/SYNC.md:480-485` |
| Q9 | Concurrency scripts cover money and payroll races | FAIL | Only station and pad races exist (02, 07) |
