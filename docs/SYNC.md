# Multi-device sync (Phase 2)

How Owner and Staff devices share one arena through Supabase while each keeps
working on its own SQLite database. The audit that preceded this work is in
[SYNC_AUDIT.md](SYNC_AUDIT.md).

## Modes

| Mode | When | Database file | Auth |
|---|---|---|---|
| Local-only (default) | no Supabase dart-defines | `arena_ops.sqlite` | PIN picker, as before |
| Cloud | `AO_BACKEND=supabase` + URL + anon key | `arena_ops_cloud_<arena>_<user>.sqlite` | the person's own Supabase account |

Cloud mode never opens or migrates the local-only file. One file per
(arena, person) means a person's unsent work can only ever be pushed under
their own sign-in.

## Write path

```
UI → *Actions (permission guard) → Local*Repository
        └─ one Drift transaction: local rows + one sync_outbox op
SyncEngine ── sync_push(arena, ops, device) ──► sync_ops ledger ─► op_* function
```

* Ops carry every id the device generated (session, segment, pad allocations,
  borrow moves, charges, payment), so server rows and device rows share identity.
* `sync_push` applies each op **once** (`sync_ops` keyed by op id, savepoint per
  op). A retried op, including one whose response was lost, replays its first
  answer. A payment cannot be recorded twice: the ledger replays the op, and
  the payment's primary key refuses a copy sent under a new op id.
* Each `op_*` function checks the permission the app checks (start / bill /
  discount / settings / owner) and re-validates every floor rule the Drift
  repositories enforce. It writes the whole operation atomically: session +
  segment + borrowed pads + allocations, or end + charges + pad release.
* Stations, then pads, are locked in uuid order. Two devices can never hold the
  same pad, and a count-only start serialises against a borrow from the same
  station (`supabase/concurrency_tests/run_pads.sh`).
* Stale writes are refused (`stale`). That covers an end priced from segments or
  an end time another device has since changed, an extend from an old end, a
  switch of a segment that is no longer open, and customer/booking edits over
  a newer version.
* Clients cannot write tables directly any more; `sync_push` is the only path.

## Server-side pricing (0013)

Every bill a device pushes is priced again on the server. An op whose money
does not match is refused (`price_mismatch`), so the device keeps the session
open and Sync shows the reason. Migration
`0013_server_pricing.sql` ports `PricingService`, `SegmentBilling` and
`GroupBilling` to plpgsql (`_pr_quote`, `_pr_session_bill`, `_pr_group_bill`).

**Why re-price instead of a tolerance check.** The engine uses only integer
paise with fixed rounding rules, so the server can reach the device's exact
number. Any tolerance would be free money for anyone with API access, and it
would also hide a porting bug. The tolerance is therefore **0 paise**.

**What is checked**

| Op | Check |
|---|---|
| `session.start`, `group.create` | `pricing_snapshot` must equal the arena's price list (rates, activities, policy, opening/happy hours, holidays, closures). That is the live list, or one an owner replaced in the last 72 h, which covers a device that went offline holding the old list. Card name and ordering are ignored. A group's `billing_mode` must be the snapshot policy's. Otherwise the op is refused with `pricing_snapshot_mismatch`. Without this check, a forged ₹0 price list would get past re-pricing. |
| `session.end`, `group.end` | The server prices the segments/assignments it holds, using the stored snapshot and the end time. `billed_amount_paise` must equal the server total. The charge rows must match the server's rows as a multiset on activity, station, controllers, band, start, end, played/billed minutes, unit, unit price and amount; ids and order are ignored. The end may not come before the start of the open segment or assignment. |
| `session.extend`, `group.extend` | `added_amount_paise` must equal what the device's planner computes. For a single session that is the money-rounded quote over the open segment's config, from the session start to the new end, minus the same quote to the old end. For a group it is the unrounded group subtotal at the new end minus the subtotal at the old end. |
| waived ends | Priced and checked exactly like any other end. Waiving changes only `payment_status` and still needs `discount`. |

Verification runs after the 0011 op body. Permission, stale and floor
refusals therefore keep their own codes. A price refusal rolls the whole op
back through the op's savepoint.

**Edge cases the port reproduces** (the Dart engine is the reference):

* Happy hour is split at the IST window boundaries of every day the interval
  touches. Holidays and closed days have no happy hour. Adjacent pieces of the
  same band are merged. A missing happy rate falls back to standard, and an
  activity that is not happy-eligible is never split.
