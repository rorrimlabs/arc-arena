# Multi-device sync (Phase 2)

How Owner and Staff devices share one arena through Supabase while each keeps
working on its own SQLite database.

## Modes

| Mode | When | Database file | Auth |
|---|---|---|---|
| Local-only (default) | no Supabase dart-defines | `arena_ops.sqlite` | PIN picker, as before |
| Cloud | `AO_BACKEND=supabase` + URL + anon key | `arena_ops_cloud_<arena>_<user>.sqlite` | the person's own Supabase account |

Cloud mode never opens or migrates the local-only file. One file per
(arena, person) means a person's unsent work can only ever be pushed under
their own sign-in. A release build runs cloud mode only; local mode (demo
catalog, demo PINs) is for debug builds ([RELEASE.md](RELEASE.md)).

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
| `session.start`, `group.create` | `pricing_snapshot` must equal the arena's price list (rates, activities, policy, opening hours, holidays, closures, active pricing rules). That is the live list, or one an owner replaced in the last 72 h, which covers a device that went offline holding the old list. Card name and ordering are ignored. A group's `billing_mode` must be the snapshot policy's. Otherwise the op is refused with `pricing_snapshot_mismatch`. Without this check, a forged ₹0 price list would get past re-pricing. |
| `session.end`, `group.end` | The server prices the segments/assignments it holds, using the stored snapshot and the end time. `billed_amount_paise` must equal the server total. The charge rows must match the server's rows as a multiset on activity, station, controllers, band, start, end, played/billed minutes, unit, unit price and amount; ids and order are ignored. The end may not come before the start of the open segment or assignment. |
| `session.extend`, `group.extend` | `added_amount_paise` must equal what the device's planner computes. For a single session that is the money-rounded quote over the open segment's config, from the session start to the new end, minus the same quote to the old end. For a group it is the unrounded group subtotal at the new end minus the subtotal at the old end. |
| waived ends | Priced and checked exactly like any other end. Waiving changes only `payment_status` and still needs `discount`. |

Verification runs after the 0011 op body. Permission, stale and floor
refusals therefore keep their own codes. A price refusal rolls the whole op
back through the op's savepoint.

**Edge cases the port reproduces** (the Dart engine is the reference):

* There is one price band (standard): every interval is priced as one line.
  Happy hours and other time-of-day prices are pricing rules (below), judged
  once at the session's (group's) start; nothing is split at a window edge.
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
bill for it. What bounds it (`_client_time`): every session and group time
(start, switch, add, end) is refused when later than the server's time plus
2 minutes (`time_in_future`) or older than the arena's offline window
(`time_too_old`; settings key `offline_rules`, `max_offline_hours` 1–720,
default 24). Inside the window the server keeps its own receipt time
(`sessions.created_at` / `ended_recorded_at`, the same on `group_sessions`), and
the dashboard flags a start recorded over 5 minutes late and an end recorded
over 15 minutes late. Who sent it stays on `created_by` / `sync_ops.user_id`.
In pooled group mode the purchased controller count is also staff's
declaration.

### Changing pricing (rule)

The server's `_pr_*` functions are a hand port of the Dart engine. **Any change
to how the app prices** — `lib/domain/pricing/`, `lib/domain/services/
segment_billing.dart`, `group_billing.dart`, `session_planner.dart` (extension
cost), `lib/core/money/`, the IST/business calendar in `lib/core/time/`, or the
`BillingPolicy` knobs — **must ship together with**:

1. the matching change to the `_pr_*` function in `supabase/schemas/`, with
   the migration generated from it (migrations are never written or edited by
   hand — see CLAUDE.md, "Supabase — declarative schemas only");
2. a green `bash tool/pricing_parity.sh` run (parity at 0 mismatches and both
   self-tests caught), with the new rule added to the boundary corpus in
   `tool/pricing_parity/generate.dart` if random sampling would rarely hit it.

Otherwise devices start receiving `price_mismatch` for correct bills (the
session stays open on the device and shows under Sync → Needs attention). The
same applies in reverse to any change in `_pr_*`.

