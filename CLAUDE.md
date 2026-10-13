# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`arena_ops` — staff-first gaming-center operations app (404 Arena). One Flutter codebase, responsive on an Android phone and a counter tablet. Correctness of **timing, pricing and records** is the priority. Planning/phase checklist: `docs/PLAN.md`; unconfirmed business rules and their defaults: `docs/OWNER_CONFIRMATION.md`; backup/migration/release runbook: `docs/RELEASE.md`.

**Product scope (SLC — simple, lovable, complete):** the Flutter app is **staff only** for now: the floor (start / switch / extend / end sessions, take payments, groups, bookings, controllers, members as their permissions allow). **Everything an owner does lives on the admin web dashboard** (`apps/admin/`): sales and reports, voids, stations, games, pricing, users, settings. Do not build owner features in the mobile app; owner screens there (Today, Money, Reports, Settings) are to be hidden later, not extended. Owner-side mobile comes back after the SLC.

Repo layout:

| Path | What |
|---|---|
| `apps/mobile/` (`lib/`, `test/`, platform dirs) | Flutter staff app — run every `flutter`/`dart` command from this folder |
| `apps/admin/` | Angular 22 admin web app (standalone components, signals, Tailwind 4, Vitest). Its own rules live in `apps/admin/CLAUDE.md` (there is no `AGENTS.md`) and load automatically when working in that folder — follow them for any Angular code. Run its commands from `apps/admin/` (`npm run dev` = `ng serve` on port 4200 — there is no `npm start`; `npm run build`, `npm test`). Prefer the `angular-cli` MCP server (root `.mcp.json`) over shelling out to `ng`. |
| `supabase/` | Postgres backend: declarative schema (`schemas/`), generated migrations, pgTAP tests, seed, Edge Functions (`functions/`: `staff-admin` sends invitations — `invite_member` as the caller, then the e-mail through Supabase Auth; the only holder of the service-role key, server-side only). Map of tables/functions and the security model: `supabase/README.md` |
| `design/` | Design references: `admin.html` = final admin design export (how to decode and read it: `.claude/commands/design-build.md`; build screens with `/design-build <screen>`); `404 Arena App (offline).html` = staff app design |
| `tool/` | `verify_all.sh` (every automated check, one entry point), `sync_it.sh` (cross-app integration, local stack only), `dev_run.sh` (floor app against the local stack), `pricing_parity.sh` |
| `.agents/skills/` (linked into `.claude/skills/`) | Agent skills installed with `npx skills add` (tracked in `skills-lock.json`): `supabase` and `supabase-postgres-best-practices`. Use them for any Supabase/Postgres work. |

## Commands

Flutter (from `apps/mobile/`):

```bash
flutter pub get
flutter run                                   # local Drift/SQLite backend (default)
flutter analyze                               # must be clean
flutter test                                  # full suite
flutter test test/domain/pricing/pricing_rates_test.dart          # one file
flutter test test/domain/pricing/pricing_rates_test.dart --plain-name "happy hour"   # one test by name
dart run build_runner build --delete-conflicting-outputs          # regen *.freezed.dart / *.g.dart / database.g.dart
flutter build apk --release --split-per-abi --dart-define-from-file=dart_define.prod.json   # counter tablet uses app-arm64-v8a-release.apk
```

Release builds are **cloud-only**: Gradle refuses a release task without `AO_BACKEND=supabase` in the dart-defines or without `android/key.properties` (git-ignored; never signs with the debug key), and at start `AppConfig.problemFor` refuses local mode, a missing/non-https/development URL and any secret or `service_role` key. Details: `docs/RELEASE.md`.

Generated files (`*.freezed.dart`, `*.g.dart`, `apps/mobile/lib/data/local/database.g.dart`) are committed — regenerate after editing entities or Drift tables, never hand-edit. `build.yaml` makes Drift store `DateTime` as ISO-8601 UTC text; keep it that way.

## Supabase — declarative schemas only

`supabase/schemas/` is the **single source of truth** for the Postgres schema, in the layout `supabase db schema declarative generate` produces: `public/tables/<table>.sql`, `public/functions/<fn>.sql`, `public/views/`, `public/sequences/`, `public/default_privileges.sql`, `private/` (`schema.sql`, `default_privileges.sql`, `functions/`), `realtime/policies.sql`, `_cluster/extensions/`, `_cluster/publications.sql`. Each file holds one object with its indexes, triggers, RLS policies, grants and `comment on` documentation. The CLI's **pg-delta** engine (`[experimental.pgdelta] enabled = true` in `supabase/config.toml`) diffs those files against the migration history. Migrations in `supabase/migrations/` are **generated output — never write, edit, rename or delete a migration file by hand** (an `Edit(supabase/migrations/**)` deny rule enforces this). `0001`–`0016` are the original hand-written history, kept as the baseline.

