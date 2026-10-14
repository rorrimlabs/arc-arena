# arena_ops — Implementation Plan & Checklist

> **Status (2026-10-14).** This plan is kept as history. *Backend strategy*,
> *Architecture* (the directory tree) and the *Phase 5+* section describe the
> pre-sync plan and are superseded; the Phase 0–4 checklists record what was
> built for the floor app. Current state: Supabase sync with Realtime nudges is
> built and verified on the local stack only (hosted dev has migrations up to
> 0015; nothing later is pushed); owner features live on the admin dashboard (`apps/admin`);
> staff join by invitation; release builds are cloud-only. Current docs:
> [`CLAUDE.md`](../CLAUDE.md) (scope, architecture, conventions),
> [`SYNC.md`](SYNC.md), [`DEPLOY_SUPABASE.md`](DEPLOY_SUPABASE.md),
> [`RELEASE.md`](RELEASE.md), [`supabase/README.md`](../supabase/README.md).

Staff-first Gaming Center Operations app. One Flutter codebase, responsive phone (personal)
+ tablet (counter). Correctness of **timing, pricing, and records** outranks everything else.

## Backend strategy (important)

Claude cannot provision a Supabase project (requires owner login). Therefore:

- **Domain layer** (pricing, rules, clock, entities) is pure Dart — built & tested now, no backend.
- **Data layer** uses a **repository abstraction** with two implementations:
  - `local` (Drift/SQLite) — the **default**, makes the app runnable on-device immediately.
    Timers persist as **timestamps**, survive restart. Conflict checks run client-side through
    the same domain `AvailabilityService`. Correct for a **single counter device**.
  - `supabase` — Postgres + RPCs + RLS, selected via `--dart-define=AO_BACKEND=supabase`
    plus `AO_SUPABASE_URL` / `AO_SUPABASE_ANON_KEY`. SQL lives in `supabase/`. This is what
    makes **multi-device** (phone + tablet simultaneously) concurrency-safe.
- Multi-device concurrency is only guaranteed once the Supabase backend is live and tested.
  Until then the app is honest about running in local mode.

## Tech stack (mandated)

Flutter · Riverpod · go_router · freezed · json_serializable · Supabase/Postgres · Drift/SQLite.
Money = integer **paise** (`bigint`). Times = `timestamptz` UTC. Business rules = Asia/Kolkata.

> IST is a fixed UTC+05:30 offset with no DST, so business-day math uses a fixed offset
> (no heavyweight `timezone` dependency). Documented assumption.

## Architecture

```
lib/
  core/      clock/ · money/ · result/ · theme/ · config/ · time/ (IST business day)
  domain/    entities/ · value/ · services/ · pricing/ · rules/
  data/      repositories/ (interfaces) · local/ (Drift) · supabase/ · dto/
  features/  floor/ · new_session/ · customers/ · games/ · reports/ · settings/
  app/       router/ · providers/ · bootstrap/
supabase/    migrations/ · seed.sql · tests/
```

No pricing, timer-truth, or DB calls inside widgets.

## Phase checklist

### Phase 0 — Setup (CURRENT)
- [ ] Dependencies + build_runner wired and clean
- [x] Directory structure
- [x] `Clock` abstraction (+ fake) and IST business-day helper
- [x] Money (paise) value type
- [x] `Result` type
- [x] Theme (M3, monospace digits, ≥56px targets, dark-friendly)
- [x] Navigation shell: 5 bottom tabs (Today/Floor/Money/Reports/More), max depth 2, no hamburger.
      Customers ("Members") and the Games library live under More → (Members / Settings → Games).
      (Updated by the 404 re-skin; the earlier 4-tab Floor/Customers/Games/Reports plan is superseded.)
- [x] Supabase migrations + seed.sql (schema only; RPCs stubbed, filled Phase 2)
- [x] `flutter analyze` clean, app boots to Floor placeholder

### Phase 1 — Domain engine ✅
- [x] Entities (freezed): Customer, Activity, Resource, Game, Session, Extension, Charge, Payment, BillingPolicy, Rate; pure value objects for pricing
- [x] `PricingService` (pure): band-splitting, happy-hour split, per-activity billing, paise, rounding
- [x] `AvailabilityService`: overlap, touching boundaries, max-extension, closing-time, RIFT PS5↔VR
- [x] `SessionPlanner` + `SessionTimer` (start/extend plans, timer derivation)
- [x] Exhaustive pricing + rules + timer tests (fake clock)

