# 02 — Supabase database audit (schema, migrations, functions, integrity, performance)

Auditor area: database design and mechanics (IDs DB-001…). RLS/grants/auth and pricing/payroll business semantics are covered by other auditors and are mentioned here only where they are schema-integrity issues.

## Scope and method

- **Read:** `CLAUDE.md`, `supabase/README.md`, `docs/SYNC.md` (relevant sections), `docs/DEPLOY_SUPABASE.md`, `docs/RELEASE.md` (backup section), `supabase/config.toml` (db section), `supabase/seed.sql`, all 53 table files in `supabase/schemas/public/tables/` (constraints, indexes, triggers, policies), the 4 `sync_v_*` views, `_cluster/publications.sql`, and these functions: `private.sync_push`, `private.sync_pull`, `_sync_apply`, `_sync_sources`, `_assert_same_arena`, `assert_resource_free_for_segment/_assignment`, `assert_controller_free_for_allocation`, `sync_stamp`, `sync_record_delete`, RLS helpers (`app_arena_ids*`, `app_my_staff_ids`, `app_has_perm`), `op_payment`, `op_group_end`, `_group_active`, `_discount_apply` (lock part), `op_leave_decide`, `op_salary_run_finalise`, `_pay_draft`, `_period_finalised`, `op_shift_upsert`, `op_salary_adjustment_reverse`, `_sales`, `arena_overview` (data source), report-RPC bounds, `_pay_build_line` (numeric types), `_pr_money`, `_pr_ist_date`, plus greps across all ~220 functions for deletes, updates on append-only tables, float types, timezone handling, nested exception handlers, row locks and `audit_log` writes.
- **Migrations:** the 11 files in `supabase/migrations/` were scanned for DROP / ALTER / data rewrites; git history of the migrations directory was inspected (`git log --diff-filter=D`).
- **Static only.** I didn't run supabase, docker, psql, pgTAP or the advisors. Line numbers below were checked with `grep -n` / `cat -n` against the working tree at `24a4bdd`.

## Schema map

There is one multi-tenant Postgres 17 database. Every business row carries `arena_id`, and cross-arena references are blocked by the `t_same_arena` trigger (`_assert_same_arena`), not by composite FKs (the exception is `activity_code`, which uses a composite FK to `activities(arena_id, code)`). The tables fall into these groups:
- **Tenancy and people:** `arenas`, `staff_profiles` (linked to `auth.users`), `staff_invites`, `customers`.
- **Floor catalogue:** `resources` (stations), `activities` (station types), `resource_activities`, `games`, `game_*`, `controllers`, `accessory_kinds`.
- **Pricing:** `rate_cards`, `rate_bands`, `rates`, `billing_policies`, `holidays`, `pricing_rules`, `settings`, `pricing_catalog_history`, `discounts`.
- **Single sessions:** `sessions` → `session_segments`, `session_extensions`, `session_charges`, `payments`, `bill_discounts`.
- **Group sessions:** `group_sessions` → `group_assignments`, `group_extensions`, `group_charges`, `group_payments`.
- **Pad tracking:** `controller_allocations`, `controller_moves`.
- **Bookings and audit:** `bookings`, `audit_log`.
- **Staff module (online only, 14 tables):** `attendance_punches`, `attendance_entries`, `shifts`, `staff_shifts`, `staff_holidays`, `staff_hr_profiles`, `leave_requests`, `leave_adjustments`, `staff_pay_rates`, `pay_policies`, `salary_runs`, `salary_run_lines`, `salary_deduction_decisions`, `salary_adjustments`.
- **Sync plumbing:** `sync_ops` (idempotency ledger), `sync_tombstones`.

Money is `bigint` paise and instants are `timestamptz`. The change feed uses `sync_xid xid8`, stamped by trigger, with an `(arena_id, sync_xid)` index on every synced table. Every write goes through `sync_push` → `_sync_apply` (a `case` over 71 op kinds) → `op_*` (SECURITY DEFINER), one savepoint per op.

---

## Findings

