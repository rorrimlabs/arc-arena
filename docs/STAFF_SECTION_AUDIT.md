# Staff Section — Phase 1 Audit (read-only)

**Date:** 2026-10-04 · **Scope:** audit only, no production behaviour changed.
**Verdict:** the Staff core is **already built and well-tested**, not greenfield. Work remaining is
*finishing* (reminders, custom duration, reports/settings UI, wire-ups), *reconciling the re-skin*
(3 stale tests, PLAN nav), and a few *owner decisions* — not rebuilding.

Sources of truth read: `docs/GAMING_CENTER_PRODUCT_REQUIREMENTS.md` (PRD),
`docs/OWNER_CONFIRMATION.md`, `docs/PLAN.md`, `design/404 Arena App (offline).html`, and the full
`lib/` + `test/` + `supabase/` tree. Toolchain: Flutter 3.47.6. `flutter analyze` = clean.
`flutter test` = **99 passed / 3 failed** (the 3 failures are stale UI tests, see §D).

---

## A. Requirements already supported (built + mostly tested)

| Area | Status | Where |
|---|---|---|
| Floor overview: zoned station cards, live timers, status strip | ✅ | `features/floor/presentation/floor_screen.dart`, `widgets/station_card.dart` |
| Resource status derived from **open segments** (never typed) | ✅ | `data/local/local_session_repository.dart` (`watchOpenSegments`, `_ensureResourceFree`) |
| Timestamp-only timer (survives restart/refresh/offline); overtime/warning | ✅ tested | `domain/services/session_timer.dart`; `test/domain/services/session_timer_test.dart` |
| Game↔resource compatibility matrix (per-station playable states), editable | ✅ | `game_edit_screen.dart` (per-system dropdowns); seed overrides match PRD §4 |
| Player mode + max local players | ✅ | `game_picker_sheet.dart`, `game_edit_screen.dart` |
| New session flow (customer→activity→station→game→controllers→duration→preview→start) | ✅ | `features/new_session/presentation/new_session_screen.dart` |
| Price preview with **pricing band** shown | ✅ | `new_session_screen.dart` preview bar (`segments…band.code`) |
| Switch system (compatible+free only) / change game (playable only) / change controllers → **each a new segment** | ✅ tested | floor `sheets/*`; `local_session_repository.reconfigure`; `test/data/local/session_repository_test.dart` |
| Segments: parent + ordered segments; **one open segment per resource** + RIFT PS5⊕VR | ✅ tested | `data/local/database.dart` unique index; repo tests (`resource_busy`, RIFT block) |
| Extend +15/+30/+60 with conflict + closing-time block + exact reason | ✅ tested | `sheets/extend_sheet.dart`; `domain/services/availability_service.dart` |
| Deterministic pricing: paise, half-up, **happy-hour boundary split**, band fallback, grace/min/VR units | ✅ heavily tested | `domain/pricing/pricing_service.dart`; `test/domain/pricing/*` |
| End + **segment billing** (bill from ALL segments, cash-round once) | ✅ tested | `domain/services/segment_billing.dart`; integration test |
| Payments: cash/UPI/card/other, partial/pending/paid/waived, append-only, refund needs reason | ✅ | `sheets/end_session_sheet.dart`; `local_session_repository.recordPayment` |
| Booking: game-first availability, any/specific system, full-period conflict, RIFT | ✅ tested | `features/bookings/*`; `app/controllers/booking_actions.dart`; `domain/services/booking_availability_service.dart` |
| Check-in → session linked by `bookingId`, booking preserved as planned record | ✅ | `upcoming_bookings.dart` → `booking_actions.checkIn` |
| Session history timeline (per-segment) | ✅ | `sheets/session_history_sheet.dart`; station detail inline list |
| Game controls (PS glyph tokens) + "Controls not added yet" empty state | ✅ (read-only) | `features/games/presentation/controls_sheet.dart`, `widgets/button_glyph.dart` |
| Automatic current-day/time pricing (happy hour auto; weekend/holiday exclusion) | ✅ tested | `core/time/business_calendar.dart`; `test/domain/pricing/pricing_happy_hour_test.dart` |
| Customer directory + derived stats | ✅ | `features/customers/*` |
| Today glance + Money tab (bills/log by method) | ✅ | `features/today/*`, `features/money/*` |

## B. Design components available & reusable (use these — do not invent new UI)