* Grace: a session or segment of `≤ grace` minutes is free. Minimum charge
  extends the *billed* interval, so a charge row may end after the session.
  Played minutes still count only actual time.
* Per-minute bills prorate by the second. Block bills round the whole minutes
  up first, then up or to the nearest block. VR is billed in units rounded up
  or to the nearest unit, or prorated.
* Rounding scope `session` rounds each priced interval once, using the exact
  numerator over a common denominator. Rounding scope `segment`, or mixed
  denominators, sums the per-piece paise. Cash rounding (to nearest or up)
  applies once to the session or group total.
* Policy applies **per segment**, which is option A in
  [billing-segment-policy.md](billing-segment-policy.md). If the owner picks
  option B, the Dart engine and `_pr_*` must change together.
* A segment with no rate in the snapshot contributes nothing on both sides
  (the End screen warns staff).
* Groups: a per-system sweep splits at every controller-count change. In
  pooled mode the purchased count is priced once over the group window, and
  stretches without controllers are still billed per system.
* `early_exit` / `late_arrival = planned` are stored but not used by the app's
  billing. Both sides bill actual time.

**What is still trusted — session times.** Start, switch, extend and end times
come from the device; that is what lets a device work offline. The server
checks that the money matches the bill *for the times it was given*, and that
times are in order, but it cannot tell whether those times are true. So
server-side amount validation is **not** protection against forged or wrong
timestamps: a member with `bill` and direct API access could, for example,
send an end time earlier than the real one and the correctly-priced, smaller
bill for it. The evidence for an audit is the server's own receipt time on
every op (`sync_ops.created_at`, `sessions.created_at`) and who sent it
(`created_by`, `sync_ops.user_id`). In pooled group mode the purchased
controller count is also staff's declaration.

### Changing pricing (rule)

The server's `_pr_*` functions are a hand port of the Dart engine. **Any change
to how the app prices** — `lib/domain/pricing/`, `lib/domain/services/
segment_billing.dart`, `group_billing.dart`, `session_planner.dart` (extension
cost), `lib/core/money/`, the IST/business calendar in `lib/core/time/`, or the
`BillingPolicy` knobs — **must ship together with**:

1. a NEW migration that changes the matching `_pr_*` function (never edit an
   applied migration);
2. a green `bash tool/pricing_parity.sh` run (parity at 0 mismatches and both
   self-tests caught), with the new rule added to the boundary corpus in
   `tool/pricing_parity/generate.dart` if random sampling would rarely hit it.

Otherwise devices start receiving `price_mismatch` for correct bills (the
session stays open on the device and shows under Sync → Needs attention). The
same applies in reverse to any change in `_pr_*`.

`tool/pricing_parity.sh` prices a fixed boundary corpus (every billing unit ×
rounding × cash-rounding step and direction at block edges; grace and minimum
charge edges; happy-hour start/end ±1 s; holidays; IST midnight; VR unit
rounding; lounge; multi-segment and group bills, waived and not; extensions)
plus seeded random cases with the app's code, then re-prices them on the local
database at the function level and through the real `sync_push` end/extend ops
(exact money applied, one paisa off refused). It runs in a rolled-back
transaction and finishes by proving it can fail (a one-paisa error on either
side must be reported).

## Read path

* Every synced row carries `sync_xid` (the id of the transaction that last wrote
  it). `sync_pull` returns rows with `cursor <= sync_xid < pg_snapshot_xmin`, all
  from one snapshot, so a row from a still-open transaction is never skipped.
  Deletes arrive as tombstones.
* The engine pulls after every push, every 10 s while the app is in front, and
  on resume.

## Conflicts and rejections

An offline device cannot know what another device did meanwhile, so conflicting
offline work is **refused** on reconnect, never merged. When that happens:

1. The op stays in the outbox as `rejected`, with the server's reason and its
   full payload (including any money taken).
2. The device replaces its copy of the affected entity with the server's.
   Entities are a session, group, pad, customer or booking; a refused owner edit
   replaces the whole catalog. Rows the refused op had written disappear from
   the floor.
3. The Sync screen (tap the status strip) lists it under *Needs attention* until
   someone marks it *Seen*.

Pull and rollback run only while the outbox has no pending ops. This is
re-checked inside the Drift transaction, so server rows never overwrite an
unsent local change.

## Status strip

Local mode · Synced · *N* waiting · Syncing · Offline (*N* saved here, not sent
yet) · Sign in again / Access off, plus "*N* need attention" whenever refused
ops are unacknowledged.

## Auth and roles

