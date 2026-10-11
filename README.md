# arena_ops

Staff-first **Gaming Center Operations** app. One Flutter codebase, responsive on
an Android phone (personal staff device) and a counter tablet. Correctness of
**timing, pricing and records** is the priority.

> Full specification: the brief this was built from. Planning & phase checklist:
> [`docs/PLAN.md`](docs/PLAN.md). Unconfirmed business rules:
> [`docs/OWNER_CONFIRMATION.md`](docs/OWNER_CONFIRMATION.md).

## Running

Default backend is **local** (Drift/SQLite) — runs on-device with no server:

```bash
flutter run
```

`--dart-define=AO_BACKEND=supabase` is accepted but **does not yet sync
anything** — there is no Supabase client, so the app still reads and writes the
local database and the status strip says so. The flag exists as the seam for
that work; see **Backend** below.

## Verify

```bash
flutter analyze
flutter test
```

180 tests. The pricing engine, session/segment rules, availability, booking
conflicts and the reporting engine are pure Dart and tested directly; the floor,
payment queue and walk-in flow are covered by widget tests at phone and desktop
sizes.

## Business rules

Open **Tue–Sun 2–11 PM (Monday closed)**, happy hour **Tue–Fri 2–5 PM**. None of
that is compiled in — hours, holidays, the rate card, the billing rules and the
station list are all stored and edited in **More → Settings**. A session captures
an immutable pricing snapshot when it starts, so changing a rate never moves a
bill that has already been issued. Rules the owner has not confirmed are listed
in [`docs/OWNER_CONFIRMATION.md`](docs/OWNER_CONFIRMATION.md) with their
defaults.

## Architecture

Clean layering (`lib/core`, `lib/domain`, `lib/data`, `lib/features`, `lib/app`).
No pricing, timer-truth or DB calls live in widgets. The pricing engine and
session/availability rules are pure Dart and heavily tested. Money is integer
paise; instants are UTC; business rules use Asia/Kolkata (fixed +05:30).

## Backend

The app is **local-first**: Drift/SQLite on the device is the source of truth, so
sessions, segments, payments and bookings survive a refresh, a restart and a total
loss of connectivity — there is no network in the write path to fail. Timers are
derived from stored timestamps, never from a counter.

It is **single-device**. There is no Supabase project (creating one needs the
owner's login), no Dart client, no outbox and no sync, so the UI says "Local mode
· saved on this device" rather than a fake Online/Offline indicator.
`supabase/migrations/` holds the SQL to apply when a project exists; `0004` brings
it up to the shipped schema but has never been applied or executed against a real
Postgres. See `docs/WORKFLOW_AUDIT_2026-10-10.md` §4.