## [P1][DB-001] Squashed migration history cannot be pushed to the existing hosted project; the deployment runbook and CLAUDE.md describe migrations that no longer exist
**Status:** VERIFIED
**Category:** Migrations / deployment
**Location:** `supabase/migrations/20261015054055_declarative_sync.sql:1-20`; `docs/DEPLOY_SUPABASE.md:110-111`, `docs/DEPLOY_SUPABASE.md:131-136`; `CLAUDE.md:43`; `supabase/README.md:12,20`
**Problem:** Commits `5d9e137` and `9065613` deleted `0001`–`0016` and the 29 generated `2026101[1-4]…` migrations. They replaced them with one baseline, `20261015054055_declarative_sync.sql` (11,817 lines; it starts with `create schema "private"` and creates every table), followed by 10 later files. The hosted dev project `ouxvtvlzhxddmqirmnxo` records 36 applied versions (`0001`…`0016` plus 20 generated), and none of them exists locally any more.
**Evidence:** `git log --diff-filter=D -- supabase/migrations` lists `0001_schema.sql … 0016_integrity_and_authz.sql` and `20261011202706…20261014203120` as deleted. DEPLOY doc §4: "must list exactly `0001` … `0016` followed by the generated migrations". §4a: "`supabase migration list --linked`: 36/36 match". CLAUDE.md: "(`0001`–`0016` = hand-written baseline)". README: "`schemas/public/tables/` | 35 tables" (there are 53).
**Impact:** `supabase db push` against hosted dev refuses ("remote migration versions not found in local migrations directory"). If someone forces it with `migration repair`, the baseline fails at `create schema "private"` / `create table` on a populated database. A "repair everything as applied" shortcut would also silently skip the baseline's newer objects, such as the staff module, which is in the later files, and money/RLS changes folded into the baseline. The runbook an operator would follow for production describes a migration list that cannot appear.
**Failure Scenario:** The owner follows DEPLOY_SUPABASE §4a to bring hosted dev up to date for the two-phone test. The push is refused, and an improvised `migration repair` leaves hosted dev with a schema that differs from `schemas/` while `migration list` shows "match".
**Recommended Fix:** Decide explicitly how hosted dev gets the new history: either (a) reset or recreate the hosted dev project and push the 11 current files to an empty database, or (b) `migration repair --status reverted` the 36 old versions and then apply a pg-delta diff generated against a dump of hosted dev, never the baseline. Then rewrite DEPLOY_SUPABASE §1/§4/§4a and the CLAUDE.md/README references to the current file list. The schema itself needs no change.
**Estimated Effort:** Small (docs) + Medium (hosted dev reset/repair)
**Production Blocker:** Yes, for the documented path (hosted dev validation precedes production). A brand-new production project would apply the 11 files cleanly, but that hasn't been verified on hosted.
**Suggested Verification:** `supabase migration list --linked` (read-only) against hosted dev. Locally: `supabase db reset --local`, then `supabase db schema declarative sync --no-apply` must report "No schema changes found".

## [P1][DB-002] Deleting a login cascades away that person's attendance evidence, leave history and finalised payroll lines
**Status:** VERIFIED (static FK chain)
**Category:** Data integrity / ON DELETE CASCADE on money and audit records
**Location:** `supabase/schemas/public/tables/staff_profiles.sql:27-28`; `staff_id` FKs with `on delete cascade` in `attendance_punches.sql:43`, `attendance_entries.sql:48`, `leave_requests.sql:43`, `leave_adjustments.sql:20`, `staff_pay_rates.sql:26`, `salary_run_lines.sql:31`, `salary_adjustments.sql:26`, `salary_deduction_decisions.sql:22`, `staff_hr_profiles.sql:22`, `staff_shifts.sql:21`; `docs/DEPLOY_SUPABASE.md:312`
**Problem:** `staff_profiles.user_id → auth.users ON DELETE CASCADE`, and every staff-module table references `staff_profiles(id) ON DELETE CASCADE`. Deleting an Auth user therefore deletes all of these rows for every arena that person belonged to:
- immutable punch evidence;
- attendance entries, including superseded and voided correction history;
- leave requests and adjustments;
- effective-dated pay rates;
- `salary_run_lines` and `salary_adjustments` of **finalised** salary runs.

Only `created_by → auth.users` FKs without cascade (sessions, payments, …) stop the delete, and only for people who ever wrote floor rows. A staff member whose punches, leave and entries were all created by themselves leaves no blocking reference.
**Evidence:** `constraint "staff_profiles_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade`; `constraint "salary_run_lines_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade`. The deploy doc says: "To remove the login entirely: Authentication → Users → delete."
**Impact:** Payroll records of a closed period disappear. `salary_runs.net_paise` stays but its lines are gone, so the payslip can no longer be reconstructed or proven. Attendance evidence is destroyed and no `audit_log` row records it. This contradicts the CLAUDE.md invariant "Money records are append-only" and the "finalised run locks its period" design. For floor staff the same delete instead fails with an FK error, so the documented step is unreliable either way.
**Failure Scenario:** An employee leaves. The owner deactivates them, then follows the doc and deletes the login in the Supabase dashboard. Every finalised salary line, pay rate and punch for that person is gone, with no PITR configured (DB-003).
**Recommended Fix:** In `schemas/public/tables/staff_profiles.sql`, change `staff_profiles_user_id_fkey` to `on delete restrict`, or make `user_id` nullable with `on delete set null` so the profile survives as a former employee. Change the staff-module `staff_id` FKs to `on delete restrict`, at least for `attendance_punches`, `attendance_entries`, `salary_run_lines`, `salary_adjustments`, `salary_deduction_decisions`, `staff_pay_rates` and `leave_*`. Update DEPLOY §7.7 to say "Deactivate; never delete a login that has history". Everything goes through pg-delta. The change is constraint-only and non-destructive, but it needs owner approval because it changes delete behaviour.
**Estimated Effort:** Small
**Production Blocker:** Yes
**Suggested Verification:** Add a pgTAP case that deletes an `auth.users` row that has a finalised run line and expects 23503. Run `supabase test db`.