### Time rules and discounts

Time rules are priced by the server and the floor app alike (2026-10-15:
happy hours became an ordinary rule, `lib/domain/pricing/rule_engine.dart` ↔
`_pr_rule` / `_pr_rule_price`). Discounts are built on the server and the
dashboard; the floor app does not send them yet.

* **Time rules.** `_pricing_snapshot` / `_pricing_canon` carry `rules` only
  while the arena has an active rule, so an arena without rules is priced and
  validated exactly as before. A rule is judged at the session's (group's)
  start in IST — weekday, whole minute of day (seconds dropped) in
  `[start_min, end_min)`, holiday
  mode, dates, type — and the first by priority changes every unit price of
  the session for its whole length (ties: name, then id, in code-point order,
  `collate "C"`; `_pr_rule`, `_pr_rule_price`; percent is
  round-half-up, rupees per hour are pro rata to the rate's unit, half toward
  +∞, never below 0). **Once an arena has an active rule, a floor app built
  before rule support is refused at `session.start` / `group.create`
  (`pricing_snapshot_mismatch`)**: release the server and the floor app
  together. The floor app pulls `pricing_rules` into Drift (schema v16, which
  also rewinds the pull cursor once so rules sent before the upgrade arrive).
* **Discounts.** `session.end` / `group.end` take an optional `discount`
  (preset, coupon by code, or manual) validated and recorded by
  `_discount_apply`; billed = cash-rounded (subtotal − discount). An end
  without a discount behaves as before, so older floor apps keep working.
* The new tables (`accessory_kinds`, `pricing_rules`, `discounts`,
  `bill_discounts`) and `controllers.kind_id` are in the change feed; floor
  apps that do not know them ignore them.
* `tool/pricing_parity.sh` covers rules (both kinds and signs, window edges,
  holiday modes, dates, tie-breaks); discounts are pinned by pgTAP 25 only.

