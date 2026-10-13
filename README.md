# arena_ops

Staff-first **Gaming Center Operations** app. One Flutter codebase, responsive on
an Android phone (personal staff device) and a counter tablet. Correctness of
**timing, pricing and records** is the priority.

> Full specification: the brief this was built from. Planning & phase checklist:
> [`docs/PLAN.md`](docs/PLAN.md). Unconfirmed business rules:
> [`docs/OWNER_CONFIRMATION.md`](docs/OWNER_CONFIRMATION.md).

## Running

Flutter commands run from `apps/mobile/`. Default backend is **local**
(Drift/SQLite, debug builds only) — runs on-device with no server:

```bash
flutter run
```

Cloud mode (several devices sharing one arena through Supabase) needs the
backend URL and publishable key at build time:

```bash
flutter run --dart-define-from-file=dart_define.hosted-dev.json
```

`bash tool/dev_run.sh -d "<device>"` runs it against the local Supabase stack.
Release builds are cloud-only (`--dart-define-from-file=dart_define.prod.json`
plus the signing key — [`docs/RELEASE.md`](docs/RELEASE.md)). The owner's admin
dashboard is `apps/admin` (`npm run dev`). See **Backend** below.

## Verify

```bash
flutter analyze
flutter test
```

`bash tool/verify_all.sh` runs every automated check — Flutter analyze and
tests, the admin unit tests and build, pgTAP and the advisors on the local
Supabase stack — and reports each step PASS/FAIL/SKIP. `--with-it` adds the
cross-app sync integration (`tool/sync_it.sh`), `--with-psql` the pricing
parity check and the concurrency races (docs/SYNC.md).
The pricing engine, session/segment rules, availability, booking
conflicts and the reporting engine are pure Dart and tested directly; the floor,
payment queue and walk-in flow are covered by widget tests at phone and desktop
sizes.

## Business rules

Open **Tue–Sun 2–11 PM (Monday closed)**, happy hour **Tue–Fri 2–5 PM**. None of
that is compiled in — hours, holidays, the rate card, the billing rules and the
station list are all stored as data and edited on the admin dashboard (or, with
the Settings permission, in the floor app's **More → Settings**). A session captures
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

Without the Supabase dart-defines it is single-device and the UI says "Local
mode · saved on this device". In cloud mode each person signs in with their own
login (owners register on the admin dashboard; staff and co-owners join only by
accepting an e-mailed invitation); every write goes into the device database and a sync outbox in one
transaction, is pushed to Supabase (`sync_push`, which re-checks permissions,
floor rules and prices), and other devices pull it — a Realtime nudge on the
arena's private channel triggers the pull within about a second, with a 10 s
poll as the fallback. Conflicting offline work is refused and shown under Sync, never
merged silently. Design, limits and how to run it: [`docs/SYNC.md`](docs/SYNC.md);
hosted setup: [`docs/DEPLOY_SUPABASE.md`](docs/DEPLOY_SUPABASE.md). Schema
changes are made in the declarative files under `supabase/schemas/`; migrations
in `supabase/migrations/` are generated from them (`supabase/README.md`).
