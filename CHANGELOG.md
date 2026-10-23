# Changelog

All notable changes to arena_ops (floor app, admin web and Supabase backend)
are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

One version covers the whole release: `apps/admin/package.json`,
`apps/mobile/pubspec.yaml` and the migrations in `supabase/migrations/` ship
together.

## [Unreleased]

### Changed
- Floor app Extend (single and group): pick any number of minutes (− / + in 5-min steps, a
  slider up to 4 h, or tap to type) instead of fixed +15/+30/+60. The confirmation shows the
  bill so far, the extension's price and the new total, for staff to tell the customer. The
  station card's "+30" button is now "Extend".
- Overtime, single sessions and groups: past the booked end the clock keeps running but the
  price stops at the booked time. At End, staff see how long it ran over and what that adds, and
  choose "Charge overtime" (off by default: the booked time is billed). Extending still charges
  up to the new end. End ops carry `charge_overtime`; server `_pr_session_bill`,
  `_pr_group_bill` / `_pr_sweep` (migrations `20261023154403_no_overtime_charge`,
  `20261023154904_overtime_choice`).

### Added
- Floor app End session: "Ended at" can be changed (e.g. the timer ran on) and the price
  recalculates; the "Bill amount" can be lowered (sent as a manual discount; the manual-discount
  limit applies below owner level).
- Floor app: Sync button in the Floor screen header.
- Admin Sales: "Edit" on a closed bill (Money permission) shows Start, End and the Price and
  lets you set the amount. Collected is set to match (the difference recorded as paid or given
  back), and History shows the change with any corrected times. Sync op `bill.adjust`
  (migrations `20261023151719_bill_edit` onwards).
- Local demo seed (`supabase/seed.sql`, loaded by `supabase db reset`): arena "404 Arena
  (demo)" with owner and staff logins, catalog, customers, a week of bills, running sessions
  and bookings. Logins and how to load it without a reset are in the README.

### Removed
- Billing rules removed from admin Settings and the floor app's Settings, and the Overtime
  grace field from admin Pricing. Bills use the simple defaults: per-minute, no grace period,
  no minimum charge, rounded to the nearest ₹1. The pricing code is unchanged.
- Sentry removed from the floor app for now (crash reports, breadcrumbs, Session Replay):
  `sentry_flutter` and `sentry_dart_plugin` dropped, `AO_SENTRY_*` defines are ignored. Timer
  anomalies and unexpected errors go to the debug log only. iOS builds no longer fetch
  `sentry-cocoa` from GitHub.

## [0.0.1-alpha.0] - 2026-10-21

First alpha release. For internal testing on the staging project; not for real
takings yet.

### Added

**Floor app (Flutter, staff only)**
- Sign-in with per-person logins; one local database per arena and person.
- Sessions started from a station: game, players, controllers, pricing snapshot
  captured at start. Switch system, change game and change controllers close
  the open segment and open a new one.
- Timers derived from stored timestamps; live price stops at the booked end;
  overtime grace per station type.
- Custom durations in hours and minutes; extensions.
- Billing and payments, including split and group bills, discounts
  (preset, coupon or manual) and cash rounding.
- Groups, bookings tab, members (customers) and controller (pad) tracking with
  loan, return and move history.
- Offline-first: every change is saved on the device and synced through an
  outbox; conflicts and refusals show under Sync → Needs attention.
- Staff module: own clock-in/out (server-timed) and leave applications.
- Permission-aware screens (start, bill, discount, members, stations, …).
- Flavors `dev`, `staging` and `prod`, each bound to one environment.

**Admin web (Angular)**
- Owner self-registration with e-mail confirmation and arena creation;
  self-service venue setup wizard.
- Stations, station types (priced per minute, hour or day, fractional units),
  games library with per-station availability, controllers and accessory types.
- Pricing: rates, time rules (happy hours as ordinary rules), holidays, hours,
  billing rules, overtime grace, discounts and coupons.
- Users: invite by e-mail, accept-invite flow, roles and permissions,
  deactivate.
- Sales and reports, live via private Realtime channels.
- Staff: shifts and roster, attendance corrections, leave approvals, pay setup
  and payroll with finalised, locked periods.
- Password reset; Turnstile support for sign-up and sign-in.

**Backend (Supabase)**
- Declarative schema (`supabase/schemas/`) with generated migrations.
- All writes through `sync_push` with per-op permission checks; the server
  re-prices every bill and extension and refuses any difference.
- Row Level Security on every table, scoped to arena membership and
  permission; `anon` reaches nothing.
- Private Realtime channel per arena; paged `sync_pull` with permission-aware
  filtering.
- Append-only money, audit and evidence records.
- Staff module: attendance days, shifts, leave balances and salary runs.

### Security
- No SECURITY DEFINER function in an exposed schema is client-executable;
  client API is a fixed allow-list.
- Release builds refuse local mode, non-https or development hosts, and any
  secret or `service_role` key.
- Only the publishable key ships in either app.

### Known issues
- Not yet tested on two real phones across different networks.
- Session times are device-asserted within bounds; the server cannot prove an
  end time is true.
- No automated Dart-vs-SQL pricing parity check or cross-app e2e suite: the
  old `tool/` scripts were removed and an e2e suite is planned.
- Admin web admits only owner-level logins, so a `leave_approve`-only member
  cannot approve leave anywhere yet.
- Admin initial bundle exceeds its 500 kB budget.
- Not built yet: push notifications, who's-in board, shared clock-in tablet.

[Unreleased]: https://github.com/rorrimlabs/arc-arena/compare/v0.0.1-alpha.0...HEAD
[0.0.1-alpha.0]: https://github.com/rorrimlabs/arc-arena/releases/tag/v0.0.1-alpha.0
