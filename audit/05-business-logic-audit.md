# Business Logic & Data Integrity Audit

## Part A — Floor, pricing, payments, sync

Scope: single sessions and segments, groups, bookings, pricing (Dart `apps/mobile/lib/domain/pricing/**`, `domain/services/segment_billing.dart` vs SQL `_pr_*`), discounts, waives, payments/refunds/corrections, voids, pads, sales reports, sync conflict and time semantics. Static review only (2026-10-16, branch `feature/venue-generalization`, clean tree). Nothing was run.

### Domain map

| Entity (table) | Server ops (`sync_push` → `_sync_apply` → `op_*`) | Permission (server) |
|---|---|---|
| `sessions`, `session_segments`, `session_extensions`, `session_charges` | `session.start`, `session.reconfigure` (switch station / game / controllers), `session.extend`, `session.end` (+ optional discount, waive), `session.void` | start; start; start; bill (+discount to waive / manual discount); owner level |
| `group_sessions`, `group_assignments`, `group_extensions`, `group_charges` | `group.create`, `group.add`, `group.switch`, `group.end_player`, `group.extend`, `group.end`, `group.void` | start / bill / owner level, as for sessions |
| `payments`, `group_payments` (append-only) | `payment.record` (payment or refund), `payment.correct` (method move = refund + payment pair) | bill (+discount for refund); money |
| `bill_discounts`, `discounts` | applied inside `session.end` / `group.end` by `_discount_apply` | preset/coupon: bill; manual: discount (capped unless settings) |
| `controller_allocations`, `controller_moves`, `controllers` | inside start/reconfigure/group ops (`_pad_borrow`, `_pad_allocate`); `controller.move` | start / settings |
| `bookings` | `booking.create`, `booking.update`, `booking.set_status`; check-in via `session.start.booking_id` | start |
| `pricing_catalog_history` | written by `_sync_apply` when a pricing op changes the canon | — |
| Reports | `arena_sales`, `arena_sale`, `arena_overview` (all over `_sales`) | owner level |
| Idempotency ledger `sync_ops` | every op, keyed by `op_id` | active member |

Not present: customer wallets / balances / memberships (customers table has none).

### Findings