- **Full 404 design system ported**: `core/theme/app_theme.dart` (M3 wiring), `arena_colors.dart`,
  `arena_palette.dart` (Ink/Lime/Amber/Red + radii), `arena_type.dart`. Tokens match the mock
  (lime `#98E748` primary on black, amber=warning, red=overtime; IBM Plex Sans/Mono + Saira, all
  bundled in `assets/fonts` + `pubspec.yaml`). Dark-first (`themeMode: dark`).
- **Shared widgets**: `arena_badge`, `arena_header`, `arena_list`, `arena_segmented`,
  `arena_bar_chart`, `arena_placeholder_page`, `section_placeholder`, status dot/labels.
- **Patterns**: themed bottom-sheets (all floor actions), dialogs, chips, cards, 56px min targets,
  tabular mono digits for timers/money. Reuse `ArenaPlaceholderPage` for any "coming soon".
- **Nav**: 5-tab bottom bar (Today·Floor·Money·Reports·More) matching the mock's top-level sections.

## C. Missing pieces (real gaps vs the brief)

| # | Gap | Brief ref | Notes |
|---|---|---|---|
| C1 | **Booking reminders / local notifications — entirely absent** | §23, acceptance "reminders work offline" | No package, no scheduling code. Needs a new dep (e.g. `flutter_local_notifications` + `timezone`) and platform permission setup. Largest functional gap. |
| C2 | **Custom duration** (choose end-time OR minutes) | §11, §12 | New session, Extend, and Booking expose only fixed presets. Domain already supports arbitrary `durationMinutes`/open-ended — UI-only gap. |
| C3 | **View Games per station is orphaned** | §8, FR-FLOOR-05 | `sheets/view_games_sheet.dart` is complete and correct but **never wired** to a screen. Small wire-up. |
| C4 | **Controls editor** | §10 empty-state hint, Settings subtitle | Controls are read-only; the empty state points to an editor that doesn't exist (dead-end). |
| C5 | **Reports tab UI** | FR-REP, §38 | All 10 reports are "This report is on the way." placeholders. (Data providers for Today/Money exist.) |
| C6 | **Owner config screens** | §26–§27, memory "rules configurable + OWNER CONFIRMATION" | Pricing/price-bands, Opening hours, Holidays, Stations, Staff are placeholders. Engine is config-driven; no editing UI. |
| C7 | **Online/Offline + "last synced" indicator** | §4 | Absent. Only a clock-drift banner exists. See decision D-ii. |
| C8 | **Supabase sync / multi-device** | §33 | No Dart client; local-only. Acknowledged in docs as deferred. |
| C9 | **Excel export** | FR-XLS (P1) | Not implemented. |
| C10 | **Dead code** | — | `active_session_card.dart`, `station_grid.dart`, `today_summary_strip.dart`, `view_games_sheet.dart` unused (cleanup / wire C3). |

## D. Exact mismatches (documentation vs implementation — not silently resolved)

- **D1 — Nav changed, docs/tests not reconciled.** PLAN.md §Phase-0 says "4 bottom tabs
  (Floor/Customers/Games/Reports)". Actual is **5 tabs (Today·Floor·Money·Reports·More)**;
  Customers ("Members") and Games live under More. The re-skin changed this; PLAN.md is stale.
- **D2 — 3 failing tests are the above regression**, not logic bugs:
  `test/app/app_shell_smoke_test.dart` (×2, asserts 4 destinations + boot-to-Floor + Customers/Games
  tabs) and `test/features/customers/customers_screen_test.dart` (navigates via old nav). All
  correctness tests (pricing/timer/availability/segments/booking/integration) pass.
- **D3 — Supabase migrations are the pre-segment legacy schema** (no `session_segments`,
  `game_resources`, `player_mode`, `max_local_players`; `sessions` still single-resource). The Drift
  schema is current. Already flagged in `PLAN.md:100-103`. Regenerate before wiring Supabase.
- **D4 — PLAN Phase-3 checklist partially inaccurate**: "Game Library CRUD" is actually done
  (`games_screen` + `game_edit_screen`); "Game Controls editor" is genuinely still missing.
- **D5 — Holiday semantics**: `business_calendar.operatingWindow` treats a public holiday as the
  centre being **fully closed** (returns null), whereas PRD §4 only states *happy hour* never applies
  on holidays. No live impact (holiday seed is empty) but it's an assumption to confirm (D-iv).

## E. Decisions required (owner / user — before Phase 2)

