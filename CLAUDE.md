# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`arena_ops` — staff-first gaming-center operations app (404 Arena). One Flutter codebase, responsive on an Android phone and a counter tablet. Correctness of **timing, pricing and records** is the priority. Planning/phase checklist: `docs/PLAN.md`; unconfirmed business rules and their defaults: `docs/OWNER_CONFIRMATION.md`; backup/migration/release runbook: `docs/RELEASE.md`.

Repo layout:

| Path | What |
|---|---|
| repo root (`lib/`, `test/`, platform dirs) | Flutter staff app |
| `apps/admin/` | Angular 22 admin web app (standalone components, signals, Tailwind 4, Vitest). Its own rules live in `apps/admin/CLAUDE.md` (identical to its `AGENTS.md`) and load automatically when working in that folder — follow them for any Angular code. Run its commands from `apps/admin/` (`npm start`, `npm run build`, `npm test`). Prefer the `angular-cli` MCP server (root `.mcp.json`) over shelling out to `ng`. |
| `supabase/` | Postgres schema (declarative), pgTAP tests, seed |
| `.agents/skills/` (linked into `.claude/skills/`) | Agent skills installed with `npx skills add` (tracked in `skills-lock.json`): `supabase` and `supabase-postgres-best-practices`. Use them for any Supabase/Postgres work. |

## Commands

```bash
flutter pub get
flutter run                                   # local Drift/SQLite backend (default)
flutter analyze                               # must be clean
flutter test                                  # full suite
flutter test test/domain/pricing/pricing_rates_test.dart          # one file
flutter test test/domain/pricing/pricing_rates_test.dart --plain-name "happy hour"   # one test by name
dart run build_runner build --delete-conflicting-outputs          # regen *.freezed.dart / *.g.dart / database.g.dart
flutter build apk --release --split-per-abi   # counter tablet uses app-arm64-v8a-release.apk
```

Generated files (`*.freezed.dart`, `*.g.dart`, `lib/data/local/database.g.dart`) are committed — regenerate after editing entities or Drift tables, never hand-edit. `build.yaml` makes Drift store `DateTime` as ISO-8601 UTC text; keep it that way.

## Supabase — declarative schemas only

`supabase/schemas/*.sql` is the **single source of truth** for the Postgres schema (`[db.migrations] schema_paths` in `supabase/config.toml`; files apply in that order). Migrations in `supabase/migrations/` are **generated output — never write, edit, rename or delete a migration file by hand** (an `Edit(supabase/migrations/**)` deny rule enforces this).

To change the schema:
1. edit the desired end state in `supabase/schemas/` (add a column to the `create table`, change the function body, etc. — not `alter` statements);
2. `supabase stop` (diff needs the local DB stopped), then `supabase db diff -f <descriptive_name>` to generate the migration;
3. review the generated SQL; `supabase start` (or `supabase migration up`) applies it; `supabase db reset` rebuilds from scratch + `seed.sql`;
4. verify: `supabase test db` (pgTAP in `supabase/tests/`), `supabase db advisors`, and for locking changes `bash supabase/concurrency_tests/run.sh`.

The diff engine does not capture DML (data goes in `supabase/seed.sql`) and has known blind spots (e.g. view ownership/`security_invoker`, materialized views, `alter policy`, comments, partitions, publications, domains, some grants). If a change needs one of those, **stop and ask** rather than hand-writing a migration. Never push to a remote project without being asked.

`supabase` and `docker` are excluded from the Bash sandbox (they need the Docker socket and `~/.supabase`); Docker Desktop must be running.

## Architecture

Layered under `lib/`; dependencies point inward:

- `core/` — cross-cutting primitives: `Clock` (UTC; `FakeClock` in tests), `Result`/`Failure`, money (`paise.dart`, `rounding.dart`), IST/business-calendar time, theme (`arena_*` palette/type), shared widgets.
- `domain/` — pure Dart, no Flutter/DB. Freezed entities, repository **interfaces**, command objects (`repositories/commands.dart`, `group_commands.dart`), and the rule engines: `pricing/` (pricing service, immutable `PricingSnapshot`, billing policy), `services/` (availability, session planner/timer, segment & group billing, pad selection, payment rules), `reports/`, `auth/` (permissions, `PermissionGuard`, PBKDF2 PIN credentials).
- `data/local/` — Drift implementation: `database.dart` (all tables + migrations), `Local*Repository` classes implementing the domain interfaces, mappers, seed data, `db_safety.dart`.
- `app/` — wiring: Riverpod providers (`providers/`), go_router (`router/`), auth controller, and **action controllers** (`controllers/session_actions.dart`, `booking_actions.dart`, `group_session_actions.dart`) that orchestrate domain services + repositories + clock.
- `features/<area>/presentation|application/` — screens and sheets (floor, new_session, group_sessions, bookings, controllers, customers, money, reports, more/settings, …).

Flow for any mutation: widget → action controller (checks `PermissionGuard`, prices with pure services, builds a command) → repository (re-checks conflicts, writes atomically) → `Result<T>`. **No pricing, availability checks, timestamp math or DB calls in widgets.** `Failure` carries `message` + `fix` + stable `code` (e.g. `resource_busy`) so the UI never invents error copy. Permission checks live in the action layer, not just by hiding buttons.

### Invariants that bite

- **Money is integer paise.** No doubles for currency.
- **Instants are UTC** everywhere; business rules (hours, happy hour, holidays) use Asia/Kolkata fixed +05:30 via `core/time/`. Always get "now" from `clockProvider`, never `DateTime.now()`.
- **Timers are derived from stored timestamps**, never an incrementing counter.
- A session captures an immutable **pricing snapshot** at start; rate changes never move an issued bill. Sessions are split into **segments** (switch system / change game / change controllers close the open segment and open a new one); one open segment per resource.
- Hours, holidays, rate card, billing rules and stations are **data** (More → Settings), not compiled constants.
- Controllers (pads) are tracked physically: allocations, cross-station borrow/move with history.

### Database safety and migrations

The device DB is the only copy of the day's takings. `main()` calls `DbSafety.protect` **before** opening `AppDatabase` (Drift migrates on open): it takes a WAL-checkpointed, integrity-verified backup and refuses to open (`DatabaseLockedApp`) if a migration is pending without a verified backup.

To change the schema:
1. bump `AppDatabase.expectedSchemaVersion`;
2. add an **additive** step to `_steps` in `database.dart` (`_steps[n]` = v`n` → v`n+1`; never drop/rewrite user rows);
3. add a case to `test/data/local/migration_test.dart` that builds the old shape with real session/segment/payment rows and asserts they survive.

`db_safety_test.dart` fails the build on gaps in the step chain.

### Backend status

Local-first, single-device. `--dart-define=AO_BACKEND=supabase` (`core/config/app_config.dart`) is only a seam — there is no Supabase client, sync or outbox, and the UI must say so honestly rather than show a fake online indicator. `supabase/schemas/` is the intended Postgres schema (RLS, RPCs) and has not been applied to a real project.

## Tests

`test/` mirrors `lib/` (`domain/`, `data/local/`, `app/`, `features/`, plus `integration/`). Use `test/support/test_db.dart`: `seededMemoryDb()` for an in-memory seeded Drift DB and `testOverrides(db, clock: FakeClock(...), auth: TestStaffAuth.new)` for `ProviderScope` overrides (defaults to a signed-in owner and a no-op notification service). `test/support/pricing_fixtures.dart` holds pricing fixtures. Widget tests cover phone and desktop sizes.