* Staff create their own account on their own device. An owner adds that
  e-mail in Settings → Staff (`add_staff_by_email`). No service-role key exists
  anywhere in the app or the repo.
* `create_arena` makes a new arena with the starter catalog; the caller becomes
  its owner. `claim_arena` is no longer client-callable.
* Permissions come from `staff_profiles` and follow an owner's edits live. Turning
  a member off stops their device syncing and returns it to the sign-in gate.
  Their unsent ops stay in their database file.
* The device PIN is device-local and never synced. Cloud mode has no PIN step.

## Running it locally

```bash
supabase start              # project arena_ops, ports 5443x (Zitemonk keeps 5432x)
bash tool/verify_all.sh     # everything, in order, each step reported separately
bash tool/dev_run.sh -d "iPhone 17"   # the app in cloud mode against the local stack
```

`tool/verify_all.sh` runs, in this order: `flutter analyze`, `flutter test`,
`supabase test db`, the two race scripts, the two-device suite
(`tool/sync_it.sh`), the pricing parity check (`tool/pricing_parity.sh`), then
`supabase test db` again to prove order does not matter. Each piece can also be
run on its own, in any order.

**No reset is needed between suites, or before them.** Each one isolates its
own data:

| Suite | Isolation | Leaves behind |
|---|---|---|
| pgTAP (`supabase/tests`) | each file creates its own arena (the seed catalog, fixed id) inside its transaction; every lookup is pinned to it | nothing (rolled back) |
| `concurrency_tests/run.sh`, `run_pads.sh` | a dedicated arena + owner per script (`fixture.sh`), created on start | nothing (deleted on exit, even on failure) |
| `tool/sync_it.sh` | fresh `it-*@arena.test` accounts and an `IT …` arena per run | nothing (deleted on exit, even on failure) |
| `tool/pricing_parity.sh` | a throwaway arena inside one transaction | nothing (rolled back) |

`verify_all.sh` also plants an *isolation canary* for the whole run: a second
arena with the same station and controller names. A test that falls back to
"the only arena" or "the station called HEX" therefore fails instead of
passing by luck. At the end it checks that the database holds exactly what it
held before.

`supabase db reset --local` is still the way to apply edited migrations to the
dev stack. Use `--local` explicitly; never `--linked`.

`tool/dev_run.sh`, `tool/sync_it.sh` and `tool/verify_all.sh` read only the
local API URL and anon key from `supabase status`. They never print them, and
they refuse anything that is not a localhost URL. A release build refuses a
non-https or loopback backend.

## Not done / known limits

Blocking production:

1. **No hosted project.** Everything here was verified on the local stack only.
   That proves the logic, not devices on different networks. To go live, the
   owner creates a production project, applies migrations 0001–0013, keeps
   e-mail confirmation on (or turns off open sign-up and invites), sets a real
   minimum password length and SMTP, and builds with a `dart_define.prod.json`
   kept outside git.
2. **Real-device, cross-network test** (two phones on different networks, one
   going offline mid-shift) has not been done.

Worth doing next:

* Server pricing (0013) is a hand port of the Dart engine. Any change to
  `lib/domain/pricing` or `SegmentBilling` / `GroupBilling` must change `_pr_*`
  in a new migration, or every affected bill will be refused. When pricing
  changes, re-run the Dart-vs-SQL differential check. It priced 3,600 random
  bills both ways with 0 mismatches, and it caught a one-paise change to the
  rounding rule. A permanent CI version of it would lock this in.
* Bill times come from the device (see *What is still trusted* above).

* Booking overlap is checked server-side only for a *specific* station, and not
  against live sessions (the device checks both).
* A refused owner edit re-downloads the whole feed to rebuild the catalog. That
  is fine now, heavy for a large history.
* Other devices learn of changes by 10 s polling while the app is in front.
  Supabase Realtime could cut that latency and data use.
* Cloud mode has no PIN quick-unlock (the OS lock protects the device), and the
  staff editor still shows the device-only PIN field there.
* There is no import of local-only history into a cloud arena (only test data
  exists today).
* A refused op must be redone by hand. The Sync screen explains why, but offers
  no one-tap "redo".
* The legacy single-purpose RPCs (`start_session`, `allocate_controllers`, …)
  remain as internal, non-client functions; they could be dropped later.
* In the local Supabase image, a superuser session that `SET ROLE`s to
  `authenticated` and calls a function it may not execute crashes the backend
  (supautils hint hook). The same call through PostgREST returns a clean 403. pgTAP
  therefore asserts grants with `has_function_privilege`.