## [P1][DB-003] No server-side backup / PITR policy and no migration rollback plan
**Status:** NEEDS VERIFICATION (deployed configuration)
**Category:** Backups / recoverability
**Location:** `docs/DEPLOY_SUPABASE.md:331`; `docs/RELEASE.md:14-60` (device backups only)
**Problem:** The deploy doc says no backup or PITR policy has been chosen for the hosted project. RELEASE.md covers only on-device SQLite backups and a manual Mac copy. Migrations are forward-only (no down scripts), and no step takes a logical dump before `db push`.
**Evidence:** "No backups/PITR policy has been chosen for the hosted project (plan-dependent)."
**Impact:** The server is the system of record for money, payroll and attendance, and attendance is online-only with no device copy. An operator error such as DB-002, a bad migration or a destructive SQL-editor statement has no recovery point beyond the plan's default daily snapshot, if any.
**Failure Scenario:** A migration with a mistaken data step, or a cascade delete, is applied on a Friday. On a plan without PITR, the nearest restore point could be up to 24 h old, so a day of payments and punches is lost.
**Recommended Fix:** Choose a plan with daily backups plus PITR for production, and document the retention and a tested restore drill. Add a "`pg_dump --schema-only` + `--data-only` of the linked project before every `db push`" step to DEPLOY §4. For each migration, write a short roll-forward note ("how to undo") instead of down scripts.
**Estimated Effort:** Small (config/docs) + plan cost
**Production Blocker:** Yes
**Suggested Verification:** Supabase dashboard → Database → Backups: confirm PITR is enabled and the retention period. Run one restore drill into a scratch project.

## [P2][DB-004] Append-only money and audit tables are protected only by missing grants; cascading FKs and the absence of guard triggers allow silent deletion or editing
**Status:** VERIFIED
**Category:** Data integrity / append-only enforcement
**Location:** `supabase/schemas/public/tables/payments.sql:24-37`; `group_payments.sql:24,35`; `session_charges.sql:29,39`; `group_charges.sql` (group FK cascade); `audit_log.sql:28`; `bill_discounts.sql` (session/group FKs `on delete cascade`); `sessions.sql:29-30`
**Problem:** `payments`, `group_payments`, `session_charges`, `group_charges`, `session_extensions`, `bill_discounts` and `controller_moves` cascade from `sessions` / `group_sessions` / `arenas`, and `audit_log` cascades from `arenas`. No trigger refuses UPDATE or DELETE on these tables. Append-only holds today only because clients have no write grants and no `op_*` deletes them; I checked this with a grep for `delete from` and `update public.payments`, and none exist.
**Evidence:** `constraint "payments_session_id_fkey" foreign key (session_id) references public.sessions(id) on delete cascade`; `constraint "audit_log_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade`.
**Impact:** Any of the following silently erases the payment ledger and audit trail, leaving only tombstones and no audit row: a dashboard or SQL-editor delete of a session or arena, a future `op_*` bug, or a service-role script. That defeats the "corrections are new rows" invariant.
**Failure Scenario:** An owner asks support to "remove a test session". `delete from sessions where id = …` removes its payments, charges and discount record, and the Sales report totals change retroactively with no trace.
**Recommended Fix:** (1) Change child FKs on money tables to `on delete restrict` (or `no action`): `payments`, `group_payments`, the `*_charges`, `*_extensions`, `bill_discounts` → session/group, and `audit_log` → arena. (2) Add a `before update or delete` trigger function (for example `_append_only()`, raising `append_only`) on `payments`, `group_payments`, `session_charges`, `group_charges`, `audit_log`, `salary_adjustments`, `attendance_punches` and `controller_moves`. Both are declarative edits to the table files. Arena deletion, if ever needed, becomes an explicit operator procedure.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** pgTAP: `throws_ok` on `delete from payments` and on `delete from sessions` that has payments, run as postgres. Run the full `supabase test db`, since some fixtures may rely on cascades for cleanup.

