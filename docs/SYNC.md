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
supabase start            # project arena_ops, ports 5443x (Zitemonk keeps 5432x)
supabase db reset --local # dev stack only
supabase test db          # pgTAP
bash supabase/concurrency_tests/run.sh
bash supabase/concurrency_tests/run_pads.sh
bash tool/sync_it.sh      # two-device integration tests (skipped by plain flutter test)
bash tool/dev_run.sh -d "iPhone 17"   # the app in cloud mode against the local stack
```

`tool/dev_run.sh` and `tool/sync_it.sh` read only the local API URL and anon key
from `supabase status`. They never print them, and they refuse anything that is
not a localhost URL. A release build refuses a non-https or loopback backend.

## Not done / known limits

Blocking production:

1. **No hosted project.** Everything here was verified on the local stack only.
   That proves the logic, not devices on different networks. To go live, the
   owner creates a production project, applies migrations 0001–0012, keeps
   e-mail confirmation on (or turns off open sign-up and invites), sets a real
   minimum password length and SMTP, and builds with a `dart_define.prod.json`
   kept outside git.
2. **Prices are computed on the device.** The server enforces structure: who may
   do what, resources, pads, idempotency, sign of money, and staleness. It does
   not check amounts. A member with `bill` and direct API access could under-bill.
   This was accepted by design in Phase 1; server-side re-pricing is the fix.
3. **Real-device, cross-network test** (two phones on different networks, one
   going offline mid-shift) has not been done.

Worth doing next:

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