### [P1][BL-001] Session and segment times are device-asserted with no server bound; a forward-dated start or back-dated end lowers a bill and passes re-pricing
**Status:** VERIFIED
**Category:** Money integrity / time trust
**Location:** `supabase/schemas/public/functions/op_session_start.sql:11-16,51-59`; `supabase/schemas/public/functions/op_session_end.sql:25-27,45-46,61-63`; `supabase/schemas/public/functions/op_session_reconfigure.sql:13,36`; `supabase/schemas/public/functions/op_group_create.sql:37`; `supabase/schemas/public/functions/op_group_add.sql:32,47`; `supabase/schemas/public/functions/op_group_end.sql:33,48`; `docs/SYNC.md:97-107,486-489`
**Problem:** Every billing instant (`started_at`, reconfigure `at`, `ended_at`, group `at`) is taken from the payload. Each op holds `statement_timestamp()` in `v_now` but never compares a client time with it: there is no "not in the future", no maximum skew, no maximum lag. The only checks are ordering ones (`ended_at >= started_at` via check constraints, `v_at >= open segment start`). Server re-pricing (`_pr_session_bill`) then confirms only that the money matches *the times it was given*.
**Evidence:** `op_session_start.sql:16` `v_started timestamptz := (p->>'started_at')::timestamptz;` inserted unchanged at :54/:59; `op_session_end.sql:27` `v_ended := (p->>'ended_at')::timestamptz` used at :45, :61, :81. `op_group_add.sql` has no time check at all on `at`. `grep` for any skew/interval bound across `op_session_*`, `op_group_*`, `op_payment*` finds none. The floor app follows server time only when off by more than 2 minutes (`apps/mobile/lib/core/clock/clock.dart` `ClockOffset.threshold`; `apps/mobile/lib/app/sync/cloud_root.dart:517-527`) and the offset is last-measured, so an offline device's clock change is not corrected. The dashboard flags only a *start* recorded >5 min after `started_at` (`apps/admin/src/app/features/sales/components/bill-detail.ts:39,264-266`); a start dated in the future or an end dated in the past is not flagged, and the end's server receipt time is only in `sync_ops.created_at`, which no report exposes. SYNC.md itself lists this as "Blocking production" #3.
**Impact:** Any member with `start` + `bill` and their own login (publishable key ships in the app, so `sync_push` is callable directly), or anyone who changes a tablet clock while offline, can bill less than was played. Discount validity windows (`_discount_apply` judges at `p_at = ended_at`) and pricing-rule selection (judged at `started_at`, e.g. happy hours) follow the forged times too. Reports bucket the bill by the forged `actual_ended_at`.
**Failure Scenario:** Customer plays 18:00-20:00. Staff pushes `session.start` with `started_at = 19:00` (or ends with `ended_at = 19:00`) and the matching ₹150 bill instead of ₹300; server re-prices 1 h, accepts, and the owner sees a normal 1-hour bill. Alternatively start at 17:30 inside a happy-hour rule window to get the rule price for the whole session.
**Recommended Fix:** Bound client times against server receipt time inside each op: refuse (or flag) `started_at`/`at`/`ended_at` later than `statement_timestamp() + small skew` (e.g. 2 min); store the server receipt time of the end (`sessions.ended_recorded_at`, group too) and surface "recorded late / clock mismatch" on Sales for both start and end beyond a threshold; optionally refuse ops whose times lag receipt by more than an owner-set window unless the device was offline (outbox age). Keep offline operation possible by flagging, not refusing, the lag case.
**Estimated Effort:** Medium
**Production Blocker:** Yes (the repo's own SYNC.md lists it as blocking)
**Suggested Verification:** pgTAP: `session.start` with `started_at = now()+1h` must be refused; `session.end` with `ended_at` far in the past must be flagged/stored with receipt time; `tool/sync_it.sh` offline-then-resend path still applies.

### [P2][BL-002] Unpriced segments bill ₹0 and the server accepts them; activity-vs-station and controller count are not validated
**Status:** VERIFIED (server); LIKELY (floor UI path)
**Category:** Pricing / server validation
**Location:** `supabase/schemas/public/functions/_pr_session_bill.sql` (loop: `continue when q is null`); `supabase/schemas/public/functions/_pr_rate.sql` (exact match on `controller_count`, null matches only null); `supabase/schemas/public/functions/_single_supply.sql` (count-only with `p_count` null returns without error); `supabase/schemas/public/functions/op_session_reconfigure.sql:45-57`; `supabase/schemas/public/functions/_group_assignable.sql`; `apps/mobile/lib/data/local/local_session_repository.dart:375-400`; `apps/mobile/lib/features/floor/presentation/sheets/end_session_sheet.dart:326-340`
**Problem:** A segment whose (activity, controller count) has no rate in the frozen snapshot "contributes nothing" on both sides (documented, `docs/SYNC.md:89`). The server never refuses to *create* such a segment: start/reconfigure/group placement do not check that a rate exists, that the activity is one the station offers (`resource_activities` is never consulted by any op; only `_mode_ok` when `current_mode` is set), or that a controller-using activity carries a controller count (`_single_supply` passes `p_count = null`). The floor app refuses a start without a rate (planner quote), but `reconfigure` (switch station / change controllers / change game) has no rate check in the action or the repository.
**Evidence:** `_single_supply`: `if coalesce(p_pad_count,0)=0 then v_n := coalesce(p_count,0); if v_n > 0 and ... then ... end if; return;` — null count returns. `_pr_rate` `(r->>'controller_count')::int is not distinct from p_cc`. End sheet lets "End & record" proceed when `bill.isIncomplete` (button gating at `end_session_sheet.dart:219-220` checks only amount and waive reason) and tells staff "Add the missing rate in Settings → Pricing, then bill again", which cannot work: the session's snapshot is frozen at start.
**Impact:** Revenue leak on legitimate use (e.g. change to 3 controllers where only 1/2/4 are priced, or switch to a station type created after the session started) and a free-play path for an API caller (start a PS5 station as a cheaper or unpriced type, or with `controller_count: null`).
**Failure Scenario:** Session on HEX at 2 controllers; staff changes to 3 controllers at 19:00; arena has no 3c rate. From 19:00 to close the segment is billed ₹0; End shows "incomplete" and staff ends it anyway (no other option besides waive).
**Recommended Fix:** In `op_session_start`, `op_session_reconfigure` and `_group_assignable`, refuse (`no_rate`) when `_pr_rate(snapshot, activity, 'standard', cc)` is null, refuse an activity not linked to the station in `resource_activities`, and require a count for controller activities. Mirror in `SessionActions.switchSystem/changeControllers/changeGame` (pre-flight quote) and fix the End-sheet copy.
**Estimated Effort:** Small–Medium
**Production Blocker:** No (recommended before go-live; seeded PS5 rates cover 1–4)
**Suggested Verification:** pgTAP for each refusal; manual: change controllers to an unpriced count must be refused with a clear message.

### [P2][BL-003] Waive is uncapped and its reason optional on the server, bypassing the manual-discount cap
**Status:** VERIFIED
**Category:** Discounts / authorization of write-offs
**Location:** `supabase/schemas/public/functions/op_session_end.sql:28,34,60,66-74`; `supabase/schemas/public/functions/op_group_end.sql:34,40,64,70-78`; `supabase/schemas/public/functions/_discount_apply.sql:42,92-99`
**Problem:** Manual discounts by a non-`settings` holder are capped at `discount_options.manual_max_percent` (decided #21). The same `discount` permission lets the caller end with `mark_waived: true`, which writes off 100 % of the bill with no cap; the server stores a null reason when none is sent (deliberate compatibility, `docs/SYNC.md` 0016 table). The floor app requires a reason (`session_actions.dart:702`), but that is client-only.
**Evidence:** `op_session_end.sql:34` `if v_waive then perform _need(p_arena, 'discount'); end if;` and `:70` `nullif(btrim(coalesce(p->>'waive_reason','')),'')`; no cap or owner check on waive.
**Impact:** A staff member limited to e.g. 10 % manual discounts can zero any bill; via the API without a reason. Audited (`audit_log` action `waive`, `created_by`), so detective only.
**Failure Scenario:** Staff with `bill`+`discount` ends a ₹600 bill as waived via a direct `sync_push`; reason null; takings show ₹0 for it.
**Recommended Fix:** Require `waive_reason` on the server now that the current floor build sends it (or after a minimum-build gate), and either cap waives for non-`settings` holders by the same percent or require `settings`/owner level for waives above it. Surface waives on the Overview.
**Estimated Effort:** Small
**Production Blocker:** No (owner decision on who may waive; reason requirement is cheap)
**Suggested Verification:** pgTAP: waive without reason refused; waive by capped staff refused above the cap.

### [P2][BL-004] Overtime grace (decided #30) has no parity or pgTAP coverage, and SQL/Dart diverge when the last segment's type is missing from the snapshot
**Status:** VERIFIED (missing coverage); LIKELY (divergence)
**Category:** Pricing parity
**Location:** `supabase/schemas/public/functions/_pr_session_bill.sql:35-43`; `apps/mobile/lib/app/controllers/session_actions.dart:680-688`; `apps/mobile/lib/domain/services/segment_billing.dart:92-101`; `tool/pricing_parity/harness.sql:105-134`; `apps/mobile/tool/pricing_parity/generate.dart`
**Problem:** The parity harness always inserts sessions with `scheduled_end_at = end` and ends at `end`, so `v_last > v_sched` is never true and the grace path is never exercised; `generate.dart` has no overtime case, and no file under `supabase/tests` or `apps/mobile/test` mentions `overtime_grace`. SQL selects the grace with `cross join jsonb_array_elements(activities) ... where a->>'code' = sg.activity_code order by sg.idx desc limit 1`, so if the last segment's activity is not in the snapshot it falls back to an earlier segment's grace; Dart (`overtimeGraceFor`) returns 0 in that case.
**Impact:** A correct bill can be refused with `price_mismatch` (session stays open on the device, Needs attention), or an untested path silently differs; this is exactly the class of drift SYNC.md "Changing pricing (rule)" forbids shipping without a green parity run.
**Failure Scenario:** Owner sets a 10-min grace on PS5; session switched mid-way to a station type added after it started; ended 5 min past the booked end → device bills the whole time, server bills to the booked end → `price_mismatch`.
**Recommended Fix:** Add overtime-grace cases (inside / at / beyond grace, multi-segment, segment starting after booked end, type switch) to `generate.dart` with non-equal scheduled end in the harness; make the SQL pick the grace of the highest-idx segment only (`left join`, 0 when absent).
**Estimated Effort:** Small
**Production Blocker:** No (only once an owner sets a grace) — but run parity before enabling it
**Suggested Verification:** `bash tool/pricing_parity.sh` with the new corpus.

### [P2][BL-005] Booking vs live session is enforced only on the device (#28 unconfirmed but shipping); check-in does not tie the booking to the station
**Status:** VERIFIED
**Category:** Bookings / double-booking
**Location:** `supabase/schemas/public/functions/_booking_free.sql:19-27`; `supabase/schemas/public/functions/op_session_start.sql:43-49`; `apps/mobile/lib/app/controllers/session_actions.dart:178-217`; `docs/OWNER_CONFIRMATION.md:40`
**Problem:** The server refuses only booking-vs-booking overlaps on a specific station. A walk-in started over a reservation, or a booking created over a running session, is caught only by the device's own (possibly stale/offline) view. `session.start` with `booking_id` checks only that the booking is `booked`; it does not compare the booking's `resource_id`/window with the session.
**Evidence:** `_booking_free` queries only `bookings`; `op_session_start` never reads `bookings` unless `booking_id` is sent.
**Impact:** Two tablets (one offline) can both commit: a booked customer arrives to a busy station; or a booking is checked in from the wrong station. No money loss, operational conflict.
**Failure Scenario:** Tablet A offline creates a booking for VOID 18:00-19:00; tablet B starts a walk-in on VOID at 17:50 open-ended; both sync successfully.
**Recommended Fix:** Owner to confirm #28; then in `op_session_start` refuse (or warn via `adjusted`) a start over a `booked` booking on that station within its window unless it is the booking being checked in, and in `_booking_free` refuse a booking overlapping an open segment/assignment whose scheduled end is after the booking start. Verify booking's station = session station on check-in (or allow explicitly).
**Estimated Effort:** Small–Medium
**Production Blocker:** No
**Suggested Verification:** pgTAP for both directions; `tool/sync_it.sh` two-device case.

### [P3][BL-006] Takings are attributed by bill close time and exclude money on voided bills; late refunds rewrite past days
**Status:** VERIFIED
**Category:** Reporting / reconciliation
**Location:** `supabase/schemas/public/functions/_sales.sql:63,94-99,128-129`; `supabase/schemas/private/functions/arena_overview.sql:52-60`; `apps/admin/src/app/features/sales/sales-page.ts:210-215`
**Problem:** `_sales` puts every payment of a bill in the bill's close bucket (`coalesce(actual_ended_at, updated_at)`); Overview `takings_paise` excludes voided bills entirely (`status <> 'voided'`). Consequences: a refund recorded on 20 Oct for a 15 Oct bill lowers 15 Oct's takings; an advance taken on a session still running at day end is in no day; cash kept on a voided-but-not-refunded bill is not in Overview takings (the Sales page does disclose "money on voided bills" separately). Bucketing uses the device-asserted end (BL-001).
**Impact:** No daily cash-up by receipt time; a closed day's figures can change later. Documented as design on the Sales page, so P3.
**Recommended Fix:** Add a "cash received" view by `payments.created_at` (server time) per IST day and method, alongside the bill-based figures.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** Owner click-through: refund an old bill, compare that day before/after.

### [P3][BL-007] Advance payments on a running bill are uncapped; an over-collected bill becomes "paid" silently
**Status:** VERIFIED
**Category:** Payments
**Location:** `supabase/schemas/public/functions/op_payment.sql:63-75`; `supabase/schemas/public/functions/_payment_status.sql`; `supabase/schemas/public/functions/op_session_end.sql:59-60`
**Problem:** `overpayment` applies only once `billed_amount_paise` is set. If advances exceed the final bill (early exit), `session.end` sets `paid` and nothing records change owed. Also payments on a `waived` bill are uncapped.
**Impact:** Over-collection is invisible except by reading the ledger. Documented ("A running session's advance payments are not capped").
**Recommended Fix:** At end, return/flag `overpaid_paise` and show it on the End sheet and Sales; optionally cap advances at the scheduled-end quote.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: advance > final bill produces a flag.

### [P3][BL-008] `session.end` / `group.end` accept a missing `ended_at`
**Status:** NEEDS VERIFICATION
**Category:** Data integrity
**Location:** `supabase/schemas/public/functions/op_session_end.sql:27,45-46,61-63,81-101`; `supabase/schemas/public/functions/_pr_quote.sql` (strict helpers return null)
**Problem:** `ended_at` is never required non-null. With null, open segments are "closed" to null (stay open), the session becomes `completed` with `actual_ended_at` null, and `_pr_session_bill(..., null)` yields a null total. For priced segments the charge-key comparison should refuse it (server keys lose components), but where every segment is unpriced (BL-002) total 0 vs device 0/null passes, leaving a completed session with an open segment that blocks the station (`ux_one_open_segment_per_resource`).
**Impact:** Edge case via API only; station stuck until an owner voids.
**Recommended Fix:** `if v_ended is null then raise exception 'invalid_payload'` in both end ops (and `at` in reconfigure/group ops).
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: end with no `ended_at` refused.

### [P3][BL-009] Refunds need only `bill`+`discount`, on any closed bill at any time, with no `audit_log` entry
**Status:** VERIFIED
**Category:** Payments / authorization
**Location:** `supabase/schemas/public/functions/op_payment.sql:35-36,64-68,79-81`
**Problem:** SYNC.md says refunds are dashboard-only, but the server lets any `discount` holder record a cash refund (≤ collected, reason required) on any bill, including old ones; the row carries `created_by` and reason, but no `audit_log` line (voids, waives and corrections have one). Admin web admits only owner-level logins, so in practice only API callers or owners reach it.
**Impact:** A floor staff member with `discount` could book a "cash refund" and pocket the cash; detectable only by reading ledgers.
**Recommended Fix:** Require owner level (`money`) for refunds, matching `payment.correct`, or at least add an `audit_log` row and show refunds on the Overview.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: refund by staff without `money` refused.

### [P3][BL-010] A replaced (cheaper) price list stays acceptable at start for 72 h
**Status:** VERIFIED (documented design)
**Category:** Pricing snapshot
**Location:** `supabase/schemas/public/functions/_assert_snapshot.sql:23-28`; `supabase/schemas/public/functions/_pricing_grace.sql`
**Problem:** Any canon retired within 72 h validates. Intended for offline devices, but an API caller (or a device that deliberately stays offline) can keep starting sessions on the pre-increase list for three days after an owner raises prices.
**Recommended Fix:** Accept a retired list only when the op's device time / outbox age shows it was recorded before the retirement, or shorten the window; show "started on previous price list" on Sales.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP with a retired canon and a start dated after `retired_at`.

### [P3][BL-011] "Extend beyond closing" (#18, default blocked) is device-only
**Status:** VERIFIED
**Category:** Business rule enforcement
**Location:** `supabase/schemas/public/functions/op_session_extend.sql:17-45`; `supabase/schemas/public/functions/op_group_extend.sql`; `apps/mobile/lib/app/controllers/group_session_actions.dart:470`
**Problem:** Neither extend op reads `allow_extend_past_close` or opening hours. Money is still re-priced, so the impact is operational only.
**Recommended Fix:** Check the snapshot policy and hours in both extend ops.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP.

### [P3][BL-012] `booking.update` without `base_version` overwrites unconditionally
**Status:** VERIFIED
**Category:** Sync conflict semantics
**Location:** `supabase/schemas/public/functions/_stale.sql:1-8`; `supabase/schemas/public/functions/op_booking_update.sql:28-31`
**Problem:** A null/empty `base_version` is "never stale", so an op without it silently wins over another device's edit. Same for `customer.update`.
**Recommended Fix:** Require `base_version` from current builds (refuse when absent after a version gate).
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP.

### Invariants verified as server-enforced

| Invariant | Where enforced | Evidence |
|---|---|---|
| Each op applies at most once; retry replays first answer; concurrent duplicate pushes serialise | `private.sync_push` | `sync_ops` lookup by `op_id` + `pg_advisory_xact_lock(hashtextextended(op_id))`; per-op subtransaction; transient SQLSTATEs not recorded (`supabase/schemas/private/functions/sync_push.sql`) |
| A payment cannot be recorded twice under a new op id | `payments` / `group_payments` PK = device payment id | `payments_pkey`; `23505` → `duplicate` |
| Money is append-only (no update/delete of payments, charges, discounts) | schema + op set | no `update`/`delete` on `payments`, `group_payments`, `session_charges`, `bill_discounts` anywhere in `supabase/schemas`; select-only grants, no write policies |
| Payment sign / reason / method | check constraints + `op_payment` | `payments_amount_sign_check`, `payments_check` (refund reason), `payments_method_check`; `op_payment.sql:78-85` |
| No overpayment of a final bill; refund ≤ collected; no payment on a voided bill; races serialised | `op_payment` | parent row `for update`, sum, `overpayment` / `refund_exceeds_paid` / `voided` (`op_payment.sql:40-75`) |
| Final bill total and every charge row equal the server re-pricing, 0 paise tolerance | `op_session_end`, `op_group_end` | `_pr_session_bill` / `_pr_group_bill`, `_price_mismatch`, sorted `_pr_charge_key` multiset (`op_session_end.sql:81-101`) |
| Frozen price list must equal arena's live list (or one retired ≤ 72 h); forged ₹0 list refused | `_assert_snapshot` at `session.start` / `group.create` | canon comparison incl. rates, activities (+overtime grace), policy, hours, holidays, rules; group `billing_mode` must match policy |
| Extension price matches server delta | `op_session_extend`, `op_group_extend` | `_pr_quote` / `_pr_group_bill` difference vs `added_amount_paise` |
| Discount: preset/coupon validity, use limit (row-locked), min bill, scope; manual needs `discount` and is capped for non-`settings`; amount must equal server's | `_discount_apply` | `for update` on discount; `coupon_used_up`; `discount_over_limit`; `price_mismatch` hint discount |
| One discount per bill | unique indexes | `ux_bill_discounts_session`, `ux_bill_discounts_group` |
| One open segment per station; single vs group occupancy serialised | unique partial index + triggers | `ux_one_open_segment_per_resource`; `t_segment_resource_free` / `t_assignment_resource_free` lock the station row (`assert_resource_free_for_*.sql`) |
| A pad is in at most one open allocation; must be usable, at the station, a pad | unique partial index + `_pad_allocate` + trigger | `ux_one_open_allocation_per_controller`; `controller_taken`, `controller_elsewhere`, `controller_unusable`; `op_controller_move` refuses an allocated pad |
| Billed controller count = pads allocated; ≤ 4; ≤ game max players | `_single_supply`, `_group_assignable` | `controller_count_mismatch`, `controllers_exceeded`, `players_exceeded` |
| Lock order stations → pads by uuid (no deadlock between ops) | `_lock_resources`, `_lock_pads`, `_group_lock` | `order by id for update`; re-check of pad origin then `40001` retry |
| Stale offline edits refused (segments changed, scheduled end moved, open segment/assignment replaced) | `op_session_end`, `op_session_extend`, `op_session_reconfigure`, group ops | `_same_ids` on expected segment/assignment ids; `expected_scheduled_end_at`; `old_end_at` |
| Time ordering (end ≥ start of open segment; segment/assignment end ≥ start) | check constraints + ops | `sessions_check1`, `session_segments_check`, `group_assignments_check`, `invalid_time` |
| Void: owner level, reason 1–500 chars, audit row, closes open segments/pads | `op_session_void`, `op_group_void` | `private.app_is_owner`; `void_reason_required`; `audit_log` insert |
| Waive needs `discount` and is audited (amount written off) | `op_session_end`, `op_group_end` | `audit_log` action `waive` (reason optional — BL-003) |
| Payment method correction: `money` perm, reason, never more than left, append-only pair, audited | `op_payment_correct` | sum of prior corrections from `audit_log`; refund + payment rows |
| Cross-arena references refused | `t_same_arena` triggers | e.g. `session_segments.sql:87-92` |
| Sales/Overview owner-only; IST day buckets; range caps | `arena_sales`, `arena_overview` | `app_is_owner`; `date_trunc(... at time zone 'Asia/Kolkata')`; 93 / 400-day caps; admin `istDayStart` uses fixed +05:30 |
| Money arithmetic integer paise; cash rounding once per bill | `_pr_quote`, `_pr_money`, `_pr_div` | bigint numerators, round-half-up integer division; `_pr_money` applied to session/group total only |
| Floor app "now" is server-corrected when off > 2 min; no device-local timezone use | `OffsetClock`, `core/time` | no `DateTime.now()` / `toLocal()` in business code (`apps/mobile/lib` grep) |

### Not reviewed

- `_pr_sweep` (group per-system sweep), `_pr_rule_price`, `_pr_ist_date`, VR unit and block rounding line by line: relied on `tool/pricing_parity.sh` corpus design (not run).
- Pooled group mode (`shared_controller_pool`): purchased count is staff-declared by design (`docs/SYNC.md:106-107`); not re-audited.
- Drift side: `LocalSessionRepository` / `LocalGroupSessionRepository` atomic writes, outbox ordering, `sync_applier` rollback, Drift migrations (known v16 duplicate-column issue in CLAUDE.md).
- `sync_pull` feed content and per-permission exposure (covered by the security auditor).
- Admin sales UI arithmetic beyond the SQL aggregates (`sale.models.ts` summaries, CSV export).
- Concurrency scripts (`supabase/concurrency_tests/*`) and pgTAP suites were not run; no test of any kind was executed.
- Staff module (attendance, leave, payroll): Part B.


---

## Part B — Staff module (attendance, leave, payroll)

Static, read-only review of the staff module at HEAD of `feature/venue-generalization` (commits 8106721, dc5424f, 6dd3d18). No tests, `supabase`, `flutter` or `npm` commands were run. Decided rules (S1, S2, S3, S5, S6, S23, S24 and the 🟡 defaults S4, S7–S21) were treated as requirements, not reopened.

### Domain map (short)

| Area | Server (all writes: `sync_push` → `_sync_apply` → `op_*`, SECURITY DEFINER) | Reads | Clients |
|---|---|---|---|
| Punch | `op_attendance_punch` → `attendance_punches` (evidence, append-only) + `attendance_entries` (stretches) | RLS own / `attendance_review` | Mobile `AttendanceActions` → `SupabaseAttendanceRepository.punch` (op_id = punch_id, sent straight to `sync_push`, no outbox) |
| Day calc | `_att_blocks` (shift instants), `_att_close_time`, `_att_close_stale`, `_att_day` (single source) | `attendance_days` (definer in `private`, invoker wrapper in `public`) | Mobile history, admin calendar, attendance, team pages |
| Corrections | `op_attendance_correct` (edit/void/add, supersede chain, `audit_log`), `op_attendance_review` | — | Admin attendance |
| Shifts/holidays | `op_shift_upsert/assign/unassign`, `op_staff_holiday_upsert/delete` (`settings`) | RLS all members | Admin shifts, settings |
| Leave | `op_leave_request/cancel` (self), `op_leave_decide/record/adjust` (`leave_approve`), `_leave_working_days`, `_leave_balance`, `_leave_year_start` | `leave_balances`, RLS | Mobile leave, admin leave |
| Pay | `op_hr_profile_save`, `op_pay_rate_add`, `op_pay_policy_add` (`payroll`); `op_salary_run_create/recalculate/set_deduction`, `op_salary_adjustment_add/reverse` (`payroll`); `op_salary_run_finalise/discard` (`payroll_finalise`); `_pay_build_line`, `_pay_rebuild_run`, `_pay_draft`, `_period_finalised` | RLS `payroll` / `payroll_finalise` | Admin pay-setup, payroll |

### Findings

### [P1][ST-001] A salary run can be finalised before its period ends, which freezes days that haven't happened yet and locks out the rest of the period
**Status:** VERIFIED
**Category:** Payroll integrity / period lock
**Location:** `supabase/schemas/public/functions/op_salary_run_finalise.sql:19-37`, `supabase/schemas/public/functions/op_salary_run_create.sql:27-29`, `supabase/schemas/public/functions/_att_day.sql:102,143-148`, `supabase/schemas/public/functions/_pay_build_line.sql:139-158`, `supabase/schemas/public/functions/op_attendance_punch.sql:128-186`, `apps/admin/src/app/features/payroll/data/payroll.models.ts:253-283`
**Problem:** Neither `salary_run.create` nor `salary_run.finalise` checks that `period_end` is before today (IST), and neither checks for days still marked `upcoming` or for open entries. `_att_day` marks later days (and today before the shift ends) as `upcoming`, with `present_units = 0` and `absent_units = 0`. An open entry is counted only up to `p_now`. Finalise then freezes those figures, and `_period_finalised` blocks every later leave request, decision, cancellation and attendance correction on those dates. `op_attendance_punch` has no period check, so staff keep clocking in on days that are already locked.
**Evidence:** `op_salary_run_create.sql:27` validates only `v_to < v_from` and the 62-day length. `op_salary_run_finalise.sql` has no date check at all. `_att_day.sql:143-148` sets `upcoming`/`present` with no units. `_pay_build_line.sql:140` pays monthly base for every employed day, while `:150-157` pays daily and hourly staff only for present units or regular minutes. `suggestNextPeriod` (payroll.models.ts:276-280) proposes the cycle right after the last run with no "has it ended?" guard, and the finalise confirm (`run-detail.ts:402-411`) does not warn about it.
**Impact:** Paying on the last working day of the month is common. If the owner finalises on, say, 28 Nov for 1–30 Nov:
- Daily and hourly staff are never paid for 29–30 Nov.
- Monthly staff get full pay with no absence or LOP deductions possible for those days.
- Staff cannot apply for leave on those days (`period_finalised`).
- Reviewers cannot correct or void those entries.
- The next run cannot overlap those days, so every gap must be found and entered by hand as an adjustment.
**Failure Scenario:** Owner creates and finalises the November run on 28 Nov. An hourly staff member works 12 h on 29–30 Nov. The punches are stored, but no run will ever pay those 12 h. The staff member's unplanned leave for 30 Nov is refused with `period_finalised`.
**Recommended Fix:** In `op_salary_run_finalise`, refuse when `period_end >= _pr_ist_date(now())` (new code, e.g. `period_not_over`). Optionally also refuse while any person has an open entry with `work_date <= period_end`. Mirror the check in the admin finalise button and the period suggestion. Keep `create` allowed so a draft can be previewed.
**Estimated Effort:** Small
**Production Blocker:** Yes (before payroll is used for real money)
**Suggested Verification:** pgTAP in `31_payroll_test.sql`: finalise a run whose `period_end` is today or later and expect a refusal. Then `supabase test db`.

### [P2][ST-002] "Not in use" shifts still schedule staff on the server, while the admin roster stops showing them
**Status:** VERIFIED
**Category:** Single source of truth / attendance and pay correctness
**Location:** `supabase/schemas/public/functions/_att_blocks.sql:22-33`, `apps/admin/src/app/features/shifts/dialogs/shift-dialog.ts:105-107`, `apps/admin/src/app/features/shifts/data/shifts.models.ts:262`, `supabase/schemas/public/tables/staff_shifts.sql:16-17`
**Problem:** `_att_blocks` joins `shifts` without filtering `s.active`, so a shift switched off still produces scheduled blocks for every open-ended assignment. The admin dialog promises "A shift not in use stays on past days but plans no new ones", and the admin roster (`rosterRows`) drops inactive shifts on the client. The roster therefore disagrees with `_att_day`, which feeds the calendar, leave day counts (`_leave_working_days`) and salary. In addition, `staff_shifts_no_overlap` only prevents overlaps of the *same* shift, so a person on an old shift and a new overlapping one has their scheduled minutes added together.
**Evidence:** `_att_blocks.sql:27-32` has no `s.active` predicate. `shifts.models.ts:262` filters `s.active`.
**Impact:** The owner retires "Morning" and assigns "Day" without ending the old assignments.
- If both overlap, scheduled minutes double, so an 8 h day reads as about 50%: `half_day`, plus late marks against the earlier start.
- If the person no longer works the retired shift's days, those days read as `absent`.
- In both cases deductions are suggested and applied by default (S23), and leave requests count the retired shift's days as working days.
- The roster shows nothing wrong.
**Failure Scenario:** Deactivate a shift with open-ended assignments, assign a new overlapping shift, then calculate pay: half-day and absent deductions appear for every day.
**Recommended Fix:** Decide what `active` means on the server. Either make it effective-dated (for example an `inactive_from` date that `_att_blocks` respects, which matches the UI copy), or refuse to deactivate a shift that has open-ended assignments. Also refuse overlapping *time* blocks across different shifts for one person, or document that split shifts must not overlap.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** pgTAP in `29_shifts_hours_corrections_test.sql`: an inactive shift contributes no blocks after its deactivation date. Run a payroll draft on a fixture with overlapping shifts.

### [P2][ST-003] Pay lines ignore `tracks_attendance` and deactivation, so salaried people who don't clock in get absence deductions, and deactivated staff stay on the payroll
**Status:** VERIFIED
**Category:** Payroll correctness
**Location:** `supabase/schemas/public/functions/_pay_build_line.sql:76-83,92-98`, `supabase/schemas/public/functions/_att_day.sql:71-79`, `supabase/schemas/public/functions/_pay_rebuild_run.sql:23-26`, `supabase/schemas/public/functions/op_attendance_punch.sql:80-82`
**Problem:** `_staff_hr.tracks` is used only to filter `attendance_days` and `leave_balances`. `_att_day` and `_pay_build_line` never read it, so an untracked person with a shift assignment is `absent` every scheduled day. `_pay_rebuild_run` loops over every profile in the arena, including `active = false` ones, and deactivating a member does not set `left_on`.
**Evidence:** No reference to `tracks` or `active` in `_pay_build_line.sql` or `_att_day.sql`. `_pay_build_line.sql:79-83` only excludes people with no rate, not yet joined, or already left.
**Impact:**
- An owner who turns off tracking for a salaried manager who is on the roster gets "Absent" deductions for every scheduled day, applied by default and capped at gross, so net pay is 0.
- A deactivated person with no shift and no `left_on` is paid the full monthly base every run.
- Both are visible in the timesheet, but only if the owner spots them.
**Failure Scenario:** Staff member leaves. The owner deactivates them on Team and removes their shift, but never sets "left on" in Pay setup. Next month's run includes their full salary.
**Recommended Fix:** In `_pay_build_line`, for `tracks = false` treat scheduled days as present (or skip the absence and late suggestions) and say so in `notes`. For profiles with `active = false` and no `left_on`, either exclude them or add a prominent note. Better: have staff deactivation prompt for `left_on`. Optionally refuse punches after `left_on`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP in `31_payroll_test.sql` for the untracked-with-shift and inactive-without-`left_on` cases.

### [P2][ST-004] Leave `day_split` is fixed at approval, so later holiday or shift changes cause LOP deductions on holidays and paid leave on days off
**Status:** VERIFIED
**Category:** Leave and payroll correctness
**Location:** `supabase/schemas/public/functions/op_leave_decide.sql:56-67`, `supabase/schemas/public/functions/op_leave_record.sql:70-82`, `supabase/schemas/public/functions/_att_day.sql:91-96,136-139,173`, `supabase/schemas/public/functions/_pay_build_line.sql:141-144,150-152`, `supabase/schemas/public/functions/_leave_balance.sql:25-28`
**Problem:** `day_split` (units and paid units per date) is computed from the schedule at decision time and never updated. `_att_day` still sums that day's leave units after a staff holiday is added or the shift changes, so `leave_lop` and `leave_paid` are reported even when the status is `holiday` or `week_off`. `_pay_build_line` then deducts LOP for monthly staff, pays leave for daily staff on that date, and `_leave_balance` keeps the paid days as used. Separately, `op_leave_decide` recomputes the split from the *current* schedule while `days`, `paid_days` and `lop_days` come from the request time. The two can disagree: the check constraint only ties `paid + lop = days`, not to `day_split`.
**Impact:** Leave approved in advance for a festival week, followed by the owner adding the festival as a staff holiday: monthly staff lose a day's pay as LOP on a paid holiday, or burn a paid-leave day. The person cannot fix it themselves.
**Failure Scenario:** Approve 3 days of LOP for 10–12 Nov, then add 11 Nov as a paid staff holiday. The November run shows `lop_leave` 3 units including the holiday.
**Recommended Fix:** In `_att_day`, ignore leave units on `holiday` and `week_off` days (zero `leave_paid` and `leave_lop` there), or recompute the split when holidays or shifts change. In `op_leave_decide`, recompute `days` together with the split (or refuse with a "schedule changed" code) so the stored totals match the split.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP in `30_leave_test.sql` and `31_payroll_test.sql`: approve leave, add a holiday inside it, and expect no LOP deduction or balance use for that day.

### [P2][ST-005] Changing someone's joining date silently drops their leave adjustments from the balance
**Status:** VERIFIED
**Category:** Leave balance integrity
**Location:** `supabase/schemas/public/functions/op_leave_adjust.sql:32-34`, `supabase/schemas/public/functions/_leave_balance.sql:23-24`, `supabase/schemas/public/functions/_staff_hr.sql:26`, `supabase/schemas/public/functions/op_hr_profile_save.sql:24-25,57`
**Problem:** `leave_adjustments.year_start` stores the exact leave-year start date that applied when the adjustment was made. `_leave_balance` matches adjustments with `a.year_start = y.ys`. With no HR row, `joined_on` defaults to the profile's creation date. When `hr_profile.save` later sets the real joining date (the normal onboarding order), every leave-year start moves, and earlier adjustments no longer match any year.
**Impact:** Carry-over or compensatory days entered before the joining date was corrected vanish from the balance. There is no error, and the append-only rows still exist.
**Failure Scenario:** Staff invited 10 Oct 2026 (default joined 10 Oct). The manager adds +5 days. The owner then sets joined_on = 1 Mar 2024. The balance drops by 5.
**Recommended Fix:** Bucket adjustments by date range instead of equality: store `effective_on` and sum where it falls between `ys` and `ye`. Alternatively, have `op_hr_profile_save` refuse or re-bucket when adjustments exist.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: adjust, change `joined_on`, then call `leave_balances` and expect the adjustment to still count.

### [P2][ST-006] The own-record rule does not cover `leave.adjust` or any pay op, so permission holders can top up their own leave or pay
**Status:** VERIFIED
**Category:** Authorization / segregation of duties
**Location:** `supabase/schemas/public/functions/op_leave_adjust.sql:24-34`, `supabase/schemas/public/functions/op_pay_rate_add.sql:29-49`, `supabase/schemas/public/functions/op_salary_adjustment_add.sql:27`, `supabase/schemas/public/functions/op_salary_run_set_deduction.sql:25-37`, `supabase/schemas/public/functions/op_hr_profile_save.sql:25`
**Problem:** `_own_record` is enforced on leave decide and record and on attendance correct and review (S7). It is not called by:
- `leave.adjust`: a non-owner `leave_approve` holder can add up to 366 paid-leave days to their own balance;
- `pay_rate.add`, `salary_adjustment.add`, `salary_run.set_deduction`, `hr_profile.save`: a non-owner `payroll` holder can raise their own rate, add their own bonus, waive their own deductions, or change their own joining or leaving dates.
**Impact:** Paid leave turns into money (no LOP deduction; daily and hourly staff are paid for paid leave). A colleague then approves the leave with the default split from the inflated balance. Only `payroll_finalise` stands between a self-granted raise and payment. `hr_profile.save` and `set_deduction` leave no `audit_log` trail (see ST-012).
**Failure Scenario:** A manager with `leave_approve` sends `leave.adjust {staff_id: self, days: 30}`, then applies for leave that another approver approves as paid.
**Recommended Fix:** Call `_own_record(p_arena, v_staff)` in `op_leave_adjust`, and in each pay op that targets a staff id (owner role exempt, as in S7). Add the new refusal to `docs/STAFF_API.md`.
**Estimated Effort:** Small
**Production Blocker:** No (only matters once non-owners hold these permissions; the admin web is owner-level only today)
**Suggested Verification:** pgTAP in `30_leave_test.sql` and `31_payroll_test.sql`: self-targeted adjust or pay op by a non-owner holder is refused with `own_record`.

### [P2][ST-007] Removing a shift assignment deletes its history, which turns past worked days in an open period into all-overtime week-offs
**Status:** VERIFIED
**Category:** Payroll correctness / history
**Location:** `supabase/schemas/public/functions/op_shift_unassign.sql:19`, `supabase/schemas/public/functions/op_shift_assign.sql:39-43`, `supabase/schemas/public/functions/_att_day.sql:130-139`, `apps/admin/src/app/features/shifts/components/shift-detail.ts:205-227`
**Problem:** `shift.unassign` hard-deletes the `staff_shifts` row. `shift.assign` can also move `effective_from` or `effective_to` backwards. Neither checks a lower bound date or finalised periods. For every past day in the current, unfinalised period that loses its schedule, `_att_day` returns `week_off`, where every minute worked is extra (S2) and absences disappear. The admin warning says the days "become week offs" but does not mention the pay effect.
**Impact:** Moving a person from Morning to Evening mid-month by removing the old assignment, instead of ending it, makes every hour worked earlier that month extra hours. With `extra_hours_paid` (monthly "fixed + overtime") those hours are paid as overtime on top of base, and absent deductions for those days vanish.
**Failure Scenario:** On 21 Oct, remove Morning (assigned since 1 Oct) and assign Evening from 21 Oct. The October draft shows about 160 h of extra hours for 1–20 Oct.
**Recommended Fix:** Make unassign end the assignment yesterday (`effective_to = today − 1`) rather than delete it, and allow deletion only when the assignment hasn't started. Refuse assignment date changes that reach into a finalised period. In the UI, steer people to "End assignment".
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: unassign mid-period, then `attendance_days` for earlier days still shows the scheduled status.

### [P2][ST-008] Work days follow the IST calendar date of the clock-in, not the shift it belongs to, which breaks shifts around midnight
**Status:** VERIFIED
**Category:** Time boundaries (IST midnight)
**Location:** `supabase/schemas/public/functions/op_attendance_punch.sql:166-171`, `supabase/schemas/public/functions/op_attendance_correct.sql:77`, `supabase/schemas/public/functions/_att_day.sql:98-100,124-125`, `supabase/schemas/public/functions/_att_blocks.sql:22-26`
**Problem:** `work_date := _pr_ist_date(in_at)`, and `_att_day` only considers that date's own blocks and entries.
- For a shift that starts at or just after 00:00, clocking in a few minutes before midnight files the stretch on the previous date. That date's block (00:00 the previous day) has already passed, so `late` is true every day, and the real shift date reads `absent`.
- For an overnight shift (for example 22:00–06:00), arriving after midnight files the entry on the next date: the shift's own date shows `absent`, and the next date gets two stretches (extra hours).
**Impact:** Systematic false late marks and absence or overtime pairs for night staff. Late and absence deductions are applied by default (S23).
**Failure Scenario:** Shift 00:00–08:00. Staff member clocks in 23:52 and out 08:01 every night. Every day shows "late" and the late rule deducts ½ day per 3 lates.
**Recommended Fix:** Assign `work_date` to the shift block nearest the clock-in (for example the block whose `[start − early window, end)` contains `in_at`), falling back to the IST date. Apply the same rule in corrections. Document the behaviour in STAFF.md.
**Estimated Effort:** Medium
**Production Blocker:** No (only if a venue runs shifts that cross or start at midnight)
**Suggested Verification:** pgTAP in `29_shifts_hours_corrections_test.sql` with a 00:00 shift and a 23:55 clock-in.

### [P2][ST-009] The geofence trusts the phone: position, accuracy and the mock flag are all self-reported
**Status:** VERIFIED
**Category:** Punch integrity / anti-fraud
**Location:** `supabase/schemas/public/functions/op_attendance_punch.sql:48-53,84-126`, `apps/mobile/lib/data/remote/supabase_attendance_repository.dart:141-147`
**Problem:** The server verdict is computed from `lat`, `lng`, `accuracy_m` and `is_mocked` exactly as the client sends them. Any signed-in staff member can call `sync_push` directly with their own session and any coordinates, a small accuracy, and `is_mocked` false or absent. Nothing ties the punch to an attested device or a known network. docs/STAFF.md (lines 94, 108) presents mock detection as the defence and does not acknowledge spoofing through the API. Time is safe: the server stamps it and `device_at` is evidence only.
**Impact:** `outside_rule: block` can be bypassed by a motivated staff member, so remote "clock-ins" are paid. With `flag`, the entry is paid by default unless a reviewer voids it (see ST-010).
**Failure Scenario:** A staff member scripts `sync_push` with the arena's coordinates (readable from `settings.attendance` through RLS) from home.
**Recommended Fix:** Document this as a known limitation in STAFF.md and OWNER_CONFIRMATION. Before relying on geofencing for pay, add layered checks: Play Integrity / App Attest tokens verified server-side, the registered arena kiosk (planned `via`), Wi-Fi BSSID evidence, or review of punches from unusual device ids.
**Estimated Effort:** Large (attestation), Small (documentation)
**Production Blocker:** No (an accepted limitation once documented)
**Suggested Verification:** Manual: call `sync_push` with crafted coordinates against the local stack and confirm the verdict is `inside`.

### [P2][ST-010] Finalise ignores entries still waiting for review, so flagged punches are paid and then locked
**Status:** VERIFIED
**Category:** Review controls / payroll
**Location:** `supabase/schemas/public/functions/op_salary_run_finalise.sql:21-37`, `supabase/schemas/public/functions/_att_day.sql:98-113`, `supabase/schemas/public/functions/op_attendance_correct.sql:50-52`
**Problem:** `_att_day` counts every `active` entry whatever its `review` state. That includes outside-geofence, mock-flagged, `auto_out` (S14: paid, flagged) and `past_shift_end` entries. Finalise checks only `net_negative`. After finalise, `attendance.correct` refuses those days (`period_finalised`), so a flagged entry that was never reviewed can only be clawed back by an adjustment in the next run. Finalise also silently rebuilds from live data, so the figures locked can differ from the timesheet the owner just reviewed.
**Impact:** The "flag" rule's promise ("accepted and put up for review") becomes "paid and locked" unless someone remembers to clear the review queue first. Money paid on a fraudulent or forgotten punch needs a manual recovery.
**Failure Scenario:** A mock-flagged clock-in on 30 Oct (rule `flag`) is still pending. The owner finalises October. The reviewer's void on 2 Nov is refused.
**Recommended Fix:** Refuse finalise with `pending_reviews` (hint: count and names) while any `review = 'pending'` active entry has a `work_date` in the period, or require an explicit `acknowledge_pending: true`. Return a summary of the differences after the rebuild, or require the client to send the `computed_at` it reviewed and refuse on a mismatch.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP in `31_payroll_test.sql`: finalise with a pending flagged entry and expect a refusal.

### [P3][ST-011] The finalised-period lock skips several writers, and none of the checks are serialised with finalise
**Status:** VERIFIED (lock gaps) / LIKELY (race)
**Category:** Period lock (S19) / concurrency
**Location:** `supabase/schemas/public/functions/_period_finalised.sql:16-18`, `supabase/schemas/public/functions/op_shift_upsert.sql:53`, `supabase/schemas/public/functions/op_shift_assign.sql:41`, `supabase/schemas/public/functions/op_staff_holiday_upsert.sql:24-26`, `supabase/schemas/public/functions/op_staff_holiday_delete.sql:17`, `supabase/schemas/public/functions/op_hr_profile_save.sql:57`, `supabase/schemas/public/functions/_att_close_stale.sql:20-28`, `supabase/schemas/public/functions/op_attendance_punch.sql:136-140,175-184`
**Problem:** These all change `_att_day` results for finalised days without a `period_finalised` check:
- shift time or day edits;
- assignment date changes and removals;
- staff holidays;
- HR `joined_on`, `left_on` and `standard_day_min`;
- `work_hours` settings;
- clock-out and auto-close of an entry whose `work_date` is finalised.

Money stays frozen in `salary_run_lines`, but `attendance_days` (the floor history, the admin calendar and the next run's weekly look-back, S11) recomputes the finalised days differently from what was paid. The unassign dialog's own copy admits this. In addition, `_period_finalised` reads without locking. An `attendance.correct`, `leave.decide` or `pay_rate.add` committing while finalise runs on another connection can pass the check and land in a period that has just been finalised, missing from the frozen lines.
**Impact:** The timesheet staff see for a paid month can drift from their payslip. There is also a rare race window.
**Recommended Fix:** Add `_period_finalised` checks to `hr_profile.save` (date fields), `shift.assign`/`unassign` (ranges reaching into a finalised period) and `staff_holiday.*` (day). Have `attendance_days` serve finalised days from the run's frozen `days` JSON. Take a per-arena advisory lock, or `select … for share` on the arena's `salary_runs`, in `_period_finalised` callers and in finalise.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** pgTAP: after finalise, `staff_holiday.upsert` on a covered day is refused.

### [P3][ST-012] HR profile changes and keep/waive decisions leave no audit trail
**Status:** VERIFIED
**Category:** Auditability
**Location:** `supabase/schemas/public/functions/op_hr_profile_save.sql:53-59`, `supabase/schemas/public/functions/op_salary_run_set_deduction.sql:34-38`, `supabase/schemas/public/functions/op_leave_adjust.sql:33-34`
**Problem:** `staff_hr_profiles` is updated in place: joining and leaving dates, the tracking switch, standard day and leave allowance all affect pay, and the old values are not kept. `salary_deduction_decisions` is an upsert that keeps only the latest decider. None of these write `audit_log`. Pay rates and adjustments are append-only and carry `created_by`, so they are covered.
**Impact:** Pay-affecting changes can't be reconstructed after the fact.
**Recommended Fix:** Write `audit_log` rows (before and after) in `op_hr_profile_save`, `op_salary_run_set_deduction` and `op_leave_adjust`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Inspect `audit_log` after each op (local stack).

### [P3][ST-013] Leave balance can go negative, and the approver's default split can use the wrong year's balance
**Status:** VERIFIED
**Category:** Leave balance
**Location:** `supabase/schemas/public/functions/op_leave_decide.sql:47-55`, `supabase/schemas/public/functions/op_leave_record.sql:69`, `apps/admin/src/app/features/leave/dialogs/decide-dialog.ts:175`, `supabase/schemas/public/functions/_leave_balance.sql:29-31`
**Problem:**
- Explicit `paid_days` is not capped by the balance, and `leave.record paid: true` pays every day regardless of it. That is permissible under S6 (the approver decides), but it is undocumented that balances may go negative.
- The admin always sends `paid_days`, defaulted from `leave_balances` for the *current* leave year rather than the year of `from_date`.
- Two approvals for the same person lock only their own request rows, so concurrent default approvals both see the same balance.
- Requests that span a leave-year boundary take their default from one year's balance only.
**Impact:** Paid leave can exceed the allowance without anyone noticing.
**Recommended Fix:** Show a negative-balance warning in the admin approve dialog, fetch the balance for `from_date`'s year, and lock the staff profile row in `op_leave_decide` (as `op_leave_record` already does).
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: two approvals in sequence with the default split, then check the balance.

### [P3][ST-014] For someone who joined on 29 February, leave taken on the 28 February anniversary counts in no leave year
**Status:** LIKELY (relies on PostgreSQL `age()` semantics; not executed)
**Category:** Leave year boundaries
**Location:** `supabase/schemas/public/functions/_leave_year_start.sql:16-18`, `supabase/schemas/public/functions/_leave_balance.sql:18-19,28`
**Problem:** For `joined_on = 2024-02-29`, `age('2025-02-28', '2024-02-29')` gives 0 years, so the year start is 2024-02-29. But that year's end is `2024-02-29 + 1 year − 1 day = 2025-02-27`. So 28 Feb 2025 falls outside the very year `_leave_year_start` assigned it to: its paid units are counted in no year's `used`. The comment's claim that "later years start 28 February" isn't what the code returns.
**Impact:** One day per year for 29-February joiners.
**Recommended Fix:** Compute the year end as the next year's start minus 1 day, using the same function.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `select _leave_year_start(...)` and `_leave_balance` for a 29-February joiner.

### [P3][ST-015] Punch locations and leave reasons are kept forever and visible to non-owner reviewers
**Status:** VERIFIED
**Category:** Privacy (PII)
**Location:** `supabase/schemas/public/tables/attendance_punches.sql:19-22,103-107`, `supabase/schemas/public/tables/leave_requests.sql` (policy `p_sel_leave_requests`)
**Problem:** The GPS position (`lat`, `lng`, `accuracy_m`) is stored on every punch with no retention or purge. It can be read by the person and by any `attendance_review` holder; that permission is grantable by a `settings` holder and is not owner-level. Leave reasons, which may be medical, are readable by `attendance_review` and `payroll` holders as well as `leave_approve`. This is consistent with the design, but no retention period is defined.
**Impact:** Location history of employees builds up indefinitely, which is a compliance risk under India's DPDP Act.
**Recommended Fix:** Define a retention period, for example nulling `lat`/`lng` older than N months once the period is finalised. Consider rounding stored coordinates or keeping only the distance and verdict. Document who sees what.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Policy review with the owner.

### [P3][ST-016] A mistyped pay rate can't be corrected for its own start date
**Status:** VERIFIED
**Category:** Pay setup operability
**Location:** `supabase/schemas/public/tables/staff_pay_rates.sql` (`staff_pay_rates_staff_id_effective_from_key`), `supabase/schemas/public/functions/op_pay_rate_add.sql:49`
**Problem:** Rates are append-only and unique per `(staff_id, effective_from)`, and there is no void op. A wrong amount can only be superseded from the next day, so that first day is paid on the wrong rate (1/N of a monthly salary) unless offset by an adjustment.
**Recommended Fix:** Allow `pay_rate.add` to supersede a same-date rate (keeping the old row with `superseded_by`) while no finalised run covers it, or add `pay_rate.void` with a reason and an audit entry.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: correcting a same-date rate in a draft-only period.

### [P3][ST-017] A clock-out after a read-path auto-close is refused, and the real clock-out time is lost
**Status:** VERIFIED
**Category:** Punch evidence
**Location:** `supabase/schemas/private/functions/attendance_days.sql:43`, `supabase/schemas/public/functions/op_attendance_punch.sql:153-155`
**Problem:** `attendance_days`, `salary_run.create`, `recalculate` and `finalise` call `_att_close_stale`. If one of them closes a stale entry before the person taps "clock out", the punch is refused with `not_clocked_in` and nothing is stored. When `op_attendance_punch` does the auto-close itself, the clock-out punch is kept as evidence.
**Impact:** The reviewer loses the evidence of when the person really left (S14 review).
**Recommended Fix:** On `out` with no open entry, attach the punch to the most recent `auto_out` entry of the last `max_open_hours` as evidence (as the in-call auto-close already does) instead of refusing.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP in `28_attendance_punch_test.sql`.

### Invariants verified as server-enforced

| Invariant | Where |
|---|---|
| Punch time is the server's `statement_timestamp()`; `device_at` is stored as evidence only | `op_attendance_punch.sql:39,160,169` |
| Staff punch only for their own active profile (`auth.uid()`), never for someone else | `op_attendance_punch.sql:80-82` |
| One open entry per person; active entries never overlap; punches from two devices are serialised | `attendance_entries.sql:36-37,89-90`; `FOR UPDATE` on `staff_profiles` (`op_attendance_punch.sql:80-81`) |
| Double clock-in and clock-out without clock-in are refused | `op_attendance_punch.sql:149-155` |
| Replay is idempotent (op_id = punch_id, `sync_ops`, punch PK) | `sync_push.sql:36-46`; `supabase_attendance_repository.dart:88-96` |
| Geofence, mock and outside verdict are decided on the server, with a snapshot of the rules used (client preview is advisory) | `op_attendance_punch.sql:84-126,162-163` |
| Corrections need `attendance_review` and a reason, refuse own record (non-owner), supersede rather than edit, write `audit_log`, and check finalised on both the old and the new day | `op_attendance_correct.sql:36-52,77-107` |
| Leave request and cancel only for the caller's own profile; overlap check serialised by a staff-row lock | `op_leave_request.sql:34-36,62-66`; `op_leave_cancel.sql:21-24` |
| Leave decide and record need `leave_approve`, refuse own record (non-owner), lock the request row, check finalised, write `audit_log` | `op_leave_decide.sql:35-44,85-88`; `op_leave_record.sql:40-59` |
| Paid and LOP split totals match days (`leave_requests_split_check`); paid days in halves within 0–days | `leave_requests.sql:39-42`; `op_leave_decide.sql:47-51` |
| Money is integer paise (`bigint`) in tables; exact `numeric` maths; each component rounded once | `_pay_build_line.sql:57-60,239-263` |
| Salary runs never overlap (gist exclusion, discarded excluded) | `salary_runs.sql:30-31` |
| Draft ops lock the run (`FOR UPDATE`) and refuse non-drafts, so two concurrent finalises give one success and one `run_not_draft` | `_pay_draft.sql:15-17` |
| Finalise and discard need `payroll_finalise`; everything else needs `payroll` | `op_salary_run_finalise.sql:21`, `op_salary_run_discard.sql:19` |
| `net_negative` blocks finalise; deductions capped at gross | `op_salary_run_finalise.sql:25-29`; `_pay_build_line.sql:245-248` |
| Rates and pay rules cannot start inside a finalised period | `op_pay_rate_add.sql:43-48`, `op_pay_policy_add.sql:22-27` |
| Adjustments are append-only and signed by kind; one reversal per adjustment; reversals can't be reversed | `salary_adjustments.sql` (`sign_check`, `reverses_id_key`); `op_salary_adjustment_reverse.sql:28-36` |
| Staff read no pay: `staff_pay_rates` and `pay_policies` need `payroll`; `salary_*` need `payroll` or `payroll_finalise`; `audit_log` (finalise totals) needs money or reports; the mobile app has no pay reads | table policies; `grep` of `apps/mobile/lib` |
| `staff_hr_profiles` holds no bank or ID numbers (only `employee_code`) | `staff_hr_profiles.sql` |
| `anon` has nothing; `authenticated` can only `select` staff tables (writes go through `sync_push` only) | revoke and grant blocks in each table file |
| `attendance_days` and `leave_balances`: own `p_staff` always; others need `attendance_review`/`payroll` or `leave_approve`/`payroll`; arena membership required | `private/functions/attendance_days.sql:30-42`; `private/functions/leave_balances.sql:25-34` |
| `_att_day` is the single calculation: mobile and admin render `attendance_days` output. The Dart geofence preview and the admin derived-rate "≈" figure are labelled estimates, not used for decisions | `attendance_day.dart:3`; `attendance_rules.dart:120-186`; `pay-setup.models.ts:98-111` |

### Not reviewed

- pgTAP files 28–31: their content was only grepped, and they were not run (`supabase test db` not executed).
- Validators read only partly: `_work_hours_settings`, `_leave_rules_settings`, `_pay_policy_settings`, `op_settings_save` whitelisting.
- Generated migrations vs `schemas/` parity, and `_assert_same_arena` internals.
- `private.app_arena_ids_with` and owner-level grant rules (covered by the authz auditor).
- Realtime nudge after punches, and FCM (not built).
- Kiosk / `via` (not built).
- Admin calendar, team and attendance UI and mobile screens beyond their data mapping.
- Performance of `attendance_days` (62 days × staff × per-day `_att_day` queries) and of `_pay_build_line` loops.
- A numerical walk-through of the STAFF.md §4.3 worked examples against `_pay_build_line`.
- Weekly-basis extra-hours behaviour across periods (S11) beyond reading the code: the base-subtraction logic for hourly staff looked consistent.
