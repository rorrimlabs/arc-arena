# 01 — Security audit (pre-production)

**Area:** Security (IDs SEC-001…) · **Branch:** `feature/venue-generalization` @ `24a4bdd` · **Date:** 2026-10-16
**Method:** read-only static analysis of `supabase/schemas/**` (source of truth), `supabase/config.toml`, `supabase/templates`, migrations (structure only), `apps/admin/src/app/core/**` + auth/users features, `apps/mobile/lib/app/sync/**`, git index and git history (secrets scan, values never printed). No database, Docker, test suite, network or hosted-project access was used. Line numbers verified with `grep -n` against the current tree.

Severity counts: **P0 0 · P1 0 · P2 4 · P3 8**.

---

## Trust-boundary map

| Principal | What it can reach (as written in `schemas/`) | Evidence |
|---|---|---|
| `anon` | Nothing: every table/view/sequence/function file revokes `anon`; default privileges revoke too. Only Auth endpoints (sign-up, OTP, password reset) are reachable without a session. | `public/default_privileges.sql`, `private/default_privileges.sql`; every object file ends with `revoke … from anon` (scripted check: 0 files missing) |
| `authenticated` | `SELECT` on 47 tables under RLS (arena membership, narrower for money/customer/audit/pay/attendance). `EXECUTE` on exactly 25 `public` wrappers (all `security invoker`) and on the 28 `private` definer bodies (reachable only through those wrappers or RLS, since `private` is not in `[api] schemas`). `realtime.messages` select/insert on `arena:<uuid>` topics for active members. No insert/update/delete policies anywhere. | `tests/13_security_hardening_test.sql:89-97`; `config.toml:13`; `realtime/policies.sql` |
| Definer (`postgres`) | `private.*` client API bodies and `public.op_*` / `_*` server helpers. All 133 public + 28 private definers pin `search_path`; none in `public` is client-executable. Writes only via `sync_push → _sync_apply → op_*`, each with `_need(arena, perm)` or an explicit self-scope (`user_id = auth.uid()`). | scripted check (0 definers without `set search_path`); `public/functions/_sync_apply.sql`, `_need.sql` |
| `service_role` | Everything. Not in any app, not in git history (scan: 0 `sb_secret_`, 0 service-role JWTs; the only JWT ever committed decodes to `role: anon`). Previously used by the now-removed `staff-admin` Edge Function (see SEC-002). | `git log --all -p` scan |

---

## Findings

