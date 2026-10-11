# Workflow audit — 2026-10-10

Audit of `arena_ops` against the "Fix the Gaming Cafe Staff App" brief.
**Baseline before any change:** `flutter analyze` clean, `flutter test` **152 passed**.

> This supersedes the progress log in `STAFF_SECTION_AUDIT.md`, parts of which
> describe work that is **not in the code** (see §0).

## 0. Corrections to the previous audit's progress log

Claims verified against the source, not taken on trust:

| Claim in `STAFF_SECTION_AUDIT.md` | Reality |
|---|---|
| "C3 View Games per station: wired … to a 'Games' action on available station cards" | **Not wired.** `sheets/view_games_sheet.dart` has no caller anywhere in `lib/`. `station_card.dart` renders only `Start`. |
| "Floor grid is now single column on phones (`width < 520`)" | **Not present.** `floor_screen.dart` computes `4 / 3 / 2` columns; the narrowest branch is 2, so a 390 px phone still gets two columns. |
| "C2 Custom duration" | **Correct** — wired in new-session, booking, extend. |
| "Step 6 access control" | **Correct** — PIN login, roles, permission-gated nav all present. |

## 1. What is already right (verified in code + tests)

The core is genuinely good and is **kept**, not rebuilt:

- **Pricing** (`domain/pricing/pricing_service.dart`) — pure, integer paise, exact
  rational arithmetic, happy-hour boundary splitting, per-activity duration models,
  immutable per-session snapshots. Heavily tested.
- **Timing** (`domain/services/session_timer.dart`) — derived purely from
  `startedAt` / `scheduledEndAt` / `actualEndedAt`. No counter anywhere.
- **Segments** — parent session + ordered segments; system/game/controller changes
  close one segment and open the next at the same instant, preserving the parent
  countdown. DB unique index `ux_one_open_segment_per_resource` enforces one open
  segment per resource (and therefore RIFT PS5 ⊕ VR).
- **Group sessions** — one shared countdown, many concurrent per-player assignments,
  `perSystem` vs `sharedControllerPool` billing modes.
- **Bookings** — game-first availability over the whole requested period, RIFT rule,
  check-in that preserves the planned record.
- **Payments** — append-only, partial / paid / waived, refunds require a reason.
- **Local-first persistence** (Drift/SQLite) + offline device-scheduled reminders.

## 2. Gaps against the brief (what this work fixes)

| # | Gap | Brief | Severity |
|---|-----|-------|----------|
| G1 | **Operating hours wrong.** Code opens **Mon–Sun** and runs happy hour **Mon–Fri**. Brief: open **Tue–Sun, Monday closed**; happy **Tue–Fri**. | §8 | **Correctness** |
| G2 | **Business hours hardcoded** in `BusinessHours.current()` — not persisted, no editor. | §2, §8 | High |
| G3 | **Reports are 100 % placeholder** — all ten rows open "This report is on the way." | §13 | High |
| G4 | **No Excel export.** | §13 | Medium |
| G5 | **Resources cannot be added/edited/disabled/maintained.** `CatalogRepository` has no resource mutation at all. | §2 | High |
| G6 | **Rates / billing policy / holidays persist but have no editor.** | §8 | High |
| G7 | **Floor card omits required facts** — no customer name ("by whom"), no controller count, no start time, no scheduled end. | §3 | High |
| G8 | **No "awaiting payment / checkout" view** on the staff home screen. | §3 | High |
| G9 | **Occupied-card actions appear only when ending/overtime**; otherwise every action costs a navigation. | §3 | Medium |
| G10 | **Two columns at phone width** — cramped for the required extra facts. | §3, §14 | Medium |
| G11 | `ResourceStatus` lacks **temporarilyUnavailable**; **Reserved** is never surfaced from upcoming bookings. | §2 | Medium |
| G12 | **Per-system game status has no notes field** and cannot be changed from the floor. | §5 | Medium |
| G13 | **`view_games_sheet.dart` is dead code** (plus three other unused widgets). | §5, §14 | Low |
| G14 | **Bookings cannot be edited**; no `notes`, no party name/phone for walk-ins, no reminder status. | §9 | Medium |
| G15 | **Payment can only be taken through End/Bill** — no "record payment" on a running session. | §10 | Medium |
| G16 | **Silent under-billing:** `SegmentBilling` does `if (q == null) continue;`, dropping an unpriceable segment from the bill with no signal. | §8, §12 | **Correctness** |
| G17 | **Game controls are read-only**; the empty state points at an editor that does not exist. | §5 | Low |
| G18 | **Supabase migrations are the pre-segment schema** and no Dart client exists. | §11 | See §4 |

## 3. Owner decisions

The 24 existing `OWNER_CONFIRMATION` items stand. This work adds:

- **OC-25 — Monday.** The brief says the centre is **closed Monday**; the shipped
  code and the previous spec said open Mon–Sun with Monday happy hours. Implemented
  per the brief (**closed Monday, happy Tue–Fri**) and made editable in
  Settings → Opening hours. **OWNER CONFIRMATION REQUIRED** if Monday really trades.
- **OC-26 — Holiday semantics.** `operatingWindow` treats a public holiday as fully
  closed, while the rate rules only say happy hour never applies then. Now an
  explicit per-holiday `closed` flag, defaulting to *open, no happy hour*.
- **OC-27 — VR / Lounge happy hour.** Still no happy rate given; both remain
  `happyHourEligible = false`.