## [P2][DB-005] `sync_pull` materialises the entire remaining change feed for every page (quadratic first sync; 8 s timeout risk)
**Status:** VERIFIED (code); impact at scale LIKELY. The issue is partly acknowledged in `docs/SYNC.md:502-504`.
**Category:** Query performance / unbounded query
**Location:** `supabase/schemas/private/functions/sync_pull.sql:35-62`
**Problem:** The CTE `ch` is a `union all` over 33 sources selecting `to_jsonb(s)` for **every** row with `sync_xid >= cursor`. It is referenced by `g` and by the final aggregate, so it is materialised before the page cut (`cut`). Each page therefore costs O(all remaining rows), and a cursor-0 pull of N rows costs about N²/2000 row-serialisations in total.
**Evidence:** `'select %L::text as t, s.sync_xid as x, to_jsonb(s) as r from %I s where s.arena_id = $1 and s.sync_xid >= $2 and s.sync_xid < (select hi from snap)'`. SYNC.md: "with a long history it can exceed the 8 s statement timeout and leave that device 'offline'".
**Impact:** Several cases hit this: a new device, a reinstall, a re-login (cloud DB file is per arena/user), or a refused owner edit (which re-downloads from cursor 0). After a year of history, such a pull can time out under `authenticated`'s 8 s limit and retry forever. The affected device cannot work.
**Failure Scenario:** In month 10, a replacement tablet signs in, and the first `sync_pull` page exceeds 8 s on 200k+ rows. The device shows "Sync error" indefinitely.
**Recommended Fix:** Compute the cut from `(sync_xid)` only, using index-only scans on `(arena_id, sync_xid)`: count by xid until the limit is reached. Then run `to_jsonb` only for rows with `sync_xid < upper`. Optionally cap `p_limit` (it is uncapped above). Longer term, consider a snapshot or bootstrap endpoint for cursor 0 that excludes closed history older than N days.
**Estimated Effort:** Medium
**Production Blocker:** No (the risk grows with data)
**Suggested Verification:** Seed an arena with about 300k synced rows locally and time `sync_pull(cursor=>'0')` with `explain (analyze, buffers)`. Then run `tool/sync_it.sh` after the change.

## [P2][DB-006] The "finalised period" lock is check-then-act without a lock, so a correction can commit into a period being finalised
**Status:** LIKELY
**Category:** Concurrency / locking (payroll)
**Location:** `supabase/schemas/public/functions/_period_finalised.sql` (plain `exists` on `salary_runs`); callers `op_attendance_correct.sql:50,78`, `op_leave_request.sql:59`, `op_leave_cancel.sql:27`, `op_leave_record.sql:57`, `op_leave_decide.sql:42`; `op_salary_run_finalise.sql:22-30`; `_pay_draft.sql:15`
**Problem:** Finalise locks only its own `salary_runs` row, rebuilds the lines from attendance and leave, and flips the status. The guarded writers read `salary_runs` without any lock. Under READ COMMITTED, a correction can pass `_period_finalised` (the run is still a draft) and commit after finalise's rebuild has read the old rows.
**Evidence:** `select exists (select 1 from salary_runs where arena_id = p_arena and status = 'finalised' and period_start <= p_to and period_end >= p_from);`
**Impact:** A finalised run's stored lines can disagree with `_att_day`/leave data for its own period. That breaks the "a finalised salary run locks its period" guarantee in CLAUDE.md, and nothing detects it afterwards.
**Failure Scenario:** The owner clicks Finalise while a manager approves a leave or corrects a clock-out for a day in that period. Both succeed: the payslip omits the change, and the calendar shows it.
**Recommended Fix:** Serialise per arena and payroll. For example, take `pg_advisory_xact_lock(hashtextextended('payroll:'||p_arena::text,0))` inside `_period_finalised` (rename it to `_period_lock_check`) and in `op_salary_run_finalise` before the rebuild. Alternatively, have `_period_finalised` take `for share` on overlapping `salary_runs` rows and have finalise re-check after its rebuild.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Add a two-connection race script in `supabase/concurrency_tests/` modelled on `run.sh`: finalise in A with `pg_sleep`, `attendance.correct` in B. Expect B to get `period_finalised`.

## [P2][DB-007] Concurrent leave approvals for the same person can both draw on the same paid-leave balance
**Status:** LIKELY
**Category:** Concurrency / locking
**Location:** `supabase/schemas/public/functions/op_leave_decide.sql:37-38,53`
**Problem:** `op_leave_decide` locks only the request row (`for update`) and then computes the paid share from `_leave_balance(...)`. `op_leave_request` (line 35) and `op_leave_record` (line 43) serialise on the `staff_profiles` row, but `op_leave_decide` doesn't. Two approvals of different requests by the same person can run in parallel, and neither sees the other's uncommitted paid days.
**Evidence:** `select * into v_r from leave_requests where id = (p->>'id')::uuid and arena_id = p_arena for update;` … `v_left := greatest(0, (_leave_balance(v_r.staff_id, v_r.from_date)->>'balance')::numeric);`
**Impact:** Paid leave can exceed the entitlement, so salary is overpaid and the LOP deduction is lost.
**Failure Scenario:** Two managers with `leave_approve` approve two pending requests from the same employee at the same moment. Each takes the remaining 2 paid days, so 4 paid days are granted against a balance of 2.
**Recommended Fix:** In `op_leave_decide`, before computing the balance, lock the staff row the same way the other leave ops do: `perform 1 from staff_profiles where id = v_r.staff_id for update`. Do the same in `op_leave_adjust`, which has no lock (see the grep list).
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Two-connection race test approving two requests for the same staff member; the total `paid_days` must be at most the balance.