- **E-i — Booking reminders scope (C1):** approve adding a local-notification dependency
  (`flutter_local_notifications` + `timezone`) and the iOS/Android permission setup? Target platforms?
- **E-ii — Offline indicator (C7):** in a single-device local deployment there is no server to be
  "offline" from. Options: (a) show an honest **"Local mode · data on this device"** status now and
  light up true online/offline + "last synced" when Supabase lands; (b) defer entirely to the
  Supabase phase. Recommend (a).
- **E-iii — The 20 `OWNER_CONFIRMATION` knobs** already have safe defaults; confirm the real values
  when convenient (no redesign needed). Owner-config UI (C6) is where they'd be edited.
- **E-iv — Holiday = closed, or open-without-happy-hour? (D5)**

---

## Proposed implementation order (follows the brief's phase gates)

0. **Reconcile the re-skin (fast, unblocks CI):** update the 3 stale tests to the 5-tab nav; correct
   PLAN.md nav + Phase-3 checklist. (Tests only — no production behaviour change.)
1. **Finish Staff-core wire-ups (Phase 2 tail):** wire **View Games** per station (C3); add
   **custom duration** to new-session/extend/booking (C2); offline/local-mode status line (C7/E-ii).
2. **Booking reminders offline (Phase 3, C1):** add notification dep, schedule on create/check-in,
   cancel on cancel/check-in, de-dupe on restart.
3. **Pricing/owner-config + Reports UI (Phase 4, C5/C6):** price-bands/hours/holidays/stations
   editors over the existing config; real Reports screens over existing providers; Excel export (C9).
4. **Polish + cleanup (Phase 5):** remove/relocate dead widgets (C10); controls editor (C4);
   per-screen empty/error consistency.
5. **Later:** Supabase schema regen (D3) + sync (C8).

Per the brief: do not advance a phase while its core tests fail; after each change run
`flutter analyze` → relevant tests → report.

---

## Progress since the audit (2026-10-04)

**Step 0 — re-skin reconciled (done):**
- Fixed the 3 stale nav tests (`test/app/app_shell_smoke_test.dart`,
  `test/features/customers/customers_screen_test.dart`) to the 5-tab nav. Suite is now green.
- Corrected PLAN.md nav line + Phase-3 checklist (D1, D4).

**Step 1 — quick Staff wire-ups (done):**
- **C3 View Games per station:** wired `showViewGamesSheet` to a "Games" action on available
  station cards (station-kind only), beside "Start". `station_card.dart`, `floor_screen.dart`.
- **C2 Custom duration:** added a reusable `core/widgets/custom_duration_sheet.dart` and a "Custom"
  chip to New Session, Booking, and Extend (the pricing engine already supported arbitrary minutes).
- **C7 Offline status:** added `core/widgets/connection_status.dart` — honest "Local mode · saved on
  this device" strip on Floor + Today, structured to become Online/Offline + last-synced when
  Supabase lands (owner decision E-ii = option a).
- Tests: `test/features/floor/floor_wireups_test.dart` locks the three above. `flutter analyze` clean;
  **105 tests pass**.

**Step 1b — responsive floor fix (done, verified on iPhone 17 Pro simulator):**
- Floor grid is now **single column on phones** (`width < 520`), 2 / 3 / 4 columns on wider
  tablet / desktop (spec §36). Full-width phone cards give the actions room.
- Station-card button labels are hardened (`maxLines: 1`, ellipsis) so "Games"/"Start" never
  char-wrap. Fixes the truncated "G a …" button seen at 2-column phone width.
- Verified live: Today + Floor render cleanly, stations show Games + Start, Pool/Lounge show only
  Start, and the View Games sheet opens with player mode + max players per game.

**Step 2 — polish (done, verified on device):**
- "1 controllers" → "1 controller" (singular) in the station-detail header.
- "GAMES THIS SESSION" segment rows now show the **game name + station + controllers**
  (e.g. "GTA V" · "RIFT · 1 controller") instead of a generic "Game segment".

**Step 3 — booking reminders (C1, done):** offline, device-scheduled local notifications.
- Deps: `flutter_local_notifications` + `timezone`. Pure builder
  `domain/notifications/reminder_plan.dart` (+ `reminder_policy.dart`, default 30-min lead); platform
  wrapper `core/notifications/notification_service.dart` (real + no-op); coordinator
  `app/notifications/booking_reminders.dart`.
- Wired: `BookingActions` schedules on create, cancels on check-in/cancel; `main()` requests
  permission + reconciles on startup (`syncUpcoming` cancels-all then reschedules → **no duplicates
  after restart**). Reminder ids are a stable FNV-1a hash of the booking id (reliable cancel/dedupe).