## 4. Scope statement — offline & multi-device (brief §11)

The app is **local-first**: Drift/SQLite on the device is the source of truth, so
every session, segment, payment and booking already survives refresh, restart and a
total loss of connectivity — there is no network in the write path to fail. That
satisfies "persist durably", "survive a reload" and "continue calculating from
persisted timestamps".

It does **not** satisfy multi-device sync, because there is no server: Supabase was
never provisioned (it needs the owner's login) and the SQL in `supabase/` is a stale
pre-segment schema. Per the brief's own instruction — *"Do not claim multi-device
offline conflict resolution unless it is actually implemented and tested"* — this
work **does not** add an outbox, a sync engine or a conflict policy, and the UI says
"Local mode · saved on this device" rather than a fake Online/Offline indicator.
Wiring Supabase is tracked as remaining work in §6.

## 5. Implementation order

1. **Core rules & data** — hours (G1/G2), resource CRUD + statuses (G5, G11),
   rate/policy/holiday writes (G6), compatibility notes (G12), booking fields (G14),
   unpriced-segment surfacing (G16).
2. **Floor** — card facts (G7), quick actions (G9), responsive columns (G10),
   awaiting-payment section (G8), View Games + per-system status (G12/G13),
   record payment on a live session (G15).
3. **Bookings** — edit, notes, reminder status (G14).
4. **Reports & export** — real metrics from persisted rows, Today/Week/Month/Custom,
   `.xlsx` export (G3, G4).
5. **Settings** — stations, hours, holidays, rates, policy editors (G2, G5, G6);
   controls editor (G17).
6. **Tests** for every scenario in brief §16, then analyze + full suite.

## 6. Known remaining work after this pass

- Supabase schema regeneration + sync client + multi-device conflict policy (G18).
- Design-only modules with no data model behind them (shift open/close & cash drawer,
  checklists, issue/downtime log, void approval queue, member coins & plans).
  These appear in `design/` but are **not** in the brief's scope; they are not
  faked with placeholder numbers.

---

## 7. What was done (same day)

Every gap in §2 except G18, with the scope statement in §4 unchanged.

| Gap | Outcome |
|---|---|
| G1 | Hours corrected to **open Tue–Sun, Monday closed; happy Tue–Fri**. The two Monday happy-hour tests were rewritten to assert the closed-Monday rule, and a test asserts the calendar reports Monday closed / Tuesday open. |
| G2 | `BusinessHours` is persisted in a new `settings` table and edited in **Settings → Opening hours**. Nothing in the pricing or availability path reads a hardcoded schedule. |
| G3 | **Reports** rebuilt over persisted rows: collected / billed / pending / waived / refunded, sessions, gaming hours, customers (new vs returning), revenue by activity, by payment method, by price band, takings by day, station utilisation, most-played games and a searchable session history. Today / Week / Month / Custom. Arithmetic lives in a pure `ReportsService` with 12 tests. |
| G4 | **`.xlsx` export** (`excel` package) with six sheets, built from the same `ArenaReport` the screen shows; a test decodes the workbook and asserts the figures match. |
| G5 | **Settings → Stations**: add / edit / disable / maintenance / temporarily-unavailable, refused while a station is occupied. |
| G6 | Rate card, billing rules and holidays all have editors. `upsertRate` had a real bug — it keyed on a generated id that did not match the seeded rows, so edits silently inserted a *second* rate the pricer never reached. Fixed to replace by natural key, plus a unique index on (activity, band, controllers). |
| G7 | The occupied card now shows customer, game, controller count, start → due times and the running bill. |
| G8 | **Awaiting payment** queue on the Floor, with one-tap Collect. |
| G9 | Quick actions are always on the card; `•••` opens every in-session action. |
| G10 | One column below 540 px, two to four above; the free card was compacted to one action row. |
| G11 | `temporarilyUnavailable` added; **Reserved** is derived from the next booking. |
| G12 | `game_resources` gained `notes` + `updatedAt`; staff set per-system status with a note from the station's Games sheet. |
| G13 | `view_games_sheet` wired; `station_grid`, `today_summary_strip` and `active_session_card` deleted (unreferenced; the last one's two tests were replaced by five richer `StationCard` tests). |
| G14 | Bookings can be **edited**, carry notes, a party name/phone and a reminder status, and can be cancelled or have their reminder toggled. |
| G15 | **Record payment** on a running session — before, during or after — with append-only part-payments across methods. |
| G16 | `SegmentBilling` now reports unpriceable segments instead of dropping them, and the End screen warns that the total is short. |
| G17 | **Controls editor** built; the empty state points at a screen that exists. |

Also fixed, found by running the app rather than reading it:
- the session-actions sheet overflowed by 132 px on a phone;
- "No price is configured for this combination" appeared when the real problem was that no controller count had been picked;
- the new-session step numbers skipped hidden steps (1, 2, 4);
- the report's day axis printed `IstDate(2026-10-10)`, and a one-day range drew a meaningless full-width bar;
- the session log's range chips overflowed by 7 px;
- `ReportsService` crashed sorting the unmodifiable empty list a session with no segments falls back to.

**Verification:** `flutter analyze` clean; `flutter test` **179 passed** (from 152). Floor, new
session, walk-in start, controller change, billing, reports, session log and the owner/staff split
were exercised on an iPhone 17 Pro simulator.