## [P2][DB-008] `sync_push` error handling: transient failures become permanent rejections, and some malformed ops abort the whole batch
**Status:** VERIFIED (code paths); impact LIKELY
**Category:** Idempotency / transaction semantics
**Location:** `supabase/schemas/private/functions/sync_push.sql:35-80`
**Problem:**
1. Any SQLSTATE not in `('40001','40P01','55P03','57014')` is stored in `sync_ops` as `rejected` with `server_error`, or with a mapped code. That includes transient ones such as `53xxx` (resources), `08xxx` and `XX000`. A later retry of the same `op_id` replays that rejection forever.
2. `57014` (statement timeout) can never reach the handler: PL/pgSQL `others` doesn't catch `query_canceled`, so a timeout aborts the whole RPC. That rollback is safe, but the branch is dead code.
3. Three cases raise outside the per-op block and abort the entire batch, including ops already applied in this call:
   - `(v_op->>'op_id')::uuid` on a non-uuid value (line 36);
   - `op_id_reused` (line 42);
   - a null `op_id` (the rejected-row insert in the handler violates the PK).

   The client then resends the same batch and stalls behind this "poison" op.
4. There is no server-side cap on the number of ops per call (the client sends 50).

**Evidence:** `if v_state in ('40001', '40P01', '55P03', '57014') then … 'retry'`; `else 'server_error' end;` followed by `insert into sync_ops(… 'rejected', v_code …)`. The `if v_prev.arena_id <> p_arena then raise exception 'op_id_reused'; end if;` check sits outside the inner `begin … exception`.
**Impact:** A money op (`payment.record`, `session.end`) that hits a transient server fault is permanently refused. Staff must re-key it from "Needs attention", which the app does surface, so this isn't silent loss. A single malformed op blocks every later op from that device.
**Failure Scenario:** During a brief resource exhaustion on hosted, five queued payments come back `server_error`, and replays keep returning `rejected` even after the server recovers.
**Recommended Fix:** Treat only deterministic classes (`P0001` business codes, `22*`, `23*`, `42501`) as `rejected`. For everything else, return `retry` without writing `sync_ops`. Move the uuid cast and the `op_id_reused` check inside the per-op block so they reject just that op. Drop `57014` from the list, or document it. Add `if jsonb_array_length(p_ops) > 100 then raise …`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP in `07_sync_ops_test.sql`: a batch containing a non-uuid `op_id` should still apply its other ops, and a simulated non-business error (for example via a test-only op) should return `retry` and leave no `sync_ops` row.

## [P2][DB-009] Audit trail gaps: permission, pay-rate, price-list and payroll-control changes leave no who/what record
**Status:** VERIFIED
**Category:** Audit coverage
**Location:** `supabase/schemas/public/functions/` — `audit_log` is written only by `op_attendance_correct`, `op_attendance_review`, `op_customer_create`, `op_group_end`, `op_group_void`, `op_leave_record`, `op_leave_decide`, `op_payment_correct`, `op_salary_run_finalise`, `op_session_end`, `op_session_void`. `supabase/schemas/public/tables/sync_ops.sql:10-26` (no payload column).
**Problem:** None of these write `audit_log`:
- `op_staff_update` (permissions and roles, edited in place);
- `op_rate_upsert/_delete`, `op_policy_save`, `op_settings_save`, `op_rule_*`, `op_discount_*`;
- `op_pay_rate_add`, `op_pay_policy_add`, `op_hr_profile_save`;
- `op_salary_run_discard`, `op_salary_run_set_deduction`.

`sync_ops` records `user_id`, `kind` and the time but not the op payload. `pricing_catalog_history` keeps the old price list but not who replaced it.
**Evidence:** The grep `insert into audit_log` matches only the 11 files listed. The `sync_ops` columns are `op_id, arena_id, user_id, device_id, kind, status, result, error_code, error_message, created_at`.
**Impact:** Some questions can't be answered after the fact: who granted `money` to a staff member, who changed the hourly rate before a dispute, who discarded a salary run. For a cash business, permission and price history is the main fraud-investigation trail.
**Failure Scenario:** A staff member is briefly given `discount`, waives several bills, and has it removed again. The waives are audited, but the grant and revocation are invisible.
**Recommended Fix:** Insert `audit_log` rows (before/after jsonb) in `op_staff_update`, the pricing ops (one row per `_sync_apply` pricing change, written next to the `pricing_catalog_history` insert), the pay-rate and pay-policy adds, and the salary-run discard and set-deduction ops. Alternatively, store a redacted `payload jsonb` in `sync_ops` for config ops.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** pgTAP: after `staff.update` and `rate.upsert`, `audit_log` contains a row with `created_by = auth.uid()` and the before/after values.