- Platform: iOS `AppDelegate` notification-center delegate; Android manifest permissions + scheduled
  receivers + core-library desugaring.
- Tests: `test/domain/notifications/reminder_plan_test.dart` (builder/ids) +
  `test/app/booking_reminders_test.dart` (create schedules, cancel cancels, restart de-dupes).
  Verified live on iPhone 17 Pro: permission prompt shown + granted, app stable. **113 tests pass.**

**Step 4 — Today bookings + notifications + game-library reachability (done):**
- Today header gained **Bookings** (calendar) and **Notifications** (bell + lime count badge) actions;
  an **Upcoming bookings** section (list or empty-state + New) fills the home screen; new
  `NotificationsScreen` lists upcoming reminders. Reviewed by an adversarial multi-lens workflow
  (3 reviewers → verify); **8 confirmed findings all fixed**, incl. a real crash (FilledButton in
  `ListTile.trailing` → infinite-width) now rebuilt as a 404 Container card with a bounded button,
  badge recolored to lime, overflow guards, by-id customer resolution, past-reminder handling.
- **Game library reachable from the pickers (user ask):** the new-session game picker and in-session
  Change Game now show the resource **name** (not id), a **Manage** action, and an actionable empty
  state — "Add \"<search>\"" opens the add-game form prefilled, "Open game library" → `GamesScreen`.
  Shared `no_games_state.dart`. (Add/edit name, category, platform, player mode, max players, active,
  and per-station compatibility already lived in `game_edit_screen.dart`.) Verified live.
- `flutter analyze` clean; **115 tests pass** (+ Today widget tests).

**Step 5 — blank date/time picker fixed (done, verified):** on iOS 26.5 the **Impeller** renderer drew
every Material **dialog** blank (`showDatePicker`/`showTimePicker`, and by extension any AlertDialog)
while bottom sheets rendered fine — so bookings couldn't be created. No Dart exception; it's an engine
rendering bug. Fixed by falling back to **Skia** (`ios/Runner/Info.plist` → `FLTEnableImpeller=false`).
Verified live end-to-end: date picker + time picker render, a booking was created (Rahul, 8–9 PM),
the bell shows a lime **1** badge, the Upcoming-bookings card and the Notifications reminder tile
("Reminds 7:30 PM · 30m before") all render. Trade-off: Skia is the older (deprecated-but-supported)
renderer; revisit once the upstream Impeller bug is fixed. (Android unaffected — it already used its
own default.)

**Step 6 — staff/owner access control (done, verified; the design's role model):** the design is a
**PIN login with Owner/Staff roles** gated by 8 permissions (`start, bill, discount, members,
stations, money, reports, settings`); `owner = money || reports`. Implemented:
- Domain `AppUser` + `Permission`; a persisted **Users** table (Drift schema v5) seeded with **two**
  accounts — **Arjun (Owner, all)** + **Priya (Staff)**; default PINs 1111 / 2222 (placeholders).
- **App opens straight into the staff view** (no login on launch — `main()` auto-signs-in the default
  staff via `AuthController.openAs`). The PIN **login screen** (pick-a-user → 4-digit pad) is still
  there and reachable via **More → Sign out** to switch to the owner. `AuthController`, router
  `redirect` + `refreshListenable`.
- **Role-gated nav**: Owner → Today·Floor·Money·Reports·More (lands on Today); **Staff → Floor·More**
  (lands on Floor) — **Money/Reports/Today hidden**; More hides **Settings** (needs `settings`) and
  **Members** (needs `members`). Sign out → lock.
- Tests: `test/features/auth/login_test.dart` (owner PIN → Today + 5 tabs; staff → Floor + 2 tabs, no
  Money/Reports/Today). All existing widget tests start signed-in as owner via `testOverrides`.
  `flutter analyze` clean; **117 tests pass**. Verified live: login, staff view, owner view, sign out.
- Deferred (needs a backend): the design's **cloud owner account** (email/password) and
  multi-arena onboarding ("Create your arena"). Local PIN login covers the single-device staff need.

**Still open (next):** Settings → Staff editor (add/edit users + PINs from the UI); C4 controls editor, C5 reports UI,
C6 owner-config screens (incl. configurable reminder lead time), C8 sync, C9 Excel, C10 dead-code
cleanup; decisions E-iii, E-iv.
