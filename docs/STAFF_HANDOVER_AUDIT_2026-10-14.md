# Staff handover audit — 2026-10-14

Question: is 404 Arena safe and practical to hand to floor staff for real daily billing, with
an owner dashboard whose sales, history and exports can be trusted?

Status of this document: **final**. §0–§5 are the findings as written before any change (kept
as found); §6–§12 record what was fixed, the evidence after the fixes, what remains, and the
verdict. Nothing was committed, pushed or deployed.

**Verdict: BLOCKED — EXTERNAL SETUP OR REAL-DEVICE VERIFICATION REQUIRED** (§12). The code
defects found in this audit are fixed and tested on the local stack; the hosted backend the
release app talks to cannot yet run invitations, the owner's Sales screen or this audit's
corrections, there is no signing key for an installable release, and nothing has been tried on
a real counter device.

## 0. How this audit was done

* Read the repository rules first (`CLAUDE.md`, `apps/admin/CLAUDE.md`, `docs/PLAN.md`,
  `docs/OWNER_CONFIRMATION.md`, `docs/RELEASE.md`, `docs/DEPLOY_SUPABASE.md`, `docs/SYNC.md`,
  `supabase/README.md`) and the two earlier reports of today
  (`COMPLETION_AUDIT_2026-10-14.md`, `STAFF_LOGIN_REPAIR_2026-10-14.md`). Their claims were
  re-checked against the code, not taken as evidence. There is no `AGENTS.md`,
  `ARCHITECTURE.md` or `ENGINEERING_STANDARDS.md` in this repository.
* Traced the code path for every requirement (staff app → action → repository → outbox →
  `sync_push` → `op_*` → tables → `arena_sales` / `arena_sale` → dashboard).
* Ran every automated suite on the local stack (§1).
* Hosted project: **read-only** checks only (`supabase migration list --linked`,
  `supabase functions list`, unauthenticated HTTP probes that can execute nothing). Nothing was
  pushed, deployed or changed on hosted.