## [P2][DB-010] `arena_overview` and `_sales` scan every closed bill and build full JSON per bill over windows of up to 400 + 400 days
**Status:** LIKELY
**Category:** Query performance
**Location:** `supabase/schemas/public/functions/_sales.sql:63,128-129,215-216`; `supabase/schemas/private/functions/arena_overview.sql:44-56`
**Problem:** The close-time filter is on the computed `coalesce(actual_ended_at, updated_at)`, which no index covers. Only `(arena_id, status)` helps, so every call reads all closed sessions and groups of the arena. For each bill in range, `_sales` builds the full object: stations, activities, games, payments ledger, audit lookups, returning-customer `exists` and discount. `arena_overview` calls it twice, for the current and previous window, each up to 400 days, only to sum a few numbers.
**Evidence:** `cross join lateral (select coalesce(s.actual_ended_at, s.updated_at) as at) b` … `where s.arena_id = p_arena and s.status <> 'active' and (case when p_id is null then b.at >= p_from and b.at < p_to …)`; `select x as b … from _sales(p_arena, p_from, p_to) x` … `from _sales(p_arena, p_prev_from, p_prev_to) x`.
**Impact:** The owner dashboard's year view times out (8 s) once history grows to tens of thousands of bills.
**Failure Scenario:** After 12 months, about 40k bills; Overview → "This year vs last year" returns a timeout error.
**Recommended Fix:** Add `create index … on sessions (arena_id, actual_ended_at) where status <> 'active'` and the same on `group_sessions`, and filter on `actual_ended_at` directly. A void should set `actual_ended_at`, or the filter should use an explicit `closed_at` column, so it doesn't depend on a mutable `updated_at`. Give `arena_overview` a lean aggregate path (sums from `payments` grouped by bill) instead of the full `_sales` objects.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** Seed a large arena locally and run `explain analyze select arena_overview(…, 400-day range …)`. Re-run `14_admin_sales_test.sql` and `26_admin_reads_test.sql`.

## [P3][DB-011] Missing state- and money-consistency CHECKs; `group_charges` has no line-uniqueness key
**Status:** VERIFIED
**Category:** Constraints
**Location:** `supabase/schemas/public/tables/sessions.sql:10-44`, `group_sessions.sql`, `session_extensions.sql`, `group_extensions.sql`, `session_charges.sql:7-40`, `group_charges.sql`
**Problem:** Several invariants rely entirely on `op_*` code:
- `billed_amount_paise`, `added_amount_paise`, `unit_price_paise` and charge `amount_paise` have no `>= 0` check (payments, rates and discounts do have sign checks);
- `status = 'completed'` isn't tied to `actual_ended_at is not null and billed_amount_paise is not null`;
- `group_charges` lacks the `unique (group_id, charge_index)` that `session_charges` has (`unique (session_id, segment_index)`).

The key-array comparison in `op_group_end` currently catches duplicate lines.
**Impact:** Defence in depth only. A future op bug or a manual SQL fix could store a negative bill or a completed bill with no amount, and nothing would stop it.
**Recommended Fix:** Add `check (billed_amount_paise is null or billed_amount_paise >= 0)` and the same for the other paise columns. Add `check (status <> 'completed' or (actual_ended_at is not null and billed_amount_paise is not null))` on sessions and groups, and `unique (group_id, charge_index)` on `group_charges`. First validate existing hosted rows with a read-only query. Defining the constraints as `not valid` in pg-delta is not expressible, so check the data before pushing.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Run a read-only `select count(*) … where billed_amount_paise < 0 …` on hosted, then `supabase test db`.

