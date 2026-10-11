# Phase 2 sync — audit (2026-10-11)

Scope: Drift v13 client, Supabase migrations 0001–0009, pgTAP 00–06, the
two-connection concurrency test, local PIN auth, and the session / group /
booking / payment / controller lifecycles. Read-only audit; nothing was changed
to produce it.

## Baseline (before any Phase 2 change)

| Check | Result |
|---|---|
| `git status` | `develop` @ `6e4d612`; one unrelated uncommitted edit (`lib/core/notifications/notification_service.dart`, unused import removed) — left untouched |
| `flutter analyze` | clean |
| `flutter test` | 405 passed, 0 failed |
| `supabase db reset --local` (project `arena_ops`, ports 5443x, not linked to any remote) | applies 0001–0009 + seed cleanly |
| `supabase test db` | 7 files, 217 assertions, PASS |
| `supabase/concurrency_tests/run.sh` | PASS (one start wins, other gets `resource_busy`) |

Note: the commit ids recorded in earlier session notes (e281d42, 769c608,
f973179, 3228467 …) no longer exist — history was re-rooted into
`afe4c98` / `6e4d612`. The content is present; only the ids changed.

## 1. Schema mismatches (Drift v13 ↔ Postgres 0009)

| Area | Drift | Postgres | Consequence |
|---|---|---|---|
| **Row identity** | Seed ids are human strings (`hex`, `ps5`, `g_eafc`, `ctl_hex_1`, `u1`, rate `ps5_standard_1`) | `uuid` everywhere, server-generated in `seed.sql` | A device's catalog cannot be matched to the server's. Every session row references `hex`, which does not exist server-side. **Blocking.** |
| Rates | one flat table keyed by `(activity_code, band, controller_count)` | `rate_cards` → `rate_bands` → `rates(activity_id, band_id)` | needs a mapping, not a copy |
| Resource ↔ activity | `(resource_id, activity_code)` PK | `(resource_id, activity_id)` + uuid id | mapping |
| Billing policy | one JSON blob, id `default` | typed columns per arena | mapping |
| Holidays | PK `day` | uuid id + `unique(arena, day)` | mapping |
| Bookings | `activity_code` | `activity_id` | mapping |
| Payments | `is_refund` bool | `kind` text | mapping |
| Users | `users` with PIN hash, lockout | `staff_profiles` keyed to `auth.users`; no PIN | intentional — see §4 |
| Settings | `business_hours` **and device-local notification settings** share one table | `settings(arena_id, key)` | only allow-listed shared keys may sync |
| Change tracking | — | no `updated_at` on `session_segments`, `group_assignments`, `controller_allocations` (rows are *updated* when they close) | an incremental pull by timestamp would miss every segment/allocation close. **Blocking for sync.** |
| Deletes | rates, holidays, game controls, resource links are hard-deleted locally | no tombstones | a pull can never learn about a delete |
| `seed.sql` games | — | `player_mode` / `max_local_players` left at defaults (`single`, 1) while Drift seeds e.g. EA FC = 4 | server-side player-limit checks would refuse legitimate multi-pad sessions |
| Local idempotency | no `request_id` on Drift sessions/payments; `requestId` is threaded through commands but never persisted | `request_id` unique per arena | client has nothing stable to retry with |

## 2. Security gaps (server)

Severity is for a multi-device deployment where any signed-in member can call
PostgREST directly with their own JWT.

1. **High — RPCs check membership only, not the permission the app enforces.**
   `start_session`, `reconfigure_session`, `extend_session`, group create/add/
   switch/extend require only membership; the app requires `start`.
   `end_session`, `record_payment` (+ group) require only membership; the app
   requires `bill`. Only refund/waive (`discount`) and void (owner) are mirrored.
2. **High — `release_controllers` lets any member end any open allocation**, for
   pads held by someone else's running session, silently breaking the
   one-pad-one-session guarantee. `allocate_controllers` / `borrow_controllers`
   accept arbitrary session/segment ids (not checked to exist or be active), so a
   member can lock or move pads with no session behind them.
3. **High — server end/void never close controller allocations.** `end_session`,
   `void_session`, `end_group`, `void_group`, `reconfigure_session`,
   `switch_assignment`, `end_assignment` close segments/assignments but leave
   their pads "in use" forever.
4. **Medium — payments accepted on voided sessions/groups** (`record_payment`,
   `record_group_payment` only check existence).
5. **Medium — customers/bookings are plain member-writable tables** with no
   version check: any member can overwrite any booking (incl. status) and two
   devices silently last-write-win. Booking check-in is not protected against two
   devices checking in the same booking.