## [P2][SEC-001] Every active member can bulk-download the arena's customers and full money ledger through `sync_pull` / `sync_fetch_entity`, bypassing the narrowed RLS
**Status:** VERIFIED
**Category:** Authorization / intra-tenant data exposure (PII)
**Location:** `supabase/schemas/private/functions/sync_pull.sql:30-49`, `supabase/schemas/public/functions/_sync_sources.sql:18-34`, `supabase/schemas/private/functions/sync_fetch_entity.sql:31,41-67`, `supabase/README.md:59`
**Problem:** RLS deliberately restricts `customers` to `start/members/money/reports` and `payments`, `group_payments`, `session_charges`, `group_charges`, `bill_discounts` to `bill/money/reports`. But `sync_pull` (SECURITY DEFINER) only checks `app_arena_ids()` membership and then returns every row of every `_sync_sources()` relation, which include `customers`, `payments`, `session_charges`, `group_payments`, `group_charges`, `bill_discounts`, `discounts` (coupon codes) and all `staff_profiles` perms. `sync_fetch_entity` does the same per entity. The RLS narrowing therefore protects only direct table reads, not the data itself.
**Evidence:** `if p_arena is null or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then raise … 'forbidden'` (no permission check), then `('customers','customers') … ('payments','payments') … ('bill_discounts','bill_discounts')`. README: "every active member's device still receives the arena's rows it needs offline, payments and customers included. Whether floor devices should hold less is an open product decision."
**Impact:** Any login with an active profile — including the attendance-only staff the new staff module invites with `perms = {}` (cleaners, part-timers who only clock in) — can call `rpc('sync_pull', {p_arena, p_cursor:'0'})` and page out every customer's name, phone, notes and birth year plus every payment/refund/charge. Customer phone numbers are personal data (India DPDP Act). The data also lands in the device's unencrypted Drift file (SEC-010).
**Failure Scenario:** Owner invites a cleaner (no perms) so they can clock in. The cleaner, or anyone holding their phone/session, runs a 10-line script with the publishable key and their password and exports the customer list.
**Recommended Fix:** Decide the open product question before production. Minimal server change: in `sync_pull`/`sync_fetch_entity`, filter sensitive relations by `private.app_has_perm` (customers: start|members|money|reports; money tables: bill|money|reports; discounts' `code`: discount|settings), e.g. pass an allowed-set into `_sync_sources()` usage. Members with no floor perms should get only catalog + their own profile. Mobile already tolerates missing tables (it only reads what it pulls), but verify.
**Estimated Effort:** Medium
**Production Blocker:** No (becomes Yes if attendance-only staff accounts will be issued, which is the staff module's purpose)
**Suggested Verification:** pgTAP: create a member with `perms = '{}'`, set `request.jwt.claims`, call `private.sync_pull(arena,'0',2000)` and assert no change with `t in ('customers','payments','session_charges','group_payments','group_charges','bill_discounts')`.

## [P2][SEC-002] Hosted project likely still carries objects removed from the repo (incl. the `staff-admin` service-role Edge Function deployed `--no-verify-jwt`); migration history was rewritten
**Status:** NEEDS VERIFICATION
**Category:** Deployment drift / orphaned privileged endpoint
**Location:** `docs/DEPLOY_SUPABASE.md:136-139,309`; `supabase/migrations/` (now starts at `20261015054055_declarative_sync.sql`, a full `create table` baseline); removed file `supabase/functions/staff-admin/index.ts` (last in `5d9e137^`)
**Problem:** The doc records that the hosted dev project has `0001…0016` + 20 generated migrations and a deployed `staff-admin` Edge Function (`--no-verify-jwt`, `ADMIN_ORIGINS` unset = any origin), with an owner to-do "delete it there". The repo no longer contains those migrations or the function, and the new baseline drops nothing, so anything deleted from `schemas/` (e.g. `invite_delivery_target`, `_v1` op wrappers, older RPCs) stays on hosted unless removed by hand.
**Evidence:** DEPLOY doc: "`staff-admin` deployed (`--no-verify-jwt`, …) — since removed from the repo: delete it there with `supabase functions delete staff-admin`". Old function: holds `SUPABASE_SERVICE_ROLE_KEY`; for an unconfirmed target login it calls `admin.auth.admin.updateUserById(t.user_id, { password: randomSecret() })` and `inviteUserByEmail`.
**Impact:** If still deployed: any self-registered owner (sign-up is open; every owner holds `settings` in their own arena) can make the function scrub the password of any **unconfirmed** login on the project (sabotaging sign-ups in progress) and send Auth invite e-mails via the admin API. Stale definer functions on hosted are outside test 13's assertion until it is re-run there.
**Failure Scenario:** Attacker registers an arena, POSTs `{arena_id: own, email: victim@…}` to `/functions/v1/staff-admin` with their JWT; victim's pending account password is reset and they receive an unsolicited invite.
**Recommended Fix:** Before go-live: `supabase functions list` on hosted and delete `staff-admin`; run `supabase/tests/13…` assertions (or `supabase db advisors --linked` + the test-13 function list query) against hosted; produce a schema diff hosted-vs-`schemas/` and drop leftovers; decide how hosted migration history is reconciled with the rewritten baseline (`migration repair`) without `db reset`.
**Estimated Effort:** Small (ops) / Medium (history reconciliation)
**Production Blocker:** Yes (until verified)
**Suggested Verification:** On hosted, read-only: `select proname from pg_proc where pronamespace='public'::regnamespace and has_function_privilege('authenticated',oid,'execute')` must equal test 13's list; `supabase functions list` must be empty.

## [P2][SEC-003] Payroll / leave holders can act on their own pay and leave records (own-record rule S7 not enforced on five ops)
**Status:** VERIFIED
**Category:** Authorization / separation of duties (money)
**Location:** `supabase/schemas/public/functions/op_leave_adjust.sql:24-34`, `op_pay_rate_add.sql:29-49`, `op_salary_adjustment_add.sql:27-39`, `op_hr_profile_save.sql:25-53`, `op_salary_run_set_deduction.sql:25-34`
**Problem:** `docs/STAFF.md:47,186,911` and `docs/STAFF_API.md:31-32` decide that only `role='owner'` may act on their own records (`own_record`). `_own_record()` is called in `op_attendance_correct/review` and `op_leave_decide/record`, but not in `leave.adjust`, `pay_rate.add`, `salary_adjustment.add`, `hr_profile.save`, `salary_run.set_deduction`.
**Evidence:** `op_leave_adjust`: `perform _need(p_arena, 'leave_approve'); if not exists (… id = v_staff and arena_id = p_arena) … insert into leave_adjustments(…)` — no `_own_record(p_arena, v_staff)`. Same shape in the four payroll ops.
**Impact:** A non-owner manager with `leave_approve` can credit themselves paid-leave days (turning LOP into paid salary); a non-owner `payroll` holder can raise their own rate, add a bonus to their own line, change their own `paid_leave_days`/`tracks_attendance`, or waive their own deductions. `leave_approve` is grantable by any `settings` holder (`op_staff_update` only guards money/reports/payroll).
**Failure Scenario:** Shift manager with `leave_approve` sends `leave.adjust {staff_id: <self>, days: 10, reason: "carry-over"}`; the next salary run pays the extra days.
**Recommended Fix:** Add `perform _own_record(p_arena, v_staff);` after the arena check in these five ops (and any other op taking a `staff_id` that affects pay). Add `own_record` to their refusal lists in `docs/STAFF_API.md`.
**Estimated Effort:** Small
**Production Blocker:** No (Yes if non-owner managers will hold `payroll`/`leave_approve`)
**Suggested Verification:** pgTAP: as a non-owner holding `leave_approve`/`payroll`, push each op targeting own `staff_id`; expect `rejected`/`own_record`; as owner, expect `applied`.

## [P2][SEC-004] No bot protection on public Auth endpoints: project-wide e-mail quota can be exhausted and "invitation"-branded mail sent to anyone
**Status:** LIKELY
**Category:** Auth configuration / abuse, DoS
**Location:** `supabase/config.toml:180,205,215,229`; `supabase/templates/magic_link.html:1-3`, `confirmation.html:1-6`; `apps/admin/src/app/features/users/data/users-api.ts:144-146`; `docs/DEPLOY_SUPABASE.md:83`
**Problem:** Sign-up is open, CAPTCHA is not implemented (no `captcha` anywhere in either app, so the deploy doc's "turn on CAPTCHA once the app sends a token" cannot be done), and `email_sent = 30` per hour is project-wide. `/auth/v1/otp` and `/auth/v1/signup` accept any address with the public key; the magic-link template is titled "You're invited to 404 Arena" and the confirmation template shows an "Accept the invitation" link whenever `redirect_to ≠ Site URL`.
**Evidence:** `email_sent = 30`; `enable_signup = true`; `signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: link.href … } })` (same call is available to anyone).
**Impact:** A script sending ~30 OTP/sign-up requests per hour blocks every legitimate sign-up code, invitation and password reset for all tenants; the venue's SMTP sender can be used to send invitation-looking mail to arbitrary people (reputation/phishing), and unconfirmed accounts can be squatted on any address (feeds SEC-005).
**Failure Scenario:** Competitor loops `signInWithOtp` for random addresses; owners cannot onboard staff or reset passwords for hours.
**Recommended Fix:** Implement Turnstile/hCaptcha tokens in admin register / sign-in / forgot-password / invite send, then enable CAPTCHA in hosted Auth; raise `email_sent` with custom SMTP; consider `shouldCreateUser: false` for invites to existing confirmed logins and a server-side sender for new ones; keep per-IP limits.
**Estimated Effort:** Medium
**Production Blocker:** No (strongly recommended)
**Suggested Verification:** Local: 31 `signInWithOtp` calls in an hour → 31st returns 429 for everyone; confirm on hosted dashboard what limits are set.

## [P3][SEC-005] Pre-registered (attacker-password) accounts: invite acceptance relies on a client-only password step and does not end other sessions
**Status:** NEEDS VERIFICATION
**Category:** Account takeover (pre-hijack)
**Location:** `apps/admin/src/app/features/auth/accept-invite.ts:364-367`; `apps/admin/src/app/core/auth/invitee-auth.ts:77`; `supabase/schemas/private/functions/accept_invite.sql:53-62`; `users-api.ts:144-146`
**Problem:** The old `staff-admin` scrubbed the password of an unconfirmed target server-side. Now an unconfirmed login (password chosen by whoever signed it up) is confirmed by the real invitee clicking the e-mail; the "choose your own password" step is enforced only in the browser, and `accept_invite` checks only `email_confirmed_at`. Between confirmation and `updateUser({password})`, the pre-registrant can sign in with their password; whether GoTrue revokes that session on password change, and the remaining access-token lifetime (`jwt_expiry = 3600`), decide whether they keep access after the victim accepts.
**Evidence:** `this.step.set(this.link.type === 'magiclink' ? 'confirm' : 'password');` (client); server: `if v_confirmed is null then raise 'email_not_confirmed'` only.
**Impact:** An ex-employee or insider who knows an address will be invited can obtain a session on the invitee's login and read the arena (sync_pull) once the invite is accepted.
**Failure Scenario:** Attacker signs up `newhire@…` (unconfirmed). Owner invites `newhire@…`; new hire clicks, account confirmed; attacker signs in during the password step; new hire sets password and accepts.
**Recommended Fix:** After the password is set on `/accept-invite`, call `signOut({scope:'others'})` (or `global`) before `accept_invite`; server-side, refuse `accept_invite` when the account's password was set before `email_confirmed_at` and not changed since (compare `auth.users.updated_at`/a recorded `password_set_at` claim) or require AAL/`amr` freshness.
**Estimated Effort:** Small–Medium
**Production Blocker:** No
**Suggested Verification:** Local stack + Mailpit: reproduce the sequence with two browsers; check whether the attacker's refresh token still works after the victim's `updateUser`.

## [P3][SEC-006] `accept_invite` authority re-check and overwrite are weaker than `op_staff_update`
**Status:** VERIFIED
**Category:** Authorization consistency
**Location:** `supabase/schemas/private/functions/accept_invite.sql:64-77,82-86`; `private/functions/invite_member.sql:65`; `public/functions/op_staff_update.sql:55-66`
**Problem:** (a) `invite_member` requires owner level for `money, reports, payroll, payroll_finalise`, but `accept_invite`'s inviter re-check covers only `money, reports`, so an invite carrying `payroll` stays valid after its inviter loses owner level. (b) Acceptance `on conflict (user_id, arena_id) do update set role, perms, active = true` overwrites an existing profile: a non-owner `settings` holder can, with the target's click, replace an owner-level (money/reports) staff member's perms or reactivate someone an owner deactivated — both refused by `op_staff_update`.
**Evidence:** `(not (v_inv.perms && array['money', 'reports']) or role = 'owner' or perms && array['money', 'reports'])`.
**Impact:** Low (needs a valid invite and the target's acceptance), but it is a second path around rules the op enforces.
**Failure Scenario:** Settings holder re-invites a deactivated owner-level member with `settings` perms; the member accepts and is back with access an owner removed.
**Recommended Fix:** Use the same perm list in the re-check; in `accept_invite`, when a profile exists, refuse (`member_exists`) unless the inviter would pass `op_staff_update`'s owner-level rules for that profile.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** pgTAP: invite with `payroll` by a money-holder, remove their money, accept → expect `invite_invalid`.

## [P3][SEC-007] `sync_push` returns and stores raw Postgres error text for unmapped errors
**Status:** VERIFIED
**Category:** Information disclosure
**Location:** `supabase/schemas/private/functions/sync_push.sql:66-79`
**Problem:** For any SQLSTATE other than P0001, `detail = coalesce(v_hint, v_msg)` — the raw message (constraint/relation/column names, cast errors) — is returned to the client and stored in `sync_ops.error_message`.
**Evidence:** `else 'server_error' end; … 'detail', coalesce(v_hint, v_msg)`.
**Impact:** Schema internals leak to any member; minor.
**Recommended Fix:** Return `v_hint` only (or nothing) when `v_code in ('server_error','invalid_payload','duplicate','missing_reference','invalid')`; log the full message server-side.
**Estimated Effort:** Small · **Production Blocker:** No
**Suggested Verification:** pgTAP: push an op with a non-uuid id; assert `detail` does not contain `invalid input syntax`.

## [P3][SEC-008] Realtime: any member (no perms needed) can broadcast on the arena channel; DELETE change events are not RLS-filtered
**Status:** LIKELY
**Category:** Realtime authorization
**Location:** `supabase/schemas/realtime/policies.sql:20-24`; `_cluster/publications.sql`
**Problem:** `arena_members_send` admits every active member to send any broadcast payload on `arena:<id>`; clients treat `sync` events as pull nudges (payload not applied — verified in `realtime_sync.dart`/`realtime-sync.ts`). Separately, Supabase Realtime does not apply RLS to DELETE Postgres Changes; any authenticated user (any self-registered owner) can subscribe to DELETE on published tables (`games`, `rates`, `discounts`, `game_resources`, …) and receive primary keys of other tenants' deleted rows.
**Impact:** Nudge flooding (battery/pull load) by a member; cross-tenant leak limited to UUIDs and delete timing.
**Recommended Fix:** Restrict send to members holding any floor perm or rate-limit client-side; accept the DELETE-PK limitation or remove tables that are deleted from from the publication (deletes already travel as tombstones via `sync_pull`).
**Estimated Effort:** Small · **Production Blocker:** No
**Suggested Verification:** Local: subscribe from arena B to `postgres_changes {event:'DELETE', table:'rates'}`; delete a rate in arena A; observe payload.

## [P3][SEC-009] Operator audit script is stale and reports expected FAILs
**Status:** VERIFIED
**Category:** Security process
**Location:** `supabase/audit/security_audit.sql:43`; `docs/DEPLOY_SUPABASE.md:48` and §5.1; `supabase/README.md` (audit row)
**Problem:** The allow-list predates the current 25-function client API (still names `add_staff_by_email`), so the go-live check instructs the operator to ignore a list of `FAIL` rows; DEPLOY §"Client API" lists 14 functions. Real regressions can hide among expected FAILs.
**Recommended Fix:** Sync the script's allow-list with test 13 (single source) and update the doc row.
**Estimated Effort:** Small · **Production Blocker:** No
**Suggested Verification:** Run the script locally; expect zero FAIL rows.

## [P3][SEC-010] Floor device keeps an unencrypted per-user copy of customers and payments after sign-out / revocation; Android auto-backup not disabled
**Status:** LIKELY
**Category:** Client data at rest
**Location:** `apps/mobile/lib/app/sync/staff_access.dart:46-47`; `apps/mobile/lib/app/sync/cloud_root.dart:583-600` (`_signOut` closes, never deletes); `apps/mobile/android/app/src/main/AndroidManifest.xml:17` (no `android:allowBackup`/`dataExtractionRules`)
**Problem:** The Drift file `arena_ops_cloud_<arena>_<user>.sqlite` (plain SQLite) is retained after sign-out and after `accessRevoked`. Combined with SEC-001 it holds every customer and payment. With `allowBackup` defaulting to true, Android Auto Backup may copy app files to the device's Google account. Keeping the file is deliberate (it can be the only copy of unpushed takings), so deletion must wait for an empty outbox.
**Impact:** A deactivated staff member keeps the arena's customer list on their own phone; backups leave the venue's control.
**Recommended Fix:** Set `android:allowBackup="false"` (or exclusion rules); after a revocation/sign-out with an empty outbox, delete that user's DB; consider SQLCipher if per-device PII is retained.
**Estimated Effort:** Small–Medium · **Production Blocker:** No
**Suggested Verification:** Code review of a revocation path + Drift migration test unaffected; manual adb check by the user.

## [P3][SEC-011] Admin session (refresh token) in `localStorage` with no CSP / security headers defined
**Status:** VERIFIED (absence)
**Category:** Web hardening
**Location:** `apps/admin/src/app/core/supabase/supabase.ts:104-107`; `apps/admin/src/index.html` (no CSP); no hosting header config in repo
**Problem:** supabase-js default storage keeps the session in `localStorage`; no Content-Security-Policy, `frame-ancestors`, or HSTS is configured anywhere. No XSS sink was found (no `innerHTML`, `bypassSecurityTrust*`, or data-bound `href`; `safeNext` blocks open redirects), so this is defence in depth.
**Recommended Fix:** When choosing hosting, add a strict CSP (`script-src 'self'`, `connect-src` = Supabase URL + wss), `frame-ancestors 'none'`, HSTS, `Referrer-Policy: no-referrer` (the accept-invite URL carries the token until `replaceState`).
**Estimated Effort:** Small · **Production Blocker:** No
**Suggested Verification:** Header check on the deployed origin (by the user).

## [P3][SEC-012] Local Auth config differs from the hosted checklist in security-relevant settings
**Status:** NEEDS VERIFICATION (hosted)
**Category:** Auth configuration
**Location:** `supabase/config.toml:238,244,215`; `docs/DEPLOY_SUPABASE.md:84,86`
**Problem:** Locally `secure_password_change = false` (doc requires ON for hosted); the 6-digit sign-up code lives 3600 s with `token_verifications = 30`/5 min per IP and no lockout; leaked-password protection was flagged off on hosted (doc §4a). None can be checked from the repo.
**Recommended Fix:** On hosted confirm: secure password change ON, leaked-password protection ON, OTP expiry ≤ 900 s, Realtime "Allow public access" OFF, redirect URLs limited to the dashboard origin (`/accept-invite`, `/reset-password`), anonymous sign-ins OFF.
**Estimated Effort:** Small · **Production Blocker:** No
**Suggested Verification:** Dashboard review by the owner against DEPLOY §3.

---

## Controls verified as sound

- **No anon surface.** Every one of 193 public + 28 private function files revokes `PUBLIC` and `anon`; all 53 table files revoke `anon`/`authenticated` then grant only `select`; views have no client grant and are `security_invoker = true`; the one sequence revokes both roles. Default privileges in both schemas revoke from `public`/`anon`/`authenticated`.
- **Client API = 25 invoker wrappers**, matching `tests/13_security_hardening_test.sql:89-97` exactly; no `public` SECURITY DEFINER is granted to `authenticated` (grep of grants vs `security invoker` files: identical sets). `private` is not in `config.toml [api] schemas`.
- **All definers pin `search_path`** (0 exceptions). Dynamic SQL limited to `_assert_same_arena` and `sync_pull`, both `format('%I')` over server constants with values bound via `USING`.
- **RLS on all 53 tables**; every policy is `for select to authenticated`; no write policies. `staff_invites`, `sync_ops`, `sync_tombstones`, `pricing_catalog_history` have RLS on, no policy, no grant. Payroll tables require `payroll`; attendance/leave = own rows (`app_my_staff_ids`) or reviewer perms; `audit_log` = owner level.
- **Helpers correct:** `app_arena_ids`, `app_arena_ids_with`, `app_has_perm`, `app_is_owner`, `app_my_staff_ids`, `can_use_arena_topic` all filter `user_id = auth.uid() and active`; policies use the `(select …)` initplan form.
- **Cross-tenant writes blocked twice:** every `op_*` resolves ids with `arena_id = p_arena` (scripted scan of all update/delete/lock statements; the unscoped ones reuse ids already locked under the arena), upserts use `on conflict … where <t>.arena_id = p_arena` plus an explicit "id exists in another arena → not_found" check; and 30 tables carry `_assert_same_arena` triggers on every cross-row reference (e.g. `controller_allocations.sql:144-152`).
- **Write path:** `sync_push` gates membership; each of 71 ops calls `_need`/`app_has_perm`/`app_is_owner` first or is self-scoped (`op_attendance_punch`, `op_leave_request`, `op_leave_cancel` select the caller's own profile). Refunds need `discount`, corrections `money`, finalise `payroll_finalise`.
- **Privilege escalation:** `op_staff_update` blocks self-changes, owner edits by non-owners, money/reports/payroll grants by non-owner-level; `_assert_settings_holder` prevents lock-out; `create_my_arena` requires a confirmed e-mail, advisory-locks, one owned arena; `bootstrap_owner` / `_create_arena_with_owner` not client-executable.
- **Invitations:** token = 32 random bytes, only SHA-256 stored, 7-day expiry, single use, `for update` lock, caller's confirmed auth e-mail must equal the invite, token checked before anything else is revealed; `arena_invites` never returns hashes; `revoke_invite` scoped by arena.
- **Owner RPCs** (`arena_*`) check `app_is_owner(p_arena)` first and filter by `p_arena` (`_sales`, `_plays` verified); `attendance_days`/`leave_balances` allow own `p_staff` only when it belongs to the caller in that arena.
- **Realtime:** private channels in both apps (`private: true`), topic regex-validated before the uuid cast, membership re-evaluated on JWT refresh; payloads never applied as data.
- **Secrets:** `.gitignore` excludes `dart_define*.json` except two local files; committed keys are the local publishable key and the hosted **anon** JWT (decoded `role: anon`); history scan found no secret/service-role key or DB URL with password. Storage: no buckets or `storage.*` policies in schemas or migrations, no client storage calls.
- **Clients:** mobile session in `flutter_secure_storage` keyed per backend, legacy key purged; per-user, per-arena DB path; sign-out drops alerts and closes the DB; Sentry `sendDefaultPii = false`. Admin: `safeNext` blocks open redirects, `detectSessionInUrl: false`, invitee uses an isolated non-persisted client and strips tokens from the URL, sign-out clears in-memory scope and forgets stored session on failure, password-reset redirect built from own origin.

## Not reviewed / needs verification

- Hosted project state (functions, leftover SQL objects, Auth/Realtime settings, migration history) — SEC-002, SEC-012.
- GoTrue behaviours assumed in SEC-005 (session revocation on password change) and Realtime DELETE semantics in SEC-008 — confirm on the local stack.
- All 71 `op_*` bodies were scanned mechanically (auth-before-write, arena scoping, upserts) and ~25 read in full; business-rule correctness of money/pricing/salary ops is out of this area.
- pg_graphql exposure (enabled by default on hosted): assumed to reflect only `public` objects the role can access; worth one `graphql` introspection as `authenticated` on hosted.
- Definers use `search_path = 'public'` without trailing `pg_temp`; not exploitable through PostgREST (clients cannot create temp objects) but `set search_path = public, pg_temp` would be the textbook form.
- Mobile release gating (`AppConfig.problemFor`, Gradle `AO_BACKEND` checks) and admin template-level XSS were checked by grep only; no runtime or dependency (npm/pub) vulnerability scan was run.