## [P3][DB-012] Unbounded growth of `sync_ops` and `sync_tombstones` (no retention); tombstones hold whole deleted rows and have no arena FK
**Status:** VERIFIED
**Category:** Storage / maintenance
**Location:** `supabase/schemas/public/tables/sync_ops.sql:10-26`; `supabase/schemas/public/tables/sync_tombstones.sql`; `supabase/schemas/public/functions/sync_record_delete.sql`
**Problem:** Every op, with its `result` jsonb, is kept forever. Each tombstone stores `to_jsonb(old)` (the full deleted row) and is sent to every device that pulls from cursor 0. No job prunes either table, there is no `pg_cron`, and `sync_tombstones` has no FK to `arenas`.
**Impact:** Slow growth of storage and of initial-sync payloads (adds to DB-005). Full-row tombstones also re-ship deleted catalogue data to new devices.
**Recommended Fix:** Store only the key in `row_key` (the `id`, or the PK columns for composite tables). Define retention: keep `sync_ops` for N days beyond the longest offline window the app supports, and drop tombstones older than the oldest cursor still in use, or older than N days with a forced full resync.
**Estimated Effort:** Small–Medium
**Production Blocker:** No
**Suggested Verification:** Check `select pg_total_relation_size('sync_ops'), pg_total_relation_size('sync_tombstones')` on hosted periodically.

## [P3][DB-013] Some FK columns are covered only by partial indexes
**Status:** LIKELY
**Category:** Indexing
**Location:** `supabase/schemas/public/tables/controller_allocations.sql:95-110`
**Problem:** `controller_allocations.controller_id` and `resource_id` have only `where ended_at is null` indexes (`ux_one_open_allocation_per_controller`, `ix_alloc_open_by_resource`). FK checks on controller or resource delete/update, and any per-pad history query ("who had pad X last week"), can't use them and fall back to sequential scans of the arena's whole allocation history.
**Recommended Fix:** Add `create index ix_alloc_controller_time on controller_allocations (controller_id, started_at)`, and a full index on `resource_id` if history queries need it.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `supabase db advisors --local --type performance` (unindexed foreign keys).

## [P3][DB-014] `arenas.timezone` exists but every function hard-codes +05:30 / Asia/Kolkata
**Status:** VERIFIED
**Category:** Schema design / generalisation
**Location:** `supabase/schemas/public/tables/arenas.sql` (`"timezone" text not null default 'Asia/Kolkata'`); `supabase/schemas/public/functions/_pr_ist_date.sql:16`, `_att_blocks.sql:23-25`, `_pr_rule.sql:21-22`, `arena_overview.sql:70`
**Problem:** The column suggests that per-arena time zones are supported, but no function reads it. The timezone handling itself is explicit and correct (no reliance on the session `TimeZone`).
**Impact:** A future non-IST venue would be billed and paid on IST days. This is consistent with CLAUDE.md today, but it is a trap for generalisation.
**Recommended Fix:** Document the column as reserved and add `check (timezone = 'Asia/Kolkata')` until multi-timezone support exists, or plan the change in `docs/GENERALIZATION.md`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** —

## [P3][DB-015] Migration history contains an add-then-drop column, and a test fixture function ships to production
**Status:** VERIFIED
**Category:** Migrations hygiene
**Location:** `supabase/migrations/20261015113420_overtime_grace.sql:3-4` (adds `billing_policies.overtime_grace_minutes`); `supabase/migrations/20261015114137_overtime_grace_per_type.sql:3-7` (drops it); `supabase/schemas/public/functions/_seed_arena_catalog.sql`
**Problem:** On a fresh database the pair is harmless, because the column is added and dropped about 7 minutes apart. It is still a `drop column` in the deployable history, and CLAUDE.md requires explicit approval for destructive migrations. If any environment has run the first file and stored values, applying the second destroys them. `_seed_arena_catalog` is described as "a test fixture only" but is part of the production schema. It is server-only (no client EXECUTE), so the issue is surface area, not exposure.
**Recommended Fix:** Before the first production push, record in DEPLOY §4 that the drop is expected. If hosted is reset (DB-001), you could regenerate a clean baseline so the pair never ships. Move `_seed_arena_catalog` into the pgTAP setup or `tool/` SQL, and out of `schemas/`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** `supabase db push --dry-run` output review.

## [P3][DB-016] No automated check that migrations reproduce `schemas/`
**Status:** VERIFIED
**Category:** Migrations / drift
**Location:** `tool/verify_all.sh:21-22,67-75` (pgTAP and advisors only); no `.github/` directory
**Problem:** The "re-run `declarative sync --no-apply` must say No schema changes found" step is manual, and `verify_all.sh` doesn't run it. pgTAP runs against the **migrated** database, so drift between `schemas/` and `migrations/` isn't caught until the next generated migration unexpectedly contains it.
**Recommended Fix:** Add a step to `verify_all.sh` that runs `supabase db schema declarative sync --no-apply` and fails unless the output is "No schema changes found". Run `verify_all.sh` in CI on PRs touching `supabase/`.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Run the new step locally on a clean tree.

---

## Controls verified as sound