6. **Medium — `claim_arena` promotes the first authenticated caller of an
   owner-less arena to owner.** With open sign-up in production, a stranger can
   claim a newly created arena before its owner does.
7. **Medium — no last-owner guard server-side**: an owner can deactivate or
   demote every owner (the client guards this; the server does not).
8. **Accepted by design (documented, not fixed here) — prices are client-computed.**
   `end_session` / `extend_session` trust the client's charges and amounts (the
   Dart pricing engine is the single source of truth). A member with direct API
   access and `bill` could under-bill. Mitigation today: append-only history +
   `created_by` attribution + owner reports. Server-side re-pricing is future work.
9. Local stack config is dev-grade (`enable_signup = true`,
   `minimum_password_length = 6`). Fine locally; must be tightened for production.

No service-role key, database password or JWT is committed (scanned).

## 3. Lifecycle operations not implemented server-side

| Operation (client has it, atomic in Drift) | Server today |
|---|---|
| Start session **with specific pads + borrow** | `start_session` has no pad params; pads would need a 2nd/3rd RPC — not atomic |
| Switch / change game / change controllers with pads | `reconfigure_session` ignores pads and leaves old ones allocated |
| Group create / add / switch with pads | no pad params; co-location rules differ from Drift (server skips the port ceiling and player limit for a first occupant and ignores pads borrowed in the same op) |
| End / void session or group → release pads | not done (gap 3) |
| End assignment → release pads | not done |
| Booking check-in (start + mark booking checked-in) | no server op; **also non-atomic locally** (`BookingActions.checkIn` starts the session, then sets booking status in a second write) |
| Customer create/update, booking create/update/cancel | direct table writes, no idempotency or version check |
| Owner catalog edits (rates, policy, hours, holidays, games, controls, stations, pads, staff) | direct writes against a differently-shaped schema; no mapping |
| Staff enrolment | none (`claim_arena` only) |
| Change feed / pull | none |
| Per-operation idempotency for ops without a `request_id` (`end_assignment`, void, moves) | none |

## 4. Authentication — current state and decision

* Local login = pick a user, type a 4-digit PIN (salted PBKDF2, 5-try lockout),
  held in memory only. A PIN hash is **device data**: it proves nothing to a
  server and must never be treated as a cloud credential.
* The owner already decided (2026-10-11): **one Supabase account per person**,
  per-person devices, authority enforced on the backend. The PIN becomes an
  optional device quick-unlock for the account already signed in on that device.

Plan (non-breaking): local-only mode keeps today's PIN flow unchanged. Cloud mode
is a separate, opt-in mode: sign in with the person's own Supabase account; roles
come from `staff_profiles`; enrolment is *staff signs up → owner adds them by
email* (no service-role key needed anywhere); `claim_arena` is restricted to the
database owner / a one-time setup path.

## 5. Critical controller scenario

Covered **on one device** (Drift) by `test/app/cross_station_borrow_test.dart`
and `controller_lifecycle_test.dart`. **Not enforceable server-side today**
(gaps 2, 3 and §3): nothing ties pads to a server session atomically, nothing
releases them, and a count-only start is not checked against free pads.

## 6. Decisions taken for the implementation

1. **Cloud mode uses its own database file per arena** (`arena_ops_cloud_<arena>.sqlite`)
   whose catalog is pulled from the server (server uuids). The existing local-only
   database is never migrated, rewritten or reset. Importing local-only history
   into the cloud is out of scope (only test data exists).
2. **Every write that must sync is recorded in a durable Drift outbox in the
   same transaction as the local write**, as an explicit operation carrying every
   row id the device generated — so server rows share identity with local rows.
3. **Server applies each op once** (`sync_ops` ledger keyed by op id) through one
   transactional function per op kind that re-validates everything (resource,
   game, mode lock, pads, permissions) and writes all rows atomically.
4. **Pull uses a commit-safe change feed**: every synced table carries
   `sync_xid xid8`; the pull window is `[cursor, pg_snapshot_xmin)`, so a row from
   a still-open transaction is never skipped. Deletes leave tombstones.
5. **Rejected ops are never dropped**: the op stays in the outbox with the
   server's reason; the device then re-fetches the affected entity from the server
   and rolls its local copy back to server truth. Pull is applied only when the
   outbox has no pending ops, inside the same Drift transaction that checks it.
6. Conflict-sensitive ops (start, check-in, pads, payments, end) carry the
   server version the device last saw where staleness would change the outcome
   (end/void), and the server refuses on mismatch.