### Phase 2 — Floor loop
- [x] Drift schema + local repositories + seed load (clock-stamped)
- [x] Riverpod providers; live timer derived from timestamps
- [x] New Session flow (customer/activity/station/game/controllers/duration), price preview
- [x] Active cards: elapsed/remaining/overtime, controls, extend, end
- [x] Extension flow (validation, max-extension, confirm, history)
- [x] End + Payment (append-only payments, partial/pending/change/waived)
- [x] DB-integrity tests (overlap rejected, idempotent end, payments sum) + integration test
- [x] Game controls bottom sheet (button tokens → PS glyphs)
- [x] Customers tab screen (search/list/create) + profile with derived stats & history
- [x] Clock-offset banner infrastructure (inert in local mode; lights up with Supabase server time)
- [ ] Offline disables start/extend — N/A in local mode (local DB always available); activates with the Supabase backend (§36)

### Phase 3 — Library, controls, report ✅
- [x] Today owner report model (billed/collected/pending/…) — Today tab + Money tab live
- [x] Game Library CRUD screen (disable-not-delete; add/edit name, category, platform, player
      mode, max players, active flag, per-system compatibility) — `games_screen` + `game_edit_screen`
- [x] Game Controls editor (`controls_edit_screen`, reached from Settings → Games → a game →
      Controls guide). No paste parser; controls are entered row by row.
- [x] Reports tab over real persisted rows: collected/billed/pending, sessions, gaming hours,
      customers, revenue by activity / payment method / price band, takings by day, station
      utilisation, most-played games, session history, Today/Week/Month/Custom, `.xlsx` export
      (`domain/reports/`, `features/reports/`)
- [x] Pending-payment queue on the Floor (`widgets/awaiting_payment.dart`)

### Segment model + compatibility + booking (staff-floor spec) ✅
Refactor: a session is now a **parent + segments** (spec §9). One continuous paid
session can switch system / game / controller count; each change closes the open
segment and opens a new one at the exact instant (no lost/overlapping time). The
**bill is computed from every segment** via `SegmentBilling` (sum segment
subtotals in paise, round cash once). DB enforces **one open segment per
resource** (also RIFT PS5⊕VR).
- [x] Game↔resource **compatibility matrix** (playable/not-playable/not-installed/
      maintenance/temp-unavailable), editable; games never globally available.
- [x] Game library fields: player mode + max local players; library edit screen.
- [x] Floor active card actions: Controls / Switch / Change Game / Change
      Controllers / History / Extend / End; View Games per station.
- [x] **Booking** (game-first availability, any/specific system, full-period
      conflict check, RIFT rule) + **check-in** → session linked by `bookingId`,
      booking preserved as the planned record.
- [x] Tests: segment switch/controller billing, compatibility, booking
      availability + check-in, updated integration (start→switch→extend→end→pay→report).

> `supabase/migrations/0004_segments_groups_and_config.sql` now carries the segment, group,
> per-system-availability and configuration tables. Unapplied and unexecuted — review it
> against a real Postgres before trusting it. *(2026-10-14: superseded — 0004 is part of the
> applied migration history; see the status banner.)*

### Phase 4 — owner configuration ✅
- [x] Stations: add / edit / disable / maintenance, refused while a station is in use
- [x] Opening hours per weekday + happy-hour window, persisted (was hardcoded). *2026-10-15: the happy-hour window, band and per-type flag are gone; happy hours are a pricing rule.*
- [x] Holidays, with a per-holiday "closed all day" switch
- [x] Rate card editor (price + unit per activity/band/controller count)
- [x] Billing rules editor (every OWNER CONFIRMATION knob)
- [x] Staff & roles editor, with a guard against removing the last Settings access

### Phase 5+ — Supabase sync, multi-device conflict policy (later)
*(2026-10-14: superseded — sync, the outbox and the conflict policy are built; see
[`SYNC.md`](SYNC.md). The paragraph below is the original plan.)*
`supabase/migrations/0004_segments_groups_and_config.sql` brings the SQL up to the shipped
schema (segments, groups, per-system game availability, config). It is **written but never
applied or executed** — there is no Supabase project and no local Postgres — so it is a
starting point to review, not a verified migration. No Dart client, no outbox, no sync.

## Process gate per phase
`flutter analyze` → relevant tests → fix all → explain → list remaining edge cases.
Do not advance if core tests fail.