* **Manual / visual testing was not done by me.** `CLAUDE.md` reserves it for the user ("Do not
  do manual or visual testing yourself … hand over the route/screen and a short checklist").
  Every requirement that needs eyes on a screen or a real device is marked NOT VERIFIED and
  appears in the hand-over checklist (§11).
* No spreadsheet screenshot was attached to the request and none exists in the repository. The
  Google Sheets mapping (§3) uses the column list given in the request.
* The environment had other agent sessions working in the same checkout and on the same local
  stack (a second `tool/sync_it.sh` run held the stack's lock during my baseline). Their
  uncommitted work was left untouched.

Classification: **PASS** verified with evidence · **FAIL** reproducible defect · **BLOCKED**
needs credentials, hosted configuration, hardware or an operator · **NOT VERIFIED** not enough
evidence. Severity: Critical / High / Medium / Low.

## 1. Baseline (before any change)

`bash tool/verify_all.sh --with-it` on the local stack, 2026-10-14 15:2x IST:

| Step | Result |
|---|---|
| 1 `flutter analyze` | PASS — No issues found |
| 2 `flutter test` | PASS — 753 passed, 31 skipped (live specs that run only inside `tool/sync_it.sh`) |
| 3 admin unit tests (`ng test`) | PASS — 238 passed, 3 skipped (live specs) |
| 4 admin build (development) | PASS |
| 5 pgTAP `supabase test db --local` | PASS — 17 files, 920 tests |
| 6 `supabase db advisors --local --type all` | PASS — no findings |
| 7 cross-app integration (`tool/sync_it.sh`) | **did not run**: another session's `sync_it.sh` (pid 81460) held the stack's run lock. Re-run in §7. |
| 8–9 pricing parity, concurrency races | SKIP (opt-in `--with-psql`; they use `docker exec psql`, which the user does not want run ad hoc) |

Hosted (read-only, 2026-10-14):

| Check | Result |
|---|---|
| `supabase migration list --linked` | hosted has `0001`–`0016`; the **20** migrations after `0016` (`20261011202706` … `20261014065708`) are **not applied** |
| `supabase functions list` | **no Edge Functions deployed** (`staff-admin` absent) |
| unauthenticated POST `/functions/v1/staff-admin` | 404 |
| unauthenticated POST `/rest/v1/rpc/{accept_invite, invite_member, arena_sales, arena_sale}` | 404 (functions do not exist there) |
| unauthenticated POST `/rest/v1/rpc/my_arenas` | 401 (exists, refuses anon) |

## 2. Findings

### 2.1 Staff app — billing workflow (§3 of the request)

| ID | Requirement | Status | Sev | Evidence |
|---|---|---|---|---|
| S1 | Secure sign-in (invited login, per-person session, revocation) | PASS | — | `apps/mobile/test/sync/staff_login_test.dart` (9 real-server tests, run inside `sync_it.sh`); `test/app/sync/staff_access_test.dart` |
| S2 | Select an available, compatible station | PASS | — | `AvailabilityService`, compatibility matrix; server `assert_resource_free_for_segment` + `ux_one_open_segment_per_resource`; offline double-booking refused (`two_device_sync_test.dart` "offline conflict: both devices take RIFT") |
| S3 | Game, controller configuration, pricing | PASS | — | New Session flow; pricing snapshot frozen at start and checked by `_assert_snapshot` (pgTAP 08) |
| S4 | Server-authoritative start time | **PARTIAL — by design** | Medium | Offline-first: the device stamps `started_at`; `sessions.started_at` is documented "device-reported … the server validates only their order" (`supabase/schemas/public/tables/sessions.sql`). In cloud mode the device follows server time once it is more than 2 min off (`OffsetClock`, `cloud_root.dart` `_applyClockOffset`; offset measured on every pull from `server_time`) and shows "Tablet clock is wrong. Timers use server time." The server also records its own receipt time (`created_at`, `sync_ops.created_at`). There is **no server-side bound** on device times (a start in the future is accepted). See F-TIME in §9. |
| S5 | Live timer and running estimate | PASS | — | Timers derive from stored timestamps (`SessionTimer`); live estimate `SessionActions.liveBill`; timer tests |
| S6 | Switch station / game / controllers keeping history | PASS | — | Segments: one closes, the next opens at the same instant; pgTAP 07/11; segment billing tests |
| S7 | Stop / complete | PASS | — | `op_session_end` (pgTAP 07, 08, 11) |
| S8 | Backend calculates the final amount | PASS | — | The device prices; the server re-prices from the stored segments on the frozen snapshot and refuses any difference (0 paise tolerance, `price_mismatch`) — pgTAP 08 |
| S9 | Payments by method (cash, UPI/GPay, card, other) | PASS | — | `payments.method` check; floor options choose which are offered; split = several append-only rows |
| S10 | Expected, collected, outstanding shown | PASS | — | End sheet and Take payment sheet show bill, already collected, due / change; awaiting-payment queue |
| S11 | Completed session appears in the day's sales | PASS (local) | — | `tool/sync_it.sh` phase 5 (staff bill on the owner's Sales list with exactly one payment), per the earlier reports; re-run in §7 |
| S12 | Partial payments, multiple methods | PASS | — | `payment_rules.dart` tests; pgTAP 10 (overpayment, refund limits) |
| S13 | Happy-hour pricing and rounding | PASS | — | `test/domain/pricing/*` (band split at the boundary, rounding), pgTAP 08 (same rules on the server) |
| S14 | Discounts | NOT IMPLEMENTED — owner decision | — | `OWNER_CONFIRMATION.md` #21; only a whole-bill waive exists |
| S15 | Interruptions / restart | PASS | — | Timers from timestamps; `DbSafety.protect` backup before migrations; `staff_login_test` restart; `two_device_sync_test` "ops survive a restart" |
| S16 | Offline operation, reconnection, duplicate submissions | PASS | — | Outbox + `sync_push` op-id replay (pgTAP 07); "a payment retried after a lost response is recorded once"; payment primary key = device id |
| S17 | Waive (complimentary) records a reason and an audit entry | **FAIL** | Medium | The end sheets have a "Waive" switch and no reason (`end_session_sheet.dart`, `group_end_sheet.dart`); `op_session_end` / `op_group_end` write no `audit_log` row. A written-off bill leaves no reason and no record of the amount written off. |
| S18 | Refunds | **FAIL** | High | No screen in either app records a refund: nothing in `apps/mobile/lib/features` passes `isRefund: true`, and the dashboard only sends `session.void` / `group.void`. The server supports refunds (`payment.record`, reason required) but no one can reach it. |
| S19 | Pending (not yet synced) work distinguished from confirmed | PASS (app-wide), Low gap | Low | One status strip on Floor/Today/Money/Reports ("N saved here, not sent yet", "N need attention") and the Sync screen list each waiting/refused op. No per-row badge on station cards or the awaiting-payment list. |
| S20 | Logout / account switch does not leak data | PASS | — | Device DB file per (arena, person) (`staff_access.dart` `cloudDbPath`); `staff_login_test` "another login on this device gets its own file" |
| S21 | Mobile-sized screens, a realistic staff session on a device | NOT VERIFIED | — | Widget tests cover phone and desktop sizes; no human or device run in this audit (§11) |

### 2.2 Owner dashboard — sales, history, corrections (§5)

| ID | Requirement | Status | Sev | Evidence |
|---|---|---|---|---|
| D1 | Today's sessions and sales | PASS | — | `features/sales`; `arena_sales` (pgTAP 14); sales spec |
| D2 | Filter by date / date range; previous days | **FAIL** | High | Only four chips: Today, Yesterday, 7 days, 30 days (`sale.models.ts` `SALES_RANGES`). No custom range, no way to open a specific earlier day or anything older than 30 days, though the server accepts any 93-day window. |
| D3 | Session detail and payment breakdown | PASS, Low gaps | Low | `bill-detail.ts`: lines, payments (method, time, staff), collected, due. Dropped although the server sends them: segment start/end times, extensions (with reason and who), payment/refund reasons and notes; void shows the date only. |
| D4 | Distinguish expected revenue, collected, outstanding, refunds/adjustments | **FAIL** | High | The summary line shows takings (= collected), per method, due and "on voided bills". There is **no expected (billed) total, no refunds total, no written-off (waived) total** (`summarize`, `summaryLine`). Metric meanings are not stated anywhere on screen. |
| D5 | No double counting; session revenue vs payments received | PASS with notes | Medium | Singles and groups come from separate tables (`union all`), refunds are negative rows counted once. But: (a) with a method chip on, the headline "takings" still includes the other methods of split bills (sales spec: Cash chip shows "₹780 · … · UPI ₹500 · Cash ₹280") — **FAIL, Low**; (b) payments are attributed to the day the **bill closed**, not the day they were received (`_sales.sql`), so a late payment changes that earlier day's collected figure. That is the spreadsheet's meaning too (cash/GPay per session row) but it is not stated. |
| D6 | Search sessions and customers | PASS (bills) | Low | Bill ref, member name, staff, station, game. Not by phone (sales data has no phone, deliberately). Members page lists customers. |
| D7 | Correct authorised historical records with a reason | **FAIL** | High | The only correction is a whole-bill void. Payment method recorded wrongly (cash tapped as UPI), a late payment, or a partial refund cannot be fixed from the dashboard; refunds cannot be recorded anywhere (S18). After a void, the money already collected can **never** be refunded: `op_payment` raises `voided` for refunds too. |
| D8 | Who made each correction, when, original vs updated | **FAIL** | Medium | `audit_log` has only `void` and `duplicate_phone_on_sync` rows; `arena_sale` returns only the first void record (who/when, no time on screen). No history view. |
| D9 | Reason required for financial changes | **FAIL** | Medium | `op_session_void` / `op_group_void` store `p->>'reason'` without checking it: a void with no reason is accepted (the dashboard always sends one, any other client need not). Waive: no reason at all (S17). |
| D10 | Ordinary staff cannot change historical financial records | PASS | — | Void is owner level on the server (`app_is_owner`); no op edits a closed session or a payment; tables have no client write policy (pgTAP 01, 13) |
| D11 | Refresh / recover after a connection interruption | PASS, Low gap | Low | Realtime rejoin and the browser `online` event refresh every store (`realtime-sync.ts`, unit-tested). No manual refresh button; "Today" does not roll over at midnight until something reloads. |
| D12 | Flutter changes reflected on the dashboard | PASS (local) | — | Realtime private channel nudges + reload; `sync_it.sh` phase 3 (floor change reaches the dashboard live) |
| D13 | Export historical and current reports | **FAIL** | High | One CSV (`sales-csv.ts`): no arena/range/timezone/generation time, no per-method columns (cash vs UPI per row is the core of the spreadsheet), no refunds, no outstanding, no who/when of a void, no payments ledger, no totals row, ranges limited as in D2. |
| D14 | Export safety | **FAIL** | Medium | Cells are only quoted for `" , \n`. A member name typed by staff such as `=HYPERLINK(...)` or `+cmd|...` is exported live into Excel/Sheets (CSV formula injection). |
| D15 | Export respects arena isolation and permission | PASS | — | Built only from `arena_sales` (owner level, arena checked server-side; pgTAP 14; IT phase 5 "another arena's owner sees nothing") |
| D16 | Exported totals match the database | NOT VERIFIED | — | No test compares an export with the ledger. Added in §6.2. |
| D17 | Offline / uncommitted values never exported as confirmed | PASS | — | The dashboard reads only server rows; device-only work is not on the server until `sync_push` applies it |
| D18 | Dashboard error monitoring | NOT IMPLEMENTED | Low | No error reporting in `apps/admin` (the staff app has Sentry) |

### 2.3 Historical integrity (§7)

| ID | Case | Status | Evidence |
|---|---|---|---|
| H1 | Pricing changes after the session | PASS | Snapshot frozen at start; bill re-priced from it; a start against a catalog older than 72 h is refused (pgTAP 08, `_assert_snapshot`) |
| H2 | Edited after completion | PASS (by refusal) | No op edits a completed session (end/extend/reconfigure require `active`) |
| H3 | Late payment | PASS with note | Recorded as a new row with server time; bill status recomputed; the closed day's collected figure moves (D5b) |
| H4 | Refund / correction recorded | **FAIL** | No UI (S18, D7); refunds impossible after a void |
| H5 | Completed offline, synced later | PASS | Outbox replay; bill dated by the device's end time |
| H6 | Same request retried | PASS | `sync_ops` op-id replay; payment id is the primary key (pgTAP 07; two-device test) |
| H7 | Reconnect / restart | PASS | `staff_login_test` restart; "ops survive a restart" |
| H8 | Group end time order | Low | `group_sessions` lacks the `actual_ended_at >= started_at` check that `sessions` has (the op checks it) |

### 2.4 Invitations (§8)

| ID | Item | Status | Evidence |
|---|---|---|---|
| I1 | `{"message":"name resolution failed"}` root cause | PASS (root cause confirmed) | The text comes from the local API gateway (Kong), not from `staff-admin` (every error the function returns is `{error, message}`). Kong answers it when the `supabase_edge_runtime_arena_ops` container is gone. Any `supabase functions serve` that exits removes that container, and `supabase start` on a running stack does not recreate it. Fixed earlier today by `supabase stop && supabase start` and by `tool/sync_it.sh` reusing the stack's runtime. Now: the container is up and the gateway answers the function's own `401 {"error":"unauthorized"}` without a session. |
| I2 | Documentation that would bring the failure back | **FAIL** | Low | `docs/COMPLETION_AUDIT_2026-10-14.md` §9 "Manual check" heading tells the reader to run `supabase functions serve` — the exact trigger. |
| I3 | Authorization, arena membership, one-time use, 7-day expiry, confirmed matching login | PASS (local) | pgTAP 17; `tool/it_invitations.sh` (31 checks over HTTP: 401/403/400 cases, 200 sent with 7-day expiry, re-invite replaces, mail catcher down → 502 and nothing pending, database API down → 503) |
| I4 | Hosted invitations | **BLOCKED** | Hosted has no `staff-admin` function and none of `invite_member` / `accept_invite` (§1). Needs the operator's push + deploy + Auth SMTP. |

### 2.5 Offline, realtime, isolation (§9)

| ID | Item | Status | Evidence |
|---|---|---|---|
| R1 | Offline sessions sync after reconnection; no duplicates | PASS | §2.1 S16, H5, H6 |
| R2 | Concurrent staff actions do not corrupt money | PASS | Parent row locked in `op_payment` (0016); overpayment / refund limits (pgTAP 10); concurrency scripts exist (not run here: `--with-psql`) |
| R3 | Dashboard refresh returns persisted values | PASS | Every screen reads RPCs/RLS views; no client cache survives a reload |
| R4 | Realtime cannot expose another arena | PASS | Private channel `arena:<uuid>`, `private.can_use_arena_topic` (pgTAP 18; `cross_app_test` "another arena cannot read or write this one"). A revoked member keeps the socket until the token refreshes (≤ 1 h); nudges carry no business data. |
| R5 | Device feed scope | NOT CHANGED — product decision | `sync_pull` sends payments and customers to every active member's device (documented open item, `DEPLOY_SUPABASE.md` §1) |

### 2.6 Production readiness (§11)

| ID | Item | Status | Evidence |
|---|---|---|---|
| P1 | Hosted migrations and schema | **BLOCKED** | 20 migrations not applied on hosted (§1) |
| P2 | Production URLs / variables | **BLOCKED** | `dart_define.prod.json` (git-ignored, present) points the release build at the hosted project called "development" in `DEPLOY_SUPABASE.md`, with an anon (publishable) key and `AO_ENVIRONMENT=production`. Dashboard `environment.production.ts` URL and key are empty (production build shows "Setup needed"). |
| P3 | E-mail provider for invitations | **BLOCKED** | Hosted Auth custom SMTP not configured by the operator (built-in sender only reaches team members) |
| P4 | Production auth and RLS | PASS (local) / BLOCKED (hosted) | pgTAP 01, 13, 17, 18 + advisors clean locally; hosted lacks the hardening migrations |
| P5 | Android signing | **BLOCKED** | `apps/mobile/android/key.properties` absent; Gradle refuses a release without it (`build.gradle.kts`) |
| P6 | iOS signing | **BLOCKED** | No `DEVELOPMENT_TEAM` in `ios/Runner.xcodeproj` (automatic signing, no team) |
| P7 | Error monitoring, scrubbing | PASS (staff app, config) / NOT VERIFIED (delivery) | `core/monitoring/sentry_setup.dart`: `sendDefaultPii = false`, all text and images masked in Session Replay, credential screens pause replay, unit-tested (`test/core/monitoring/*`). Production samples 10% of sessions for replay. Delivery to Sentry not checked. Dashboard: none (D18). |
| P8 | Backup / recovery | PASS (device) / NOT VERIFIED (hosted) | Device: `DbSafety` verified backup before migrations (`RELEASE.md` §1). Hosted: plan-dependent; not checked |
| P9 | Real-device installation and operation | NOT VERIFIED | Needs the operator (§11) |
| P10 | No debug auth, demo PINs or insecure fallback in release | PASS | `AppConfig.problemFor`: release refuses local mode, a missing/non-https/development URL and secret/service-role keys; Gradle refuses a release without `AO_BACKEND=supabase` (`app_config_test.dart`) |

## 3. Google Sheets session log → app (request §2, §4)

| Sheet column | Where it comes from | Entered / derived | Status |
|---|---|---|---|
| Business date | IST calendar date of the bill (`at`; hours cannot cross midnight, so start and close dates agree) | derived | PASS |
| Session number | — (bills have a UUID and a short ref `S-3F9A2C`; no per-day sequence) | — | GAP |
| Start time | `sessions.started_at` (device clock, server-corrected when > 2 min off) | automatic | PASS (S4 note) |
| Station | segments → `resources.name` | selected from configuration | PASS |
| Duration / hours | `actual_ended_at − started_at` | derived | PASS |
| Player count | group: `group_sessions.player_count`; single: largest controller count of its segments (no count for pool/lounge) | selected | PARTIAL |
| Player-hours | — | — | GAP |
| Most-played game | per bill: games in play order; per period: Overview "Top games" | from history | PASS |
| Games of interest | — (no data model) | — | GAP — owner decision |
| Repeat customer | customer profile shows visits; nothing on a bill or in reports ("new customers" only) | — | GAP |
| Customer name | `customers.name` (walk-ins get a per-visit "Walk-in" row) | entered / picked | PASS |
| Phone | `customers.phone` (optional; duplicate phone offers the existing member) | entered | PASS (kept out of sales exports, see §9) |
| Cash received | Σ cash payments − cash refunds of the bill | from the payments ledger | PASS (data) / FAIL (export, D13) |
| GPay / UPI received | Σ UPI payments − UPI refunds | from the ledger | PASS (data) / FAIL (export) |
| Total paid | net of the ledger | derived | PASS |
| Expected amount | `billed_amount_paise` (server re-priced) | derived | PASS (data) / FAIL (summary, D4) |
| Difference | expected − paid (due); zero when waived or voided | derived | PASS (detail) / FAIL (export) |
| Notes | payment note (Take payment sheet), customer notes; **no note on a session** | entered | PARTIAL — owner decision |
| Adjustments | waive (no reason), void (reason not enforced), refunds (no UI), method correction (none) | — | FAIL (S17, S18, D7, D9) |
| Session history | segments, extensions, payments | automatic | PASS (data) / Low gap (D3) |

## 4. Metric definitions (to be shown on the dashboard)

Bills are attributed to the IST day they **closed** (ended, or voided while running), like the
rows of the spreadsheet.

* **Expected** — Σ final bill of the bills that count (not voided), after cash rounding,
  including waived bills.
* **Collected** — Σ net payments (payments − refunds) on those bills, whenever received.
* **Outstanding** — Σ max(0, expected − collected) on bills not waived and not voided.
* **Written off** — Σ (expected − collected) on waived bills.
* **Refunded** — Σ refunds on those bills (already subtracted from collected).
* **On voided bills** — net collected on voided bills (a void never refunds; kept apart so the
  till reconciles).
* **Per method** — net per method on the bills that count; they add up to Collected.

## 5. Fix plan (in-scope, safe)

1. Server: a void needs a reason (`reason_required`); refunds allowed on a voided bill (never
   more than collected); a waive writes an audit entry with the amount written off and any
   reason; new owner-level op `payment.correct` (moves all or part of a payment to another
   method: an append-only refund + payment pair, one transaction, reason required, audited, no
   double correction); `_sales` adds per-bill player-minutes, a returning-customer flag and the
   payments ledger; `arena_sale` adds the full audit history.
2. Dashboard: any date or date range (≤ 93 days, IST); expected / collected / outstanding /
   written-off / refunded totals with their definitions; method filter totals fixed; refund,
   correct-method and record-payment actions with reasons; history section; segment times,
   extensions, reasons; refresh button and midnight roll-over; a proper report export (bills
   CSV with a header block, per-method columns, totals; payments ledger CSV) with formula-safe
   cells.
3. Staff app: a reason when waiving (sent with the end op).
4. Docs: remove the `functions serve` instruction (I2).
5. Tests for each, then the full suites and `tool/sync_it.sh`.

Not in scope (owner decisions, recorded in §9): per-session notes, games of interest, player
count for non-console activities, discounts / GST / invoice numbers, device feed scope.

## 6. Fixes made

All changes are uncommitted and sit on top of earlier sessions' uncommitted work in the same
checkout (several of these files already had their changes). Other agent sessions edited other
files during this audit (e.g. the staff app's `sync_engine.dart`, `sync_transport.dart`,
notifications); those are theirs and were not touched.

### 6.1 Backend (declarative schema → generated migrations, applied to the local stack only)

| Change | Files |
|---|---|
| A void needs a reason: trimmed, 1–500 characters (`void_reason_required`, `reason_too_long`); the trimmed reason is stored and audited. Fixes D9. | `schemas/public/functions/op_session_void.sql`, `op_group_void.sql` |
| Money taken before a void can be refunded (never more than collected); a voided bill still takes no new payment, now refused as `voided` before the balance check (was `overpayment`). Fixes D7 (refund after void), H4. | `op_payment.sql` |
| A waive writes `audit_log` (action `waive`: billed and paid before, amount written off, the staff reason when sent as `waive_reason`). Optional on the server so floor builds already installed still end sessions. Fixes S17 (server side). | `op_session_end.sql`, `op_group_end.sql` |
| New owner-level op `payment.correct` (`op_payment_correct`, server-only, Money permission): moves all or part of one payment to another method as an append-only refund + payment pair in one transaction, reason required, audited (before/after), never more than the payment (`already_corrected`, `amount_invalid`), `same_method`, `not_a_payment`, replay-safe through `sync_ops`. The bill's net and status never change. Fixes D7 (wrong method). | `op_payment_correct.sql` (new), `_sync_apply.sql` |
| `arena_sales` / `arena_sale` now return what the report needs: the payments ledger per bill (with `correction` flags), refunds excluding correction rows, returning-customer flag (earlier completed bill, never for walk-ins), player-minutes, who/when of the void, the server's receipt time of the start, and the bill's full audit history. Fixes D3, D8 and the data side of D13 and §3 gaps (repeat customer, player-hours). | `_sales.sql`, `private/functions/arena_sale.sql` |
| Documentation of the audit trail and payment tables | `tables/audit_log.sql`, `tables/payments.sql`, `tables/group_payments.sql` |
| Generated migrations (read before applying; no client grants; drift check "No schema changes found" after each) | `migrations/20261014102347_sales_corrections_and_audit.sql`, `20261014102752_payment_voided_before_balance.sql`, `20261014105230_sales_correction_rows_not_refunds.sql` |

### 6.2 Owner dashboard (`apps/admin/src/app`)

| Change | Files |
|---|---|
| Any IST date or date range (up to 93 days, the server's limit) through **Dates…** with From/To pickers, in the URL (`?range=custom&from=…&to=…`); a backwards or too-long range is refused with a message; a crafted invalid URL falls back to today. "Today" (and 7/30 days) move to the new day at midnight IST. Fixes D2, D11 (roll-over). | `features/sales/data/sale.models.ts` (`periodFor`, `periodBounds`, `periodProblem`), `sales-page.ts`, `shared/time/ist.ts` |
| Totals with stated meanings: **Expected / Collected / Outstanding**, then per method, Refunded, Written off, Overpaid and "on voided bills", plus a "What these totals mean" note. Identity tested: expected + overpaid = collected + outstanding + written off. With a method chip on, the line says "N bills paid by Cash · Cash ₹X · UPI ₹Y" instead of passing the whole bill off as that method. Fixes D4, D5a. | `sale.models.ts` (`summarize`, `summaryLine`), `sales-page.ts` |
| Refresh button (also recovers a list whose last load failed); the store refreshes after a failed load too. Fixes D11. | `sales-page.ts`, `data/sales-store.ts` |
| Bill detail: start and end, segment lines with their times, player-hours, member type (Walk-in / New / Returning), "reached the server" when a start synced late, extensions with reasons, payment notes and reasons, correction rows named as such, void with date **and time**, and a **History** section (void, waive, payment moved: who, when, why, amounts). Fixes D3, D8. | `components/bill-detail.ts` |
| **Record payment** (late payment, at most what is due), **Refund** (reason required, at most collected, allowed on a voided bill), **Correct method** (pick the payment, the right method, all or part, reason required). Buttons appear only for the permissions the server checks (Bill; Bill + Give discounts; Money). Fixes D7. | `dialogs/money-dialog.ts` (new), `data/sales-api.ts`, `data/sales-store.ts` |
| Void dialog: "Other…" with a written reason; tells the owner to record a refund if money goes back. | `dialogs/void-dialog.ts` |
| Exports (menu **Export**): **Bills report** and **Payments ledger** CSV. Header block: arena, period, time zone, generation time (IST and UTC), generated by, filters, definitions. Bills report: business date, No. (per day, start order), bill ref and ID, type, start/end, minutes/hours, stations, activities, games, players, player-hours, customer, customer type, bill amount, expected, cash / UPI / card / other, collected, refunded, outstanding, written off, status, void reason/by/at, started by, recorded on server; then totals for the bills that count and for voided bills. Payments ledger: every payment/refund/correction row with received date/time, bill, method, kind, amount, reason, note, recorded by, UTC time; then net per method and total. Text cells are formula-safe (leading `= + - @` tab/return get an apostrophe); UTF-8 BOM for ₹. Fixes D13, D14. | `components/sales-csv.ts` |
| Sample API and specs for all of the above | `data/sales-api.sample.ts`, `sales-page.spec.ts`, `core/layout/shell.spec.ts` |
| Live check on the real local stack (inside `tool/sync_it.sh`): a reason-less void is refused; the floor's payment is moved to another method and ₹1 refunded through the server; a second move is refused; refunds exclude the correction; History shows the move; **both exports reconcile with the payment rows read from the database through RLS** (bill totals = ledger net = database; per method). Fixes D16. | `src/integration/dashboard-phase2.it.spec.ts` |

### 6.3 Staff app (`apps/mobile`)

| Change | Files |
|---|---|
| Waiving needs a reason: a "Reason for waiving" field appears with the Waive switch and End stays disabled until it is filled (single and group end sheets); the action layer refuses a waive without one (`waive_reason_required`, permission check first); the reason goes to the server in the end op (`waive_reason`). Fixes S17. | `domain/repositories/commands.dart`, `group_commands.dart`, `domain/services/payment_rules.dart`, `app/controllers/session_actions.dart`, `group_session_actions.dart`, `data/local/local_session_repository.dart`, `local_group_session_repository.dart`, `features/floor/presentation/sheets/end_session_sheet.dart`, `features/group_sessions/presentation/sheets/group_end_sheet.dart` |
| Tests | `test/app/waive_reason_test.dart` (new), `test/features/floor/end_sheet_payment_test.dart`, `test/integration/group_session_flow_test.dart`, `test/app/permissions_test.dart` |

### 6.4 Documentation

`docs/COMPLETION_AUDIT_2026-10-14.md` (the manual check no longer tells the reader to run
`supabase functions serve` — fixes I2), `docs/DEPLOY_SUPABASE.md` §4a (hosted state verified
read-only: `0016` is already applied; items 22–24 added), `docs/SYNC.md` (money rules),
`supabase/README.md` (corrections, op map, test 22).

## 7. Test results after the fixes (all executed and read; local stack only)

| Suite | Command | Result |
|---|---|---|
| Flutter analyze | `flutter analyze` (via `verify_all.sh`) | PASS — No issues found |
| Flutter tests | `flutter test` (via `verify_all.sh`) | PASS — 778 passed, 31 skipped (live specs that run inside `sync_it.sh`); baseline 753 |
| Dashboard unit | `npx ng test --watch=false` (run alone, 16:40 IST) | PASS — 254 passed, 4 skipped (the 4 live specs, incl. the new one); baseline 238 |
| Dashboard unit inside `verify_all.sh` | same, while other sessions loaded the machine (load average 159) | FAIL — 32 tests in 12 files hit the 5 s timeout; every failure was `Test timed out`, no assertion failed. The run alone right after passed (row above). Reported, not hidden. |
| Dashboard build | `ng build --configuration development` | PASS |
| pgTAP | `supabase test db --local` | PASS — 18 files, 990 tests (baseline 920; the new file 22 adds 70) |
| Advisors | `supabase db advisors --local --type all` | PASS — no findings |
| Declarative drift | `supabase db schema declarative sync --no-apply` | "No schema changes found" after each of the 3 migrations and at the end |
| Cross-app integration | `tool/sync_it.sh` (inside `verify_all.sh`, then again with `AO_IT_KEEP_LOGS=1`, run `7e770eff`) | PASS — all 7 steps both times. Kept logs: invitation service 31/31 checks; dashboard phase 1 1/1; floor two-device + cross-app 30 passed, 1 skipped; live both directions 1/1 each; **dashboard phase 2 2/2 (incl. the new reconciliation test)**; Edge Function runtime still up |
| Pricing parity, concurrency races | `--with-psql` | NOT RUN — they use `docker exec psql`, which the user does not want run ad hoc; no pricing code changed |

Not done, by rule: manual or visual testing, screenshots, real devices (CLAUDE.md: the user
tests the UI by hand — see §11).

## 8. Final status per finding

| ID | Was | Now | Evidence |
|---|---|---|---|
| S4 server-authoritative start | PARTIAL by design | **Accepted risk, documented** (unchanged) | Offline-first: device time, corrected to server time when > 2 min off; the server's receipt time is now shown on the bill when a start reached it more than 5 min late. No server bound on device times. Owner decision in §9. |
| S17 waive without reason or audit | FAIL | **PASS** | pgTAP 22 (waive audit rows, written-off amounts); `waive_reason_test.dart`; end sheet widget test; group flow test |
| S18 no refunds anywhere | FAIL | **PASS** (dashboard) | Refund dialog, spec "money taken before a void can be refunded…"; pgTAP 22; live phase 2. The floor app still has no refund screen (owner work, by design of the SLC). |
| S19 pending badge per row | Low gap | Unchanged | App-wide strip + Sync screen remain the indicator |
| D2 date range / previous days | FAIL | **PASS** | Specs "opens any earlier day", "Dates… starts from the days on screen…", "a crafted backwards range…", helper tests |
| D3 detail gaps | Low | **PASS** | Spec "wide: shows the first bill with its times, lines, payments and history" |
| D4 expected vs collected vs outstanding | FAIL | **PASS** | Totals spec; summary identity test |
| D5a method filter totals | FAIL (Low) | **PASS** | Spec "the method chip keeps bills paid that way and says so" |
| D5b late payment attribution | note | **Documented** | Bills belong to the day they closed (like the sheet's rows); every payment keeps its own received time in the payments ledger export |
| D7 corrections | FAIL | **PASS** | Record payment / Refund / Correct method specs; pgTAP 22; live phase 2 |
| D8 who/when/original vs updated | FAIL | **PASS** | History section; `arena_sale.history`; pgTAP 22 history assertions |
| D9 reason for financial changes | FAIL | **PASS** | pgTAP 22 (void without/blank/too-long reason refused); "Other…" void spec; refunds/corrections need a reason (server and dialog) |
| D11 refresh / midnight | Low | **PASS** (refresh) / implemented (midnight) | Refresh spec. Midnight: the page recomputes today from a 60 s ticker (`injectNow`); the day boundary itself is tested in the helper test (just after midnight IST is the next day), the page's timer is not exercised by a test |
| D13 export | FAIL | **PASS** | CSV helper tests (header, columns, rows, totals, ledger); live reconciliation in phase 2 |
| D14 CSV formula injection | FAIL | **PASS** | "text cells never run as formulas" |
| D16 export totals vs database | NOT VERIFIED | **PASS** | Phase 2 live test 2/2 |
| D18 dashboard error monitoring | Not implemented | Unchanged (Low) | — |
| H4 refund/correction | FAIL | **PASS** | as D7 |
| H8 group end-time constraint | Low | Unchanged | the op checks the order; the table has no constraint |
| I1 "name resolution failed" | root cause | **PASS (local)** | Gateway route `functions-v1` → `http://supabase_edge_runtime_arena_ops:8081/` (Kong config); the name resolves only while that container exists. It is running; 31/31 invitation checks over HTTP |
| I2 misleading instruction | FAIL | **PASS** | doc corrected |
| I4, P1–P3, P5, P6, P9 | BLOCKED | **BLOCKED** | §10 |

## 9. Remaining risks and owner decisions (not changed by this audit)

* **Device-stamped times (S4).** Session start/end times come from the device clock, corrected to
  server time once it is more than 2 minutes off and measured on every sync. A device whose
  clock changes while offline, or a tampered client, can record shifted times; the server checks
  only their order. Owner decision: accept for the pilot (recommended, with the counter tablet
  set to automatic network time), or add a server-side flag/limit for starts in the future.
* **Spreadsheet columns with no data model:** per-session notes (payment notes and customer notes
  exist), "games of interest", a player count for pool / lounge (counted as 1), a gap-free
  session or invoice number (the export numbers each day's bills in start order; a bill synced
  late from an offline device can shift the numbers after it; Bill ID is permanent).
* **Discounts, GST, invoices, membership plans** — `OWNER_CONFIRMATION.md` #21/#22, still open.
* **Device feed scope:** every active member's device receives the arena's payments and customers
  through `sync_pull` (RLS still blocks direct reads). Open since 2026-10-12.
* **Staff app owner tabs (Money / Reports)** count a method correction's reversal row as a
  refund. Those tabs are owner screens slated to be hidden (CLAUDE.md); the dashboard is right.
* **Advance payments** while a session runs are not capped; two devices can both take an advance.
  The bill then shows Overpaid and the owner can refund it from the dashboard.
* **Revoked member's realtime socket** stays joined until the token refreshes (≤ 1 h); nudges carry
  no business data.
* **Dashboard has no error monitoring** (the staff app has Sentry with PII off and masked replay).
* **Pricing parity and concurrency scripts** were not run in this audit (no pricing code changed).

## 10. What the operator must do before handing the app to staff

Each step needs the owner's credentials or approval; none was done here.

1. **Hosted database.** Approve and push migrations `20261011202706` … `20261014105230`
   (23 files, `DEPLOY_SUPABASE.md` §4a order; `0016` is already there). First check the hosted
   Realtime publication, run `supabase db push --dry-run` and compare the list; never
   `--include-seed`, never `db reset --linked`. Then `supabase migration list --linked` must show
   every file on both sides.
2. **Edge Function.** `supabase functions deploy staff-admin`; set `ADMIN_SITE_URL` (the
   dashboard's https origin) and `ADMIN_ORIGINS`.
3. **Auth.** Site URL and redirect URLs (`https://<dashboard>/accept-invite`,
   `/reset-password`); **custom SMTP** (the built-in sender only reaches team members);
   confirm-signup template; leaked-password protection; password policy. Realtime: turn off
   "Allow public access".
4. **Decide which hosted project is production.** `dart_define.prod.json` points the release app
   at the project `DEPLOY_SUPABASE.md` calls the development project. Either confirm it as the
   pilot's production project or create a production project and repeat 1–3 there.
5. **Dashboard.** Put the hosted URL and publishable key in
   `apps/admin/src/environments/environment.production.ts`, `npm run build`, deploy to that https
   origin.
6. **Android signing.** Create the release keystore and `apps/mobile/android/key.properties`
   (`docs/RELEASE.md` §4), then `flutter build apk --release --split-per-abi
   --dart-define-from-file=dart_define.prod.json` and install `app-arm64-v8a-release.apk` on the
   counter tablet. **iOS** (if used): Apple developer team, `DEVELOPMENT_TEAM`, provisioning.
7. **Set up the arena on hosted:** owner signs up on the dashboard, builds stations, games, station
   types, rates, opening hours, happy hour, payment methods; invites each staff member (each
   accepts the e-mail and sets a password).
8. **Real-device test** on the tablet and a phone against hosted (`DEPLOY_SUPABASE.md` §7) and the
   checklist in §11, including one offline period and a reconnect.
9. **Backups:** confirm the hosted plan's backups / point-in-time recovery and do one restore
   test; export the day's two CSVs each evening for the first weeks.
10. **Owner decisions** in §9 (at least: accept device-stamped times; waive/void reason wording;
    whether staff may refund on the floor).

## 11. Hand-over checklist for the user's manual test (local: `npm run dev` + `bash tool/dev_run.sh`)

Dashboard, **Sales** (`/sales`):
1. Totals read Expected / Collected / Outstanding; open "What these totals mean".
2. Chips Today / Yesterday / 7 days / 30 days; **Dates…** → pick one day weeks ago, then a range;
   try a range over 93 days (message, nothing loads). Leave the page open past midnight once:
   Today moves on.
3. Cash chip on a split bill: the line says "bills paid by Cash" and shows both methods.
4. **Refresh** after taking a payment on the floor.
5. A part-paid bill → **Record payment** (try more than due, then the due amount + a note).
6. A paid bill → **Correct method** (UPI → Cash): Collected unchanged, the method split moves,
   History shows "Payment moved", the payments list shows "corrected out / in".
7. **Void** a bill with "Other…" (needs text), then **Refund** the money that was collected;
   "on voided bills" disappears.
8. **Export → Bills report** and **Payments ledger**: open both in Excel / Google Sheets; check ₹,
   names, the header block, and that the totals rows match the screen.
9. At phone width: the date pickers and totals wrap without horizontal scrolling.

Staff app (iOS Simulator via `tool/dev_run.sh`, or an Android emulator with `ANDROID=1`):
10. A walk-in and a registered customer session; switch station and game mid-session; extend;
    end with a split payment (End sheet + Take payment).
11. End a session with **Waive**: End stays disabled until a reason is typed; on the dashboard
    the bill's History shows "Waived · ₹X written off" with the reason.
12. Turn Wi-Fi off, start and end a session, take a payment, turn Wi-Fi back on: the strip shows
    "N saved here, not sent yet", then Synced; the bill appears on the dashboard once, with its
    payment once.

## 12. Verdict

**BLOCKED — EXTERNAL SETUP OR REAL-DEVICE VERIFICATION REQUIRED**

The staff billing workflow, server pricing, payments ledger, corrections with reasons and
history, sales views and exports are implemented and verified by automated tests on the local
stack (Flutter 778, dashboard 254, pgTAP 990, live cross-app suite all phases). The app cannot be
handed to staff yet because the backend it ships against (hosted) lacks 23 migrations and the
invitation function, e-mail delivery is not configured, there is no release signing key, the
dashboard has no production configuration, and nothing has run on a real counter device. Once
§10 steps 1–8 are done and the §11 checklist passes on the real devices, it is ready for a
controlled staff pilot.