`tool/pricing_parity.sh` prices a fixed boundary corpus (every billing unit ×
rounding × cash-rounding step and direction at block edges; grace and minimum
charge edges; rule window edges ±1 min / −1 s, holiday modes and tie-breaks; holidays; IST midnight; VR unit
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
  Deletes arrive as tombstones. A row in a page is the server's *current* row,
  so it outranks a tombstone for the same key in that page (a delete the same
  or an earlier transaction undid — `game.replace_controls`, a holiday or
  station link removed and re-added). Before 2026-10-12 the tombstone was
  applied last and wiped the row on every other device. Until 2026-10-14 the
  device ignored `games` and `activities` tombstones, so a game deleted on the
  dashboard (`game.delete`) or a never-used station type (`activity.remove`)
  stayed on every device; now both are removed, a deleted game taking its
  station statuses and control guide with it even if their own tombstones land
  in a later page.
* **Games: archive vs delete.** An archived game (`games.active = false`) stays
  on the device for history but is offered nowhere (new session, change game,
  group, booking pickers read active games only). A game edit from the device
  sends `base_active` (the flag it held), so a queued edit never undoes an
  archive or restore made elsewhere: the server refuses it as `stale` and the
  device converges on the server's catalog. A station-status save sends only the
  stations that changed, keeping their notes.
* **Realtime nudges a pull; polling stays as the fallback.** Both apps join one
  PRIVATE channel per arena, topic `arena:<arena uuid>` (`private: true`; the
  user's JWT is set on the socket before joining). The `realtime.messages`
  policies (`supabase/schemas/realtime/policies.sql`: `arena_members_receive`
  for select, `arena_members_send` for insert, both `to authenticated`) admit
  only active members of that arena, so a deactivated member or another arena's
  login can neither listen nor send. Realtime caches that decision per
  connection until the JWT refreshes: a revocation takes effect within
  `jwt_expiry` (3600 s).
  * *Postgres Changes*: INSERT and UPDATE only, filtered by `arena_id` and
    RLS-filtered. DELETE is never subscribed (Supabase neither RLS-checks nor
    filters DELETE events); deletions travel as the broadcast nudge.
  * *Broadcast `sync`*, sent only AFTER the server committed ops: the floor
    app's `SyncEngine` calls `onPushed` with the applied op kinds; the
    dashboard's `pushOps` broadcasts only applied kinds (never on a transport
    error or refusal). Payload: `{arena_id, kind:'push', kinds:[…],
    source:'mobile'|'admin-web', at}`.
  * **No business data travels in Realtime.** Every event only triggers a pull
    (floor app, `lib/data/sync/realtime_sync.dart`, debounced) or a store
    refetch (dashboard) through the normal authorized queries.
  * Published tables (`supabase/schemas/_cluster/publications.sql`, 33):
    accessory_kinds, activities, bill_discounts, billing_policies, bookings,
    controller_allocations, controller_moves, controllers, customers,
    discounts, game_categories, game_controls, game_resources, games,
    group_assignments, group_charges, group_extensions, group_payments,
    group_sessions, holidays, payments, pricing_rules, rate_bands, rate_cards,
    rates, resource_activities, resources, session_charges,
    session_extensions, session_segments, sessions, settings, staff_profiles.
  * The dashboard reloads only what the open screen shows; anything else is
    marked out of date and read again when a screen next needs it
    (`apps/admin/src/app/core/sync/realtime-sync.ts`, 800 ms debounce).
* **Timing.** A device pushes ~0.3 s after each local change, then pulls; a
  nudge triggers a pass on every other device, so changes arrive in about a
  second. The floor app still passes every 10 s while it is in front (the
  fallback and catch-up), and at once on resume (passes stop while the app is
  in the background); a Realtime reconnect triggers a catch-up pull
  (cursor-based, nothing missed). A nudge never restarts a stopped engine. The
  dashboard does not poll: it refetches on each event and on reconnect/online.
  (Until 2026-10-12 the "push right after a change" never fired — the timer
  was born inside the Drift write transaction and died silently — so changes
  only left on the 10 s poll.)
* Floor state (sessions, segments, groups, pads, payments, bookings) reaches
  screens through Drift watch streams. Catalog reads (stations, games,
  activities, price list, names on cards) are one-shot providers; they re-read
  whenever a pass changed local data (`syncRevisionProvider`), so a station
  another device renamed, added or took out of service appears without a
  restart.

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

A refused check-in (`session.start` with a `booking_id`) also rolls the
booking back to the server's status, so it does not stay "checked in" on that
device only.

## Money and permission rules (0016)

`supabase/migrations/0016_integrity_and_authz.sql`, from the 2026-10-12 audit.
Each rule is enforced on the device too, so the device refuses first and the
server is the referee for devices working on stale numbers.

| Rule | Server | Device |
|---|---|---|
| Once a bill is final, payments may only fill it up to the bill (`overpayment`). A running session's advance payments are not capped. A waived bill is unchanged. | `op_payment` wrapper locks the bill, sums payments | `paymentBalanceProblem` (`lib/domain/services/payment_rules.dart`), checked inside the write transaction |
| A refund may never exceed what was collected (`refund_exceeds_paid`). | same | same |
| A void needs a reason (`void_reason_required`, 2026-10-14). A voided bill takes no payment (`voided`, checked before the balance) but may be refunded, so money taken before the void can go back. | `op_session_void`, `op_group_void`, `op_payment` | the floor app never voids; refunds only from the dashboard |
| A waive writes an `audit_log` entry (amount written off, reason). A waive needs a reason on the server too (`waive_reason_required`), as in the floor app. Below owner level a waive may write off at most `discount_options.manual_max_percent` of the bill (`waive_over_limit`; exact integer check `_waive_check`, mirrored by `waiveOverLimit` on the floor). | `op_session_end`, `op_group_end` | `SessionActions.end` / `GroupSessionActions.end`, end sheets |
| `payment.correct` (dashboard only, Money permission) moves all or part of a payment to another method as a refund + payment pair with a reason; never more than the payment. The device receives the two rows like any payment; they net to zero. | `op_payment_correct` | — |
| The End sheet collects only what is still due (an advance taken while the session ran is not collected again) and says when the payment did not go in. Take payment books only the balance on a final bill and tells staff the change to return. | — | `end_session_sheet.dart`, `take_payment_sheet.dart` |
| A `role='owner'` profile always holds every permission and stays active; `staff.update` rewrites it so and answers `adjusted` (the device refetches). An arena can therefore never be left without an owner; removing an owner is an operator action on the database. | `op_staff_update` wrapper | the device reverts to the server row |
| `add_staff_by_email` cannot overwrite an existing owner's profile (`owner_profile`), refuses unknown permission codes, and must leave someone holding Settings. (Since removed: people join only by invitation — *Auth and roles*.) | redefined | — |
| Loaning a pad or sending it home needs `start` or `settings` (was: any active member). Re-homing still needs `settings`. | `op_controller_move` wrapper | UI offers it only there |
| Every cross-table reference stays inside the row's arena (`missing_reference`). | `t_same_arena` triggers on 19 tables | ids come from the device's own arena |
| `resource.upsert` cannot touch another arena's station id (`not_found`). | wrapper | — |
| Every public function pins `search_path`. | `alter function … set search_path` | — |

Two devices that both see "₹300 remaining" and both take it: the first push
is applied, the second is refused as `overpayment`. That device rolls back to
the server's payments, and the refused payment (amount and method) stays under
Sync → Needs attention. It is money a person physically took, so someone must
hand it back or record it against another bill.

## Status strip

Local mode · Synced · *N* waiting · Syncing · Offline (*N* saved here, not sent
yet) · Sign in again / Access off, plus "*N* need attention" whenever refused
ops are unacknowledged. It is on Today, Floor, Money and Reports (the screens
that total money). The waiting count keeps counting while sync is stopped (an
expired sign-in, the app paused), so the sign-out warning sees unsent work.
In the "Sign in again" state the Sync screen has a **Sign in again** button;
unsent work stays in that person's database file and goes after they sign in.

## Auth and roles

* **The floor app is staff-only: it only signs in.** New arena owners register
  on the admin dashboard (`apps/admin`): e-mail + password (10+, letters and
  digits) → the link in the confirmation e-mail (opens `/register`) →
  Create your arena → `create_my_arena(arena name, owner name)`. The server
  refuses unconfirmed logins and a second arena per login (`arena_limit`). The
  arena starts **empty**: the owner adds station types (`activity.upsert`),
  prices (`rate.upsert`), stations, controllers and games on the dashboard, and
  devices pull them.
* **Operator route:** `select bootstrap_owner(email, arena name, owner name)`
  in the SQL editor still attaches an owner to a new arena (no limit; not
  callable by the app). The legacy `create_arena` / `claim_arena` stay dropped.
* **Staff and co-owners join only by accepting an invitation.** Admin
  dashboard → Users → *Invite user* (name, e-mail, role, permissions; no
  password). The dashboard calls `invite_member` **as the caller**: staff
  invites need `settings`, granting `money`/`reports` needs owner level,
  inviting an owner needs an owner. Only the SHA-256 of a random one-time token
  is stored; the invite expires in 7 days, and a newer invite to the same
  address replaces the old link. The dashboard then has Supabase Auth e-mail
  the link (`signInWithOtp` from a throwaway client, redirect to
  `/accept-invite`), so only the address's owner receives it: a confirmed login
  gets a sign-in (magic) link; a new or unconfirmed one gets the sign-up
  confirmation, whose template shows the link for invitations
  (`supabase/templates/`). If the e-mail fails, the invite is withdrawn. No
  Edge Function and no service-role key are involved.
* The link opens the dashboard's `/accept-invite?invite=<id>&token=<token>`.
  The page takes the session from the link; unless it was a magic link (a
  login its owner had already confirmed), the person must choose their own
  password — a password someone else set on an unconfirmed address does not
  survive — then it calls `accept_invite`: the token must match and be unused,
  unwithdrawn and unexpired; the caller's **confirmed** e-mail must be the
  invited address (`invite_wrong_account`); the inviter must still hold the
  authority; an existing owner is never demoted. It creates or reactivates the
  person's profile in that arena only. The person then signs in on the floor
  app with their e-mail and their own password. Owners see pending invites on
  the Users page and can withdraw them.
* **Both apps must use the same Supabase project.** A login, its invitation and
  its membership exist only in the project where the invitation was accepted. A
  staff member invited on one server gets "That e-mail and password don't match a
  login on this server" from a floor app on the other. Pair them:

  | Server | Dashboard (`apps/admin/`) | Floor app (`apps/mobile/`) |
  |---|---|---|
  | Local stack (all development) | `npm run dev` (`environment.ts`) | `dart_define.local.json` / `dart_define.local-android.json` (VS Code "arena_ops (local Supabase: …)") |
  | Hosted project (manual go-live) | a production build (`environment.production.ts`) | `dart_define.prod.json`; every release build |

  Neither app names its server on screen. On the local stack, invitation e-mails
  land in the mail catcher (Mailpit, http://127.0.0.1:54434). Inviting on the hosted project also needs the invitation migrations
  (DEPLOY_SUPABASE.md §4a), the two e-mail templates, the dashboard's
  `/accept-invite` and `/reset-password` addresses in Auth → Redirect URLs, and
  custom SMTP (the built-in sender only mails the Supabase organisation's team
  members).
* Removed: `add_member_by_email` / `add_staff_by_email` (they linked an
  existing login without its consent), the owner-set starting password, and
  the floor app's "Add by e-mail" (it now explains that invitations are sent
  from the dashboard). Permissions, rename and deactivate are `staff.update`
  ops through `sync_push`; a field the op leaves out keeps its value.
* No service-role key exists anywhere in the apps or deployed code.
  `tool/sync_it.sh` uses the
  LOCAL stack's key in a non-exported shell variable to create test logins
  (never printed, never given to a test process).
* Permissions come from `staff_profiles` and follow an owner's edits live. Turning
  a member off stops their device syncing and returns it to the sign-in gate.
  Their unsent ops stay in their database file.
* **Stored sign-in.** The floor app keeps the session in the Keychain/Keystore
  per backend (key `arena_ops.supabase.session@<host:port>`), so a local-stack
  session is never replayed against hosted dev or vice versa; the old shared
  key is deleted at start (one extra sign-in after updating).
* **Start-up.** A stored session is checked before the first call; no request
  is ever sent as anon. A failed start-up call is classified: *offline* (no
  network, 5xx, or the access-token refresh could not reach Auth) → the
  sign-in is kept and the last arena opens from disk; *sign-in needed* (Auth
  refused the refresh token, the API rejected the token, or the session is
  gone) → cleared locally, sign-in screen; *server refused* (reachable, signed
  in, refused) → error with retry, sign-in kept. Opening an arena: when
  `my_arenas` has just reported the membership active but the device's copy of
  the staff list says off (or lacks the person), the app syncs once and checks
  again before saying "turned off" (`confirmAccess`, `lib/app/sync/staff_access.dart`).
  Every message is in plain words (`signInFailureMessage`,
  `arenaListFailureMessage`, `firstDownloadFailureMessage`): never a raw
  exception, SQL error or token. A keystore that cannot be read at start means
  "sign in again", never a crash (`SecureSessionStorage`).
* **During a shift.** A refresh that fails for lack of network is "offline":
  the engine keeps retrying with backoff and the outbox is kept. Nothing is
  sent without a session. A 42501 counts as "access turned off" only when the
  call ran with a session. Realtime nudges never restart a stopped engine.
  Unsent work always stays in the person's database file.
* Floor app permission checks live in the action controllers: `BookingActions`
  (start), `CatalogActions` (settings; pad loan/return start or settings,
  permanent re-home settings), `CustomerActions` (start or members), plus the
  session and group actions. The floor "View games" sheet is read-only without
  settings.
* The device PIN is device-local and never synced. Cloud mode has no PIN step.

## Running it locally

```bash
supabase start              # project arena_ops, ports 5443x (Zitemonk keeps 5432x)
bash tool/verify_all.sh --with-it --with-psql   # everything, in order, each step reported separately
```

The floor app runs against the local stack with the committed
`apps/mobile/dart_define.local.json` (iOS Simulator / macOS, `127.0.0.1`) or
`dart_define.local-android.json` (Android emulator, `10.0.2.2`). They hold only
the localhost URL and the local stack's **publishable** key, the same pair as
`apps/admin/src/environments/environment.ts`. If `supabase status` ever shows a
different publishable key, update all three. A physical tablet can't reach the
Mac's `127.0.0.1`; test on a simulator/emulator, then go live manually.

```bash
cd apps/mobile && flutter run --dart-define-from-file=dart_define.local.json
```

`tool/verify_all.sh` runs, in this order: `flutter analyze`, `flutter test`,
the admin unit tests (`ng test`), an admin development build (to a temp dir;
the production config inlines Google Fonts, which needs the network),
`supabase test db --local`, `supabase db advisors --local` (must be empty).
`--with-it` adds the cross-app integration (`tool/sync_it.sh`); `--with-psql`
adds the pricing parity check (`tool/pricing_parity.sh`) and the two race
scripts — both use `docker exec psql` on the local container, inside
rolled-back transactions / their own fixture arena. Every step runs and is
reported PASS, FAIL or SKIP with the reason; the exit code is non-zero if any
step failed. The declarative drift check (`supabase db schema declarative sync
--no-apply` must say "No schema changes found") stays a manual step, because
it writes a migration file when there is drift. Each piece can also be run on
its own, in any order.

**Invitation e-mails** are Supabase Auth's own: locally they land in Mailpit
(http://127.0.0.1:54434). The templates in `supabase/templates/` load at
`supabase start`; after editing one, `supabase stop && supabase start` (data is
kept).

`tool/sync_it.sh` is the cross-app suite, on the LOCAL stack only (it refuses
anything else), one run at a time (a lock in `supabase/.temp`). It provisions
throw-away `it-*@arena.test` logins (Auth admin API with the local stack's
service key), an arena via `bootstrap_owner` + `_seed_arena_catalog`, and joins
the staff login by invite → accept. Then: a
Flutter device listens live while
dashboard phase 1 runs (the Angular data layer under `ng test
--runner-config=vitest.it.config.mts`, Node environment: builds a game and its
station availability, saves floor options, invites a new person by e-mail and
accepts from the Mailpit link); the dashboard listens live while the Flutter
`test/sync/` suite runs (two-device sync, cross-app, private-channel
authorization, arena isolation); dashboard phase 2 checks that the owner's
Sales shows the staff's bill with one payment and that another arena's owner
sees nothing. Step 6 checks the stack's function runtime is still up after the
run. It cleans up exactly the logins and arenas it created. The specs
(`apps/admin/src/integration/*.it.spec.ts`, `apps/mobile/test/sync/*`) skip
themselves outside `sync_it.sh`.

**No reset is needed between suites, or before them.** Each one isolates its
own data:

| Suite | Isolation | Leaves behind |
|---|---|---|
| pgTAP (`supabase/tests`) | each file creates its own arena (the `_seed_arena_catalog` test fixture, fixed id) inside its transaction; every lookup is pinned to it | nothing (rolled back) |
| `concurrency_tests/run.sh`, `run_pads.sh` | a dedicated arena + owner per script (`fixture.sh`), created on start | nothing (deleted on exit, even on failure) |
| `tool/sync_it.sh` | fresh `it-*@arena.test` logins and the arenas they own, per run | nothing (removes exactly what the run created, on exit) |
| `tool/pricing_parity.sh` | a throwaway arena inside one transaction | nothing (rolled back) |

`supabase db reset --local` is still the way to rebuild the dev stack from the
migrations. Use `--local` explicitly; never `--linked`.

`tool/sync_it.sh` reads the local stack's service-role key into a non-exported
variable. It never prints a key and refuses anything that is not a localhost
URL. A release build refuses local mode and any non-https or
development backend ([RELEASE.md](RELEASE.md)).

## Not done / known limits

Blocking production:

1. **Hosted dev project:** linked (ref `ouxv…`) with 0001–0015 applied,
   one arena, the owner (role owner, all permissions) and one staff login
   (start, bill, discount, members), checked from the database 2026-10-12;
   not re-verified since. **Not pushed — needs the owner's go-ahead:** 0016
   and the 18 generated migrations after it ([DEPLOY_SUPABASE.md](DEPLOY_SUPABASE.md)
   §4a), so invitations, Realtime, the `private` schema and the narrower
   money/customer reads exist only on the local stack. The hosted settings
   invitations need (custom SMTP, URL configuration, the two e-mail
   templates) are not done either. As of 2026-10-12 no session or op
   had reached it.
2. **Real-device, cross-network test** (two phones on different networks, one
   going offline mid-shift) has not been done. Every multi-device claim here
   is proven against the local stack (`tool/sync_it.sh`: real accounts, two
   device databases, the dashboard's data layer, real PostgREST and Realtime)
   — not on two phones.
3. **Session times are device-asserted, within bounds.** Future times and
   times older than the offline window are refused; late ends inside it are
   flagged on the bill, not refused (see *What is still trusted* above).

Known limits (by design or not yet built):

* **Another person's unsent work on a shared device is invisible.** Each
  (arena, person) has its own database file; if A signs out with changes
  waiting and B signs in on the same device, A's changes (payments included)
  go only when A signs in there again, and nothing tells B or the owner. The
  owner's decision is per-person devices, so this is a limit, not a bug —
  but a shared counter tablet must not be used that way. The same applies to
  a member whose access is turned off with work waiting.
* **One unreadable server row stops pulls** (retried with backoff, shown as
  "Sync error") until a build that can read it ships. No row in today's schema
  is known to fail; there is no quarantine.
* **A refused owner edit re-downloads the whole feed** to rebuild the catalog
  (cursor 0, then filtered). Fine with today's data; with a long history it can
  exceed the 8 s statement timeout and leave that device "offline".
* Owner editing screens (Staff, Pricing, Hours, Holidays, Billing rules) read
  once when opened; reopen them to see another device's edit.
* Success messages ("Paid in full", "Saved") mean saved on this device; the
  status strip says whether it has reached the server.
* **Every active member's device holds the arena's rows it may read** through
  `sync_pull` (SECURITY DEFINER): sessions, the catalog and staff permissions
  for everyone; payments, charges and customers by permission — never e-mails.
  Direct reads are narrower (RLS: payment and charge rows need
  `bill`, `money` or `reports`; customers `start`, `members`, `money` or
  `reports`; `audit_log` owner level; `staff_invites` none), and the device
  feed narrows the same way (`_sync_hidden`; coupons also need `discount` or
  `settings`), so an attendance-only login receives no customers or money.
  Rows a device already holds when a permission is taken away stay in its
  file until it is reinstalled or the person signs out.

Worth doing next:

* Server pricing (0013) is a hand port of the Dart engine; the rule and the
  check that enforces it are under *Changing pricing* above
  (`tool/pricing_parity.sh`, also step 8 of `tool/verify_all.sh --with-psql`).
  It is not in a CI pipeline yet — there is no CI in this repo.

* Booking overlap is checked server-side only for a *specific* station, and not
  against live sessions (the device checks both).
* Cloud mode has no PIN quick-unlock (the OS lock protects the device), and the
  staff editor still shows the device-only PIN field there.
* There is no import of local-only history into a cloud arena (only test data
  exists today).
* A refused op must be redone by hand. The Sync screen explains why, but offers
  no one-tap "redo".
* In the local Supabase image, a superuser session that `SET ROLE`s to
  `authenticated` and calls a function it may not execute crashes the backend
  (supautils hint hook). The same call through PostgREST returns a clean 403. pgTAP
  therefore asserts grants with `has_function_privilege`.