- **Idempotent, ordered op application.** `sync_push` takes `pg_advisory_xact_lock(hashtextextended(op_id))`, checks `sync_ops` (PK `op_id`), applies each op in its own savepoint and replays the stored answer (`private/functions/sync_push.sql:39-47`). Client-generated entity ids are primary keys, so a payment re-sent under a new op id fails with `23505`.
- **Commit-safe change feed.** `sync_pull` reads only `sync_xid < pg_snapshot_xmin(pg_current_snapshot())`, so in-flight transactions are never skipped. Pages cut on whole-transaction boundaries, and a single large transaction is still delivered (`run - c > 0`) (`sync_pull.sql:46-56`). All 32 synced tables have `(arena_id, sync_xid)` indexes; I grepped every source in `_sync_sources()`.
- **Cross-tenant references.** `t_same_arena` covers every non-arena FK column on every arena table I enumerated: sessions, segments, charges, payments, groups, allocations, moves, controllers, bookings, rates, resource_activities, games, bill_discounts and all staff tables. Activity codes use composite FKs `(arena_id, activity_code) → activities(arena_id, code)`.
- **Single-occupancy guarantees.**
  - `ux_one_open_segment_per_resource` (partial unique), plus triggers that lock `resources … for update` before counting open segments and assignments (`assert_resource_free_for_segment.sql`), are covered by `concurrency_tests/run.sh`.
  - `ux_one_open_allocation_per_controller`, plus a locking trigger, is covered by `run_pads.sh`.
  - `ux_attendance_entries_open` (one open clock-in per person) and the `attendance_entries_no_overlap` GiST exclusion.
  - `staff_shifts_no_overlap`, `salary_runs_no_overlap` and `staff_invites_one_open`.
  - `ux_bill_discounts_session/_group` (one discount per bill); `salary_adjustments_reverses_id_key` (one reversal each).
- **Money locking.** `op_payment` locks the parent session or group `for update` before summing the ledger (overpayment and over-refund are race-free). The same holds for `op_session_end`, `op_session_void`, `op_payment_correct` and `_group_active` (used by group ops). `_discount_apply` locks the discount row before counting uses.
- **Money types.** Money is `bigint` paise, and the payment sign is enforced by CHECK (`payments_amount_sign_check`, `group_payments_amount_sign_check`). No `float`/`double` appears in any pricing or payroll function; only geofence math uses `double precision`. Payroll works in `numeric` and rounds to `bigint` at the end (`_pay_build_line.sql:244`). Cash rounding happens once in `_pr_money`.
- **Time.** All instants are `timestamptz`. Every IST conversion is explicit (`_pr_ist_date`, `_att_blocks`, `at time zone 'Asia/Kolkata'`); there's no `current_date` or `now()::date`. Attendance uses `statement_timestamp()` as server time.
- **RLS performance.** Policies use `arena_id in (select private.app_arena_ids())`, which is evaluated once rather than per row. `staff_profiles(user_id)` is indexed (`ix_staff_user`).
- **Bounded reads.** `arena_sales` allows at most 93 days, `arena_overview` and `arena_station_stats` 400 days, `attendance_days` 62 days. `arena_members`, `arena_activity`, `arena_game_fans` and `arena_discount_usage` clamp their limits.
- **Seed.** `supabase/seed.sql` is comments only, with no logins or demo data. `_seed_arena_catalog` has no client EXECUTE.
- **Additive changes on populated tables.** New NOT NULL columns in the later migrations carry defaults (`overtime_grace_minutes integer not null default 0`). The staff tables are new. Apart from DB-015 there's no type change, rename or data rewrite.
- **Catalogue deletes are FK-backstopped.** Segments, assignments and allocations reference `games`, `resources` and `activities` without cascade, so deleting used catalogue rows fails.

## Not reviewed / needs verification

- **Deployed configuration (NEEDS VERIFICATION):** backup and PITR plan, whether hosted Postgres role timeouts match the 8 s local assumption, and the hosted migration list. None of these can be checked statically.
- **Whether the 11 current migrations reproduce `schemas/` exactly:** not executed (no `supabase db reset` or declarative sync was run). It needs the DB-016 check.
- **Not read in full:** the ~150 other `op_*` and `_pr_*` bodies, including pricing parity with Dart. Session/group start, reconfigure, switch and pad-lock ordering were reviewed only through README/SYNC.md and the trigger backstops. Pricing semantics belong to the business-logic auditor.
- **Concurrency test coverage:** only the station race (`run.sh`) and pad races (`run_pads.sh`) exist. Nothing covers concurrent payments, payroll finalise vs corrections (DB-006), leave approvals (DB-007), double punch-in or discount use limits.
- **Not checked:** subtransaction overflow (more than 64 subxacts) for 50-op batches with nested handlers, and the `realtime.messages` policies and publication (security auditor). Supabase advisors weren't run.
- **Stale docs (not schema defects):** pgTAP `00_schema_parity_test.sql` still refers to "Drift v11". `supabase/audit/security_audit.sql` has an outdated allow-list, as the README already acknowledges.