To change the schema:
1. edit the desired end state in `supabase/schemas/` (add the column to the `create table`, change the function body, add the policy/grant/comment to the object's file — not `alter` statements); a new object gets a new file in the matching folder;
2. `supabase db schema declarative sync --name <descriptive_name> --no-apply` generates the migration — **read it**; then `supabase migration up --local` applies it;
3. **run the same sync again with `--no-apply`**: it must say "No schema changes found". pg-delta can miss grants/revokes created in the same run; if it generates something, review and apply it too;
4. verify: `supabase test db --local` (pgTAP in `supabase/tests/`), `supabase db advisors --local --type all`.

`supabase db diff` does **not** read `supabase/schemas/` in this CLI version — don't use it here. Data is not part of the schema (it goes in `supabase/seed.sql`). If a change can't be expressed in the schema files, **stop and ask** rather than hand-writing a migration. Never push to a remote project without being asked.

Security conventions (asserted by `supabase/tests/13_security_hardening_test.sql`):
- **Every object file states its client grants explicitly.** A new table/view/function/sequence file must end with `revoke all … from anon;` and `revoke all … from authenticated;` (then any deliberate grant). pg-delta's shadow database applies default privileges, so a missing explicit revoke turns into a generated `grant … to anon` — always check generated migrations for that.
- `anon` can reach nothing. `authenticated` may only `select` tables (RLS: `to authenticated using (arena_id in (select private.app_arena_ids()))`; `payments`, `group_payments`, `session_charges`, `group_charges` need `bill`/`money`/`reports`, `customers` needs `start`/`members`/`money`/`reports`, `audit_log` owner level — via `private.app_arena_ids_with(perms)`; `staff_invites` has no client access) and execute the client API: `sync_push`, `sync_pull`, `sync_fetch_entity`, `my_arenas`, `create_my_arena`, `invite_member`, `accept_invite`, `revoke_invite`, `arena_invites`, `arena_staff`, `arena_sales`, `arena_sale`, `arena_pricing`, `app_is_owner`.
- **No SECURITY DEFINER function in an exposed schema is executable by `anon` or `authenticated`** (Security Advisor lints 0028/0029 check exactly that; test 13 asserts it). The client API's definer bodies and the RLS helpers (`private.app_arena_ids`, `private.app_has_perm`, `private.app_is_owner`, `private.app_arena_ids_with(perms)`, `private.can_use_arena_topic(topic)`) live in `supabase/schemas/private/` (schema `private`, never in config.toml `[api] schemas`); `public` holds `security invoker` wrappers with the same names/arguments that call `private.<fn>`. Server-only definer functions (`op_*`, `_pr_*`, other `_` helpers, `bootstrap_owner`, `_seed_arena_catalog`, and `invite_delivery_target`, which only `service_role` may execute — the Edge Function uses it) stay in `public` without client EXECUTE. A new client RPC = a definer body in `private/functions/` + an invoker wrapper in `public/functions/`; code calls helpers as `private.app_*()`. A 42501 on a client RPC is a refusal (no membership/permission) or, without a valid session, a call that ran as `anon` — fix the client, never grant to `anon`.
- **Joining an arena is by invitation only.** Owners self-register (`create_my_arena`) or the operator runs `bootstrap_owner`; everyone else accepts an invitation (`invite_member` → e-mailed link → `accept_invite` by the invited, confirmed login). No function links an existing login without its consent.
- **All writes go through `sync_push`** → `_sync_apply` → an `op_*` function (`security definer`, `set search_path`, checks `_need(arena, perm)`). No insert/update/delete policies exist.
- Views use `security_invoker = true`.

`supabase` and `docker` are excluded from the Bash sandbox (they need the Docker socket and `~/.supabase`); Docker Desktop must be running.

## Architecture

Layered under `apps/mobile/lib/`; dependencies point inward:

- `core/` — cross-cutting primitives: `Clock` (UTC; `FakeClock` in tests), `Result`/`Failure`, money (`paise.dart`, `rounding.dart`, `rupee_input.dart` — typed rupees to paise exactly, string/integer arithmetic, max 2 decimals), IST/business-calendar time, theme (`arena_*` palette/type), shared widgets.
- `domain/` — pure Dart, no Flutter/DB. Freezed entities, repository **interfaces**, command objects (`repositories/commands.dart`, `group_commands.dart`), and the rule engines: `pricing/` (pricing service, immutable `PricingSnapshot`, billing policy), `services/` (availability, session planner/timer, segment & group billing, pad selection, payment rules), `reports/`, `auth/` (permissions, `PermissionGuard`, PBKDF2 PIN credentials).
- `data/local/` — Drift implementation: `database.dart` (all tables + migrations), `Local*Repository` classes implementing the domain interfaces, mappers, seed data, `db_safety.dart`.
- `app/` — wiring: Riverpod providers (`providers/`), go_router (`router/`), auth controller, and **action controllers** (`controllers/session_actions.dart`, `booking_actions.dart`, `group_session_actions.dart`, `catalog_actions.dart`, `customer_actions.dart`) that orchestrate domain services + repositories + clock.
- `features/<area>/presentation|application/` — screens and sheets (floor, new_session, group_sessions, bookings, controllers, customers, money, reports, more/settings, …).

Flow for any mutation: widget → action controller (checks `PermissionGuard`, prices with pure services, builds a command) → repository (re-checks conflicts, writes atomically) → `Result<T>`. **No pricing, availability checks, timestamp math or DB calls in widgets.** `Failure` carries `message` + `fix` + stable `code` (e.g. `resource_busy`) so the UI never invents error copy. Permission checks live in the action layer, not just by hiding buttons.

### Invariants that bite

- **Money is integer paise.** No doubles for currency.
- **Instants are UTC** everywhere; business rules (hours, happy hour, holidays) use Asia/Kolkata fixed +05:30 via `core/time/`. Always get "now" from `clockProvider`, never `DateTime.now()`.
- **Timers are derived from stored timestamps**, never an incrementing counter.
- A session captures an immutable **pricing snapshot** at start; rate changes never move an issued bill. Sessions are split into **segments** (switch system / change game / change controllers close the open segment and open a new one); one open segment per resource.
- Hours, holidays, rate card, billing rules and stations are **data** (admin dashboard; More → Settings in the floor app), not compiled constants. New arenas start empty — the owner builds the catalog on the dashboard.
- Controllers (pads) are tracked physically: allocations, cross-station borrow/move with history.

### Database safety and migrations

The device DB is the only copy of the day's takings. `main()` calls `DbSafety.protect` **before** opening `AppDatabase` (Drift migrates on open): it takes a WAL-checkpointed, integrity-verified backup and refuses to open (`DatabaseLockedApp`) if a migration is pending without a verified backup.

To change the schema:
1. bump `AppDatabase.expectedSchemaVersion`;
2. add an **additive** step to `_steps` in `database.dart` (`_steps[n]` = v`n` → v`n+1`; never drop/rewrite user rows);
3. add a case to `apps/mobile/test/data/local/migration_test.dart` that builds the old shape with real session/segment/payment rows and asserts they survive.

`db_safety_test.dart` fails the build on gaps in the step chain.

### Backend status

Local-first. The default build runs on Drift/SQLite only. `--dart-define-from-file=dart_define.<env>.json` with `AO_BACKEND=supabase` (`core/config/app_config.dart`) turns on multi-device sync: every local write also lands in an outbox that is pushed through `sync_push`, and other devices' changes arrive through `sync_pull` (`lib/data/sync/`, `lib/app/sync/`; design in `docs/SYNC.md`). Realtime (private channel `arena:<arena uuid>`, `realtime_sync.dart`) only nudges a pull — no business data travels in it; the 10 s poll stays as the fallback. Only the anon/publishable key ever goes into the app. Release builds run cloud mode only; debug builds without defines run local mode (demo catalog, demo PINs).

## Tests

`apps/mobile/test/` mirrors `lib/` (`domain/`, `data/local/`, `app/`, `features/`, plus `integration/` and `sync/` — the live cross-app specs, which skip themselves outside `tool/sync_it.sh`, as do `apps/admin/src/integration/*.it.spec.ts`). Use `test/support/test_db.dart`: `seededMemoryDb()` for an in-memory seeded Drift DB and `testOverrides(db, clock: FakeClock(...), auth: TestStaffAuth.new)` for `ProviderScope` overrides (defaults to a signed-in owner and a no-op notification service). `test/support/pricing_fixtures.dart` holds pricing fixtures. Widget tests cover phone and desktop sizes.

### Verification: automated only — the user does manual testing

Verify changes with the automated checks only: `flutter analyze` + `flutter test` (mobile), `npm run build` + `npm test` (admin), `supabase test db --local` + advisors (backend). `bash tool/verify_all.sh` runs all of them (the admin build with the development config; PASS/FAIL/SKIP per step, non-zero exit on any failure); `--with-it` adds `tool/sync_it.sh`, `--with-psql` adds pricing parity and the concurrency races. The declarative drift check (sync `--no-apply` → "No schema changes found") stays manual. **Do not** do manual or visual testing yourself: no headless-browser/puppeteer screenshot scripts, no driving the running app, no inspecting build output (`dist/` bundles, chunk contents). The user tests the UI by hand; when a change is done, hand over the route/screen and a short checklist of what to click through instead.
