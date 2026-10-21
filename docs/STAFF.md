# STAFF — Attendance, Leave and Salary

## Context

ArenaOS has no staff time, leave or pay features yet. The More screen's "Shift" row is a placeholder, and there is no attendance, leave or payroll data anywhere. Owners want lightweight staff management on top of the existing stack:

- geo-tagged clock in/out
- shifts
- leave with approvals
- a salary run that uses exactly the same worked-hours number the staff member sees

This is not HR or payroll compliance software: no tax, PF/ESI or statutory payslips.

**Already decided (2026-10-15):**

| Decision | Choice |
|---|---|
| Where staff clock in | Both: on their own phone, or on a registered arena tablet (kiosk with name + PIN). |
| Offline | Clock in/out needs a connection. The server stamps the time. This module's data stays out of the offline sync feed. |
| Owner-ish floor screens | Who's in, leave approvals and flagged review are gated by permission, not shown to "owners". This keeps the floor app staff-first. Pay and salary stay on admin web only. |
| Notifications | Real push now: Firebase Cloud Messaging (FCM), a device-token table and one Supabase Edge Function. **This changes the "No Edge Functions" line in CLAUDE.md.** |

**What the codebase forces (from exploration):**

- **Writes.** Every write goes `sync_push` → `_sync_apply` → `op_*` (SECURITY DEFINER, `_need(arena, perm)`). The `op_id` is the idempotency key, and ids are generated on the device. New ops plug into the `case` in `supabase/schemas/public/functions/_sync_apply.sql`.
- **Permissions.** They are a `text[]` on `staff_profiles`, validated against `_known_perms()`. `role='owner'` holds them all.
- **No per-permission filtering in sync_pull.** It sends every table in `_sync_sources()` to every active member. So **attendance, leave and pay tables must NOT join `_sync_sources()`**. The apps read them online through RLS selects and invoker RPCs, the same way `audit_log` and `arena_sales` work.
- **Settings.** Per-arena settings live in `settings(arena_id, key, json)` behind the whitelist in `op_settings_save`. Corrections go through the existing `audit_log`.
- **Holidays.** The existing `holidays` table is part of the **pricing snapshot**: changing it retires the price list. Staff holidays therefore get their own table.
- **Available pieces.** `btree_gist` is installed, so overlap exclusion constraints are possible. The server works in fixed IST +05:30.
- **Missing pieces.** There is no pg_cron, no pg_net and no push setup. Mobile has no geolocator, maps or Firebase. Admin has no map library and no PDF generator, but it does have a CSV download pattern (`apps/admin/src/app/features/sales/components/sales-csv.ts`).

---

## 1. Open questions

Each question has the default the design uses until you answer it. Confirmed answers go into `docs/OWNER_CONFIRMATION.md`.

| # | Question | Default used |
|---|---|---|
| S1 | Monthly staff day rate (used for deductions): what do we divide by? | ✅ Decided 2026-10-15: calendar days in the period. Holidays are configured per arena (staff holiday list), and work done on a holiday is counted (see S2). |
| S2 | Work on a week-off or holiday: overtime, nothing extra, or an extra day's pay? | ✅ Decided 2026-10-15: every minute worked on a holiday or week-off counts as extra hours. |
| S3 | Extra hours: how are they paid? | ✅ Decided 2026-10-15: each person has a **standard day** (arena default 8 h, per-person override). Minutes worked beyond it are **extra hours**, including on planned long days, e.g. a 12 h Sunday = 4 h extra. This applies to every pay type. Extra-hours pay is switched on per person. The rate is the person's own extra-hours rate if one is set, otherwise it is derived (monthly: salary ÷ days in period ÷ standard hours; daily: day rate ÷ standard hours; hourly: the hourly rate). It is multiplied by the arena multiplier (default 1×). "Fixed + overtime" is therefore Monthly with extra hours on, not a separate pay type. |
| S4 | Do late marks cut pay for hourly staff? They already lose the minutes. | No. Late rule applies to monthly and daily only. |
| S5 | Leave year and allowance | ✅ Decided 2026-10-15: kept simple, not HR-style. No leave types and no carry-forward. A **paid-leave allowance per year** is set per arena, with an optional per-person override, and staff see it in their profile. The leave year runs from the joining date (anniversary to anniversary). Staff apply as planned or unplanned. The approver decides how many days are **paid** (suggested: up to the balance) and how many are **LOP** (loss of pay). LOP days are deducted from salary. |
| S6 | Paid leave beyond balance | ✅ Decided 2026-10-15: not refused. The approver sees the balance and marks the excess as LOP. |
| S7 | Can someone with `leave_approve` approve their own leave? Can someone with `attendance_review` correct their own entries? | Only `role='owner'` can act on their own records. |
| S8 | Staff holidays: separate list, or reuse the pricing holiday list? | Separate list, with a "Copy from arena holidays" button. |
| S9 | Rule changes (grace, rounding, break, half-day %, deductions): do they apply to every period not yet finalised, or only from an effective date? | Time rules apply to every period not yet finalised. Pay rules and pay rates are effective-dated. Finalised runs never change. |
| S10 | Half-day and absent thresholds? | Full day at ≥ 75% of scheduled minutes, half-day at ≥ 40%, otherwise absent. |
| S11 | Weekly overtime when a week crosses the pay-period boundary? | It counts in the period that contains the week's last day. |
| S12 | Map tiles: free OpenStreetMap tiles for now, or a keyed provider (MapTiler/Stadia) from day one? | OSM now. Switch to a keyed provider before going past a handful of arenas (OSM tile policy). |
| S13 | PDF export: browser "Print → Save as PDF" from a print-styled page, or generate a real PDF file? | Print-styled page. No new dependency. |
| S14 | Forgotten clock-out: pay up to the shift end while the entry waits for review? | Yes. Auto-out at the scheduled end is counted, flagged and editable. |
| S15 | Who is tracked? Do owners clock in? | Staff are tracked. `role='owner'` is not, unless toggled. |
| S16 | Record the salary payout itself (paid on, method)? | Out of scope. "Mark paid" is optional. |
| S17 | A person working at two arenas? Today the server allows one arena per owner login (`arena_limit`). | Separate profile, pay and leave per arena. No combined payslip. Owner views are per arena, using the existing arena switcher. |
| S18 | Kiosk PIN length and lockout? | 4 digits. Lock after 5 wrong tries for 15 minutes. |
| S19 | Attendance or leave change inside a finalised period? | Refused. The owner adds an adjustment in the next run instead. |
| S20 | Salary advance recovery? | One deduction line in the chosen run. Instalments are optional, later. |
| S21 | Rounding: applied to the day's total or to each entry? | Day total, after the break. |
| S22 | Push to approvers who only use admin web (browser push)? | Optional, later. Phone push only at first. |
| S23 | Who decides salary reductions? | ✅ Decided 2026-10-15: the owner, on the month-end timesheet, per person and per deduction. The system only suggests; suggestions start as applied. |
| S24 | Salary in the staff app? | ✅ Decided 2026-10-15: none. Pay is admin-web only, for `payroll` holders. |

---

## 2. Spec (Notion-ready)

### Attendance

- **Clock in/out.** Staff clock in and out from the floor app on their own phone, or on a registered arena tablet using name + PIN.
- **Evidence saved on every punch:**
  - server time (the only time used for pay)
  - device time (evidence only)
  - GPS lat/lng
  - accuracy in metres
  - mock flag
  - location status
  - distance to the arena
  - inside / outside / unknown
  - device id (the install id already in `SyncMeta.device_id`)
  - the geofence settings used, as a snapshot
- **Location capture.** Only at the moment of the punch, foreground only. No background tracking and no background location permission.
- **Online required.** Offline → "You're offline. Clock-in needs internet so the time is recorded by the server." with the fix "Connect to Wi-Fi or mobile data and try again."
- **Geofence decision (server-side; the app shows a preview only):**
  - `inside` = distance ≤ radius **and** accuracy ≤ min accuracy
  - `outside` = distance > radius with good accuracy
  - `unknown` = no fix, accuracy too poor, or no geofence set
  - The outside rule applies to both `outside` and `unknown`:
    - **block** refuses the punch
    - **flag** allows it and queues it for review
    - **allow** allows it and only shows a badge
  - Mock location has its own rule. Default: block.
- **Kiosk tablet.** A tablet registered as an arena device skips GPS. Its punches are marked `arena_device`, which counts as inside. The PIN is checked on the server and locks after repeated wrong tries.
- **Log.** Each entry shows in → out, a map pin for each punch, an inside/outside badge and flags.

**Attendance edge cases:**

| Case | Behaviour |
|---|---|
| Double clock-in | Refused: `already_clocked_in`. Only one open entry per person (unique partial index). |
| Clock-out with nothing open | Refused: `not_clocked_in`. |
| Forgot to clock out | After the scheduled shift end + `auto_out_after_min`, the entry counts as closed at the shift end. It is flagged `auto_out` and goes to review. Fallback order: arena closing time that day, then in + `max_open_hours`. Applied lazily, with no cron: on that person's next punch, when a reviewer opens the review list, when a salary draft is built, and in every read RPC. |
| Split shifts | Any number of entries per day. Entries may not overlap (gist exclusion). A gap between entries at least as long as the shift break counts as the break, so no extra deduction. |
| Crosses midnight | A shift counts from its start to its end on the day it starts (end ≤ start ends the next day). An entry belongs to the shift it falls in (`work_date` = that shift's start day, `_att_work_date`): a clock-in at 02:00 during a 22:00–06:00 shift counts on the night it started, and up to 2 hours early counts for the coming shift. With no shift around it, the IST date of the clock-in. |
| Location denied or GPS off | Punch goes through as `unknown` with status `denied`, `gps_off`, `timeout` or `unavailable`, then the outside rule applies. Under block, staff see a fix such as "Allow location for ArenaOS in Settings" or "Turn on location". |
| Mock location | Android `isMocked` is reliable. iOS 15+ reports simulated locations where the OS exposes it, otherwise `null`, treated as not detected. The mock rule applies. |
| Low accuracy | Accuracy above the minimum → `unknown` → outside rule. The app retries for up to 15 s to get a better fix before sending. |
| Corrections | Need `attendance_review` and a reason. The original row becomes `superseded` (or `voided`). A new row points to it with `replaces_id`, and `audit_log` gets before/after. Reviewers can add a missing entry with a reason. Nothing is deleted. |
| Clocked in on a leave day | Allowed. Flagged `worked_on_leave` for review. The leave stays as it is. |
| Finalised period | Entries dated inside a finalised run can't be edited (`period_finalised`). |

### Shifts and working hours

- **Shifts.** Per arena: name, start and end (minutes after IST midnight; end ≤ start means it crosses midnight), days of the week, and an unpaid break in minutes.
- **Assignments.** Each staff member gets shift assignments with effective dates. A person can hold two shifts, which gives a split shift. A day with no assigned shift is a **week off**.
- **Staff holidays.** A per-arena list. Each holiday is paid by default.
- **Worked minutes for a day.** Add up the clocked minutes, take off the break if one applies, then round. One SQL function computes this, and both the screens and the salary run use it, so the numbers can't drift apart.
- **Standard day and extra hours.** Each person has a standard day (arena default 480 min, per-person override). On a working day, minutes beyond it are **extra hours**. Shifts can be longer on some days: a 12 h Sunday shift against an 8 h standard day gives 4 h extra. Every minute worked on a holiday or week-off is extra.
- **Daily status:** Present, Late, Half-day, Absent, On leave (full or ½), Holiday, Week off. "Worked" is added when someone works on a holiday or week-off. Today and future days show as provisional or scheduled.

### Leave

Kept deliberately simple: no leave types, no carry-forward, no HR-style policies.

- **Allowance.** One number: paid-leave days per year. It is set per arena (default 12), with an optional per-person override. Staff see it in their profile together with used days, balance and their current leave year.
- **Leave year.** Runs from the joining date: anniversary to the day before the next anniversary. The balance resets at each anniversary; unused days don't carry over. If the joining date isn't set, the profile's creation date is used.
- **Applying.** Staff give a date range, a half-day option (single-day requests only: first or second half), **planned / unplanned**, and a reason.
  - The server counts the days, skipping week-offs and staff holidays.
  - Planned leave must start today or later.
  - Unplanned leave (sick, emergency) may be backdated up to `unplanned_backdate_days` (default 7).
- **Deciding.** Anyone with `leave_approve` approves or rejects with an optional note.
  - On approval they set **paid days** and **LOP days**. The app suggests paid = min(days, balance) and the rest as LOP; the approver can change the split.
  - Paid days fill the earliest dates first.
  - A request that crosses the anniversary uses each year's balance for its own days.
- **Balance** = allowance + adjustments − paid days approved in the current leave year. Available = balance − days in pending requests.
- **Notifications.** A push goes to approvers on a new request and to the staff member on the decision.
- **Cancelling.** Staff can cancel a pending request. Cancelling an approved request becomes `cancel_pending` and needs approval again. Both are refused once the dates sit in a finalised period.
- **Effect.** Approved leave shows on the attendance calendar and feeds the salary run:
  - paid days: no deduction for monthly staff; paid at the day rate for daily staff; paid as standard-day hours for hourly staff
  - LOP days: a one-day deduction is *suggested* for monthly staff; not paid for daily or hourly staff
  - an absence with no approved leave is **Absent**, with a deduction suggested under the absent rule
  - the owner keeps or waives every suggested deduction on the month-end timesheet
- **Overlaps.** Overlapping requests from the same person are refused. Overlaps with team members are shown to the approver as information only.

### Salary

- **Pay types** (per staff member, effective-dated):
  - Fixed monthly
  - Daily
  - Hourly
- **Extra hours** (any pay type, per person, effective-dated with the rate):
  - Pay for extra hours is on or off.
  - An optional extra-hours rate. Without one, the rate is derived from the pay (see S3).
  - The arena multiplier applies on top.
  - "Fixed + overtime" = Fixed monthly with extra hours on.
- **Pay rule history.** Arena pay rules are effective-dated. A rate or rule effective date must fall after the last finalised period's end.
- **Pay period.** Monthly with a cycle start day (1–28), weekly with a start weekday, or custom (dates picked per run). Runs may not overlap.
- **Run lifecycle:** Draft → owner reviews the timesheet → Finalised (locked), or Draft → Discarded.
  - **Month-end timesheet first.** A new draft opens on the timesheet: one row per person with days by status, worked hours, extra hours, paid leave, LOP, lates and flags. Each person's day-by-day entries are one click away.
  - **The owner decides every reduction.** The system *suggests* each deduction (absent, LOP, half-day, late rule), but none is final until the owner decides. For each person and each deduction he keeps it or waives it, with an optional note. Suggestions start as applied. His decisions are stored separately, so they survive Recalculate.
  - A draft can be recalculated any time; its lines are rebuilt from live data plus the owner's decisions.
  - Finalising freezes the lines, the decisions and the rules snapshot.
  - Manual adjustments (bonus, advance, deduction) need a note and are append-only. A mistake is undone with a reversal row.
- **Breakdown per person:**
  - days by status (incl. paid leave and LOP), worked hours, extra hours
  - the rate(s) used, including mid-period changes
  - each suggested deduction with its formula, and whether it was applied or waived (with the note)
  - each adjustment
  - gross and net
- **Exports.** CSV for the timesheet, the period summary and the per-person breakdown. PDF via a print-styled page.
- **Who sees it.** Only `payroll` / `payroll_finalise` holders, on admin web. **The staff app shows no pay data at all:** no rates, no salary, no payslips. This replaces the brief's "staff see their own salary". Staff see their own attendance, hours and leave only.

### Permissions (new codes in `_known_perms()`)

| Code | Grants | Who may grant it |
|---|---|---|
| `attendance_review` | See everyone's attendance, the who's-in board and flagged entries; correct, void and add entries; accept flags. | `settings` holder |
| `leave_approve` | See all leave; approve, reject or cancel; adjust balances. | `settings` holder |
| `payroll` | Pay setup, pay rules, salary drafts, adjustments, seeing all salary. | Owner only, like `money` |
| `payroll_finalise` | Finalise or discard a run. | Owner only |

- Clocking in, seeing your own records and applying for leave need **no permission**: any active member with `tracks_attendance`.
- Shifts, holidays, the arena leave allowance and attendance settings use the existing `settings` permission. Per-person allowance and standard-day overrides use `payroll`.
- Rule S7 applies: you can't approve or correct your own records unless you are the owner.

---

## 3. Data model (declarative schema, one object per file)

**Common rules for every file below:**

- Each file follows the repo footer: `grant … to postgres, service_role;`, `revoke all … from anon;`, `revoke all … from authenticated;`, then `grant select … to authenticated` only where a select policy exists.
- No insert, update or delete policies. All writes go through `op_*`.
- Not in `_sync_sources()`, so no `sync_xid`, `sync_stamp` or tombstone triggers.
- Mutable tables get `updated_at` with `set_updated_at`.
- Every FK gets an index.
- Comments follow the repo header format and are trimmed here.

### Helpers

```sql
-- private/functions/app_my_staff_ids.sql — staff_profiles ids of the caller (active only)
create or replace function private.app_my_staff_ids()
  returns setof uuid language sql stable security definer set search_path to ''
as $$ select id from public.staff_profiles where user_id = (select auth.uid()) and active $$;
revoke all on function private.app_my_staff_ids() from public, anon;
grant execute on function private.app_my_staff_ids() to authenticated;  -- private schema, same as app_arena_ids_with

-- public/functions/_geo_distance_m.sql — haversine metres, server-only
create or replace function public._geo_distance_m(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
  returns integer language sql immutable set search_path to 'public'
as $$ select round(2 * 6371008.8 * asin(sqrt(
         power(sin(radians(lat2 - lat1) / 2), 2)
       + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::int $$;
revoke all on function public._geo_distance_m(float8,float8,float8,float8) from public, anon, authenticated;
```

`_known_perms()` gains `attendance_review`, `leave_approve`, `payroll`, `payroll_finalise`. The places that spell out the owner list (`_create_arena_with_owner`, `bootstrap_owner`) get the same update. `op_settings_save` whitelists two new keys, `attendance` and `leave_rules`, validated by `_attendance_settings(jsonb)` and `_leave_rules(jsonb)`.

### HR profile

```sql
create table "public"."staff_hr_profiles" (
  "staff_id"          uuid not null,
  "arena_id"          uuid not null,
  "joined_on"         date,
  "left_on"           date,
  "tracks_attendance" boolean not null default true,
  "employee_code"     text,
  "paid_leave_days"   numeric(4,1),                   -- per leave year; null = arena default (settings.leave_rules)
  "standard_day_min"  integer,                        -- null = arena default (settings.attendance.hours)
  "created_at"        timestamptz not null default now(),
  "updated_at"        timestamptz not null default now(),
  constraint "staff_hr_profiles_pkey" primary key (staff_id),
  constraint "staff_hr_profiles_staff_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "staff_hr_profiles_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_hr_profiles_dates_check" check (left_on is null or joined_on is null or left_on >= joined_on),
  constraint "staff_hr_profiles_leave_check" check (paid_leave_days is null or paid_leave_days between 0 and 366),
  constraint "staff_hr_profiles_std_day_check" check (standard_day_min is null or standard_day_min between 60 and 1440)
);
create index ix_staff_hr_profiles_arena on public.staff_hr_profiles (arena_id);
create trigger t_same_arena before insert or update on public.staff_hr_profiles
  for each row execute function public._assert_same_arena('staff_id', 'staff_profiles');
alter table public.staff_hr_profiles enable row level security;
create policy "p_sel_staff_hr" on public.staff_hr_profiles for select to authenticated using (
  arena_id in (select private.app_arena_ids_with(array['attendance_review','leave_approve','payroll']))
  or staff_id in (select private.app_my_staff_ids()));
```

### Attendance

```sql
create table "public"."attendance_devices" (          -- registered kiosk tablets
  "id"            uuid not null default gen_random_uuid(),
  "arena_id"      uuid not null,
  "device_id"     text not null,                      -- SyncMeta.device_id of the tablet install
  "bound_user_id" uuid not null,                      -- the login signed in on that tablet
  "label"         text not null,
  "active"        boolean not null default true,
  "created_by"    uuid not null,
  "created_at"    timestamptz not null default now(),
  "updated_at"    timestamptz not null default now(),
  constraint "attendance_devices_pkey" primary key (id),
  constraint "attendance_devices_arena_device_key" unique (arena_id, device_id),
  constraint "attendance_devices_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "attendance_devices_bound_user_fkey" foreign key (bound_user_id) references auth.users(id),
  constraint "attendance_devices_created_by_fkey" foreign key (created_by) references auth.users(id)
);
create index ix_attendance_devices_bound_user on public.attendance_devices (bound_user_id);
create index ix_attendance_devices_created_by on public.attendance_devices (created_by);
alter table public.attendance_devices enable row level security;
create policy "p_sel_attendance_devices" on public.attendance_devices for select to authenticated
  using (arena_id in (select private.app_arena_ids()));   -- the app needs "am I a kiosk?"

create table "public"."attendance_pins" (             -- kiosk PINs; NO client select
  "staff_id"     uuid not null,
  "arena_id"     uuid not null,
  "pin_hash"     text not null,                        -- crypt(pin, gen_salt('bf'))
  "failed_count" integer not null default 0,
  "locked_until" timestamptz,
  "updated_at"   timestamptz not null default now(),
  constraint "attendance_pins_pkey" primary key (staff_id),
  constraint "attendance_pins_staff_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "attendance_pins_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade
);
create index ix_attendance_pins_arena on public.attendance_pins (arena_id);
alter table public.attendance_pins enable row level security;   -- no policy, no grant to authenticated

create table "public"."attendance_punches" (          -- immutable evidence, one per clock action
  "id"                uuid not null,                  -- device-generated
  "arena_id"          uuid not null,
  "staff_id"          uuid not null,
  "kind"              text not null,
  "server_at"         timestamptz not null default statement_timestamp(),
  "device_at"         timestamptz,                    -- evidence only
  "via"               text not null default 'own_device',
  "device_id"         text not null,
  "lat"               double precision,
  "lng"               double precision,
  "accuracy_m"        numeric(7,1),
  "is_mocked"         boolean,
  "location_status"   text not null,
  "distance_m"        integer,
  "geofence"          text not null,
  "geofence_snapshot" jsonb not null,                 -- {lat,lng,radius_m,min_accuracy_m,outside_rule,mock_rule}
  "flags"             text[] not null default '{}',
  "created_by"        uuid not null,                  -- pushing login (kiosk login for kiosk punches)
  constraint "attendance_punches_pkey" primary key (id),
  constraint "attendance_punches_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "attendance_punches_staff_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "attendance_punches_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "attendance_punches_kind_check" check (kind in ('in','out')),
  constraint "attendance_punches_via_check" check (via in ('own_device','kiosk')),
  constraint "attendance_punches_loc_check" check (location_status in ('ok','denied','gps_off','timeout','unavailable','arena_device')),
  constraint "attendance_punches_geofence_check" check (geofence in ('inside','outside','unknown','arena_device')),
  constraint "attendance_punches_latlng_check" check ((lat is null) = (lng is null)
     and (lat is null or (lat between -90 and 90 and lng between -180 and 180)))
);
create index ix_attendance_punches_staff on public.attendance_punches (staff_id, server_at);
create index ix_attendance_punches_arena_time on public.attendance_punches (arena_id, server_at);
create index ix_attendance_punches_created_by on public.attendance_punches (created_by);
create trigger t_same_arena before insert on public.attendance_punches
  for each row execute function public._assert_same_arena('staff_id', 'staff_profiles');
alter table public.attendance_punches enable row level security;
create policy "p_sel_attendance_punches" on public.attendance_punches for select to authenticated using (
  arena_id in (select private.app_arena_ids_with(array['attendance_review','payroll']))
  or staff_id in (select private.app_my_staff_ids()));

create table "public"."attendance_entries" (          -- one work interval; corrections supersede, never edit history
  "id"            uuid not null default gen_random_uuid(),
  "arena_id"      uuid not null,
  "staff_id"      uuid not null,
  "work_date"     date not null,                      -- IST date of in_at
  "in_at"         timestamptz not null,
  "out_at"        timestamptz,
  "in_punch_id"   uuid,
  "out_punch_id"  uuid,
  "source"        text not null default 'punch',      -- punch | manual
  "out_source"    text,                               -- punch | auto | manual
  "status"        text not null default 'active',     -- active | superseded | voided
  "replaces_id"   uuid,
  "flags"         text[] not null default '{}',       -- outside_in, outside_out, unknown_in, mock, auto_out, worked_on_leave, manual…
  "review"        text not null default 'none',       -- none | pending | accepted | corrected
  "review_note"   text,
  "reviewed_by"   uuid,
  "reviewed_at"   timestamptz,
  "reason"        text,                               -- required on manual/correction rows
  "created_by"    uuid not null,
  "created_at"    timestamptz not null default now(),
  "updated_at"    timestamptz not null default now(),
  constraint "attendance_entries_pkey" primary key (id),
  constraint "attendance_entries_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "attendance_entries_staff_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "attendance_entries_in_punch_fkey" foreign key (in_punch_id) references public.attendance_punches(id),
  constraint "attendance_entries_out_punch_fkey" foreign key (out_punch_id) references public.attendance_punches(id),
  constraint "attendance_entries_replaces_fkey" foreign key (replaces_id) references public.attendance_entries(id),
  constraint "attendance_entries_reviewed_by_fkey" foreign key (reviewed_by) references auth.users(id),
  constraint "attendance_entries_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "attendance_entries_order_check" check (out_at is null or out_at > in_at),
  constraint "attendance_entries_source_check" check (source in ('punch','manual')),
  constraint "attendance_entries_out_source_check" check ((out_at is null) = (out_source is null)
     and (out_source is null or out_source in ('punch','auto','manual'))),
  constraint "attendance_entries_status_check" check (status in ('active','superseded','voided')),
  constraint "attendance_entries_review_check" check (review in ('none','pending','accepted','corrected')),
  constraint "attendance_entries_reason_check" check (source = 'punch' and replaces_id is null or reason is not null),
  -- No two active intervals for one person overlap (split shifts are separate rows).
  constraint "attendance_entries_no_overlap" exclude using gist (
     staff_id with =, tstzrange(in_at, coalesce(out_at, 'infinity'::timestamptz)) with &&)
     where (status = 'active')
);
create unique index ux_attendance_entries_open on public.attendance_entries (staff_id)
  where out_at is null and status = 'active';
create index ix_attendance_entries_day on public.attendance_entries (arena_id, work_date);
create index ix_attendance_entries_staff_day on public.attendance_entries (staff_id, work_date);
create index ix_attendance_entries_review on public.attendance_entries (arena_id) where review = 'pending';
create index ix_attendance_entries_in_punch on public.attendance_entries (in_punch_id);
create index ix_attendance_entries_out_punch on public.attendance_entries (out_punch_id);
create index ix_attendance_entries_replaces on public.attendance_entries (replaces_id);
create index ix_attendance_entries_reviewed_by on public.attendance_entries (reviewed_by);
create index ix_attendance_entries_created_by on public.attendance_entries (created_by);
create trigger t_attendance_entries_updated before update on public.attendance_entries
  for each row execute function public.set_updated_at();
create trigger t_same_arena before insert or update on public.attendance_entries
  for each row execute function public._assert_same_arena('staff_id', 'staff_profiles');
alter table public.attendance_entries enable row level security;
create policy "p_sel_attendance_entries" on public.attendance_entries for select to authenticated using (
  arena_id in (select private.app_arena_ids_with(array['attendance_review','payroll']))
  or staff_id in (select private.app_my_staff_ids()));
```

### Shifts and holidays

```sql
create table "public"."shifts" (
  "id"         uuid not null default gen_random_uuid(),
  "arena_id"   uuid not null,
  "name"       text not null,
  "start_min"  integer not null,                     -- minutes after IST midnight
  "end_min"    integer not null,                     -- <= start_min means it ends next day
  "days"       smallint[] not null,                  -- ISO weekday 1=Mon … 7=Sun
  "break_min"  integer not null default 0,
  "active"     boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint "shifts_pkey" primary key (id),
  constraint "shifts_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "shifts_minutes_check" check (start_min between 0 and 1439 and end_min between 0 and 1439 and end_min <> start_min),
  constraint "shifts_days_check" check (days <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(days) > 0),
  constraint "shifts_break_check" check (break_min >= 0 and break_min < 720)
);
create index ix_shifts_arena on public.shifts (arena_id);
-- policy: arena_id in app_arena_ids()  (every member may see the roster)

create table "public"."staff_shifts" (
  "id"             uuid not null default gen_random_uuid(),
  "arena_id"       uuid not null,
  "staff_id"       uuid not null,
  "shift_id"       uuid not null,
  "effective_from" date not null,
  "effective_to"   date,                             -- inclusive; null = open-ended
  "created_at"     timestamptz not null default now(),
  "updated_at"     timestamptz not null default now(),
  constraint "staff_shifts_pkey" primary key (id),
  constraint "staff_shifts_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_shifts_staff_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "staff_shifts_shift_fkey" foreign key (shift_id) references public.shifts(id),
  constraint "staff_shifts_range_check" check (effective_to is null or effective_to >= effective_from),
  constraint "staff_shifts_no_overlap" exclude using gist (
     staff_id with =, shift_id with =, daterange(effective_from, effective_to, '[]') with &&)
);
create index ix_staff_shifts_staff on public.staff_shifts (staff_id);
create index ix_staff_shifts_shift on public.staff_shifts (shift_id);
create index ix_staff_shifts_arena on public.staff_shifts (arena_id);
-- t_same_arena on staff_id and shift_id; policy: app_arena_ids()

create table "public"."staff_holidays" (
  "id"         uuid not null default gen_random_uuid(),
  "arena_id"   uuid not null,
  "day"        date not null,
  "name"       text not null,
  "paid"       boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint "staff_holidays_pkey" primary key (id),
  constraint "staff_holidays_arena_day_key" unique (arena_id, day),
  constraint "staff_holidays_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade
);
-- policy: app_arena_ids()
```

### Leave

No leave types table: the allowance is one number (`settings.leave_rules.paid_leave_days`, overridden by `staff_hr_profiles.paid_leave_days`), and the paid/LOP split is decided per request.

```sql
create table "public"."leave_requests" (
  "id"             uuid not null,                     -- device-generated
  "arena_id"       uuid not null,
  "staff_id"       uuid not null,
  "kind"           text not null,                     -- planned | unplanned
  "from_date"      date not null,
  "to_date"        date not null,
  "half_day"       text not null default 'none',      -- none | first_half | second_half
  "days"           numeric(4,1) not null,             -- server-counted, excludes week-offs/holidays
  "paid_days"      numeric(4,1),                      -- set by the approver; null until approved
  "lop_days"       numeric(4,1),                      -- days − paid_days
  "reason"         text not null,
  "status"         text not null default 'pending',   -- pending | approved | rejected | cancelled | cancel_pending
  "decided_by"     uuid,
  "decided_at"     timestamptz,
  "decision_note"  text,
  "cancel_reason"  text,
  "created_by"     uuid not null,
  "created_at"     timestamptz not null default now(),
  "updated_at"     timestamptz not null default now(),
  constraint "leave_requests_pkey" primary key (id),
  constraint "leave_requests_arena_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "leave_requests_staff_fkey" foreign key (staff_id) references public.staff_profiles(id) on delete cascade,
  constraint "leave_requests_decided_by_fkey" foreign key (decided_by) references auth.users(id),
  constraint "leave_requests_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "leave_requests_kind_check" check (kind in ('planned','unplanned')),
  constraint "leave_requests_range_check" check (to_date >= from_date),
  constraint "leave_requests_half_check" check (half_day in ('none','first_half','second_half')
     and (half_day = 'none' or from_date = to_date)),
  constraint "leave_requests_status_check" check (status in ('pending','approved','rejected','cancelled','cancel_pending')),
  constraint "leave_requests_days_check" check (days > 0),
  -- An approved request (or one awaiting cancellation) carries its paid/LOP split; others carry none.
  constraint "leave_requests_split_check" check (
     case when status in ('approved','cancel_pending')
          then paid_days >= 0 and lop_days >= 0 and paid_days + lop_days = days
          else paid_days is null and lop_days is null end)
);
create index ix_leave_requests_staff on public.leave_requests (staff_id, from_date);
create index ix_leave_requests_arena_status on public.leave_requests (arena_id, status);
create index ix_leave_requests_decided_by on public.leave_requests (decided_by);
create index ix_leave_requests_created_by on public.leave_requests (created_by);
-- t_same_arena on staff_id; history of status changes and splits goes to audit_log
create policy "p_sel_leave_requests" on public.leave_requests for select to authenticated using (
  arena_id in (select private.app_arena_ids_with(array['leave_approve','attendance_review','payroll']))
  or staff_id in (select private.app_my_staff_ids()));

create table "public"."leave_adjustments" (            -- append-only opening balances / manual corrections
  "id"            uuid not null default gen_random_uuid(),
  "arena_id"      uuid not null,
  "staff_id"      uuid not null,
  "year_start"    date not null,                      -- the joining anniversary that starts the leave year
  "days"          numeric(4,1) not null,              -- signed
  "reason"        text not null,
  "created_by"    uuid not null,
  "created_at"    timestamptz not null default now(),
  constraint "leave_adjustments_pkey" primary key (id),
  constraint "leave_adjustments_days_check" check (days <> 0)
  -- FKs (arena, staff, created_by) + indexes as above
);
-- policy: same as leave_requests
```

### Pay

```sql
create table "public"."staff_pay_rates" (             -- append-only, effective-dated
  "id"              uuid not null default gen_random_uuid(),
  "arena_id"        uuid not null,
  "staff_id"        uuid not null,
  "effective_from"  date not null,
  "pay_type"           text not null,                 -- monthly | daily | hourly
  "base_paise"         bigint not null,               -- per month / day / hour
  "extra_hours_paid"   boolean not null default false,
  "extra_hourly_paise" bigint,                        -- optional; null = derived from base (S3)
  "note"               text,
  "created_by"         uuid not null,
  "created_at"         timestamptz not null default now(),
  constraint "staff_pay_rates_pkey" primary key (id),
  constraint "staff_pay_rates_staff_from_key" unique (staff_id, effective_from),
  constraint "staff_pay_rates_type_check" check (pay_type in ('monthly','daily','hourly')),
  constraint "staff_pay_rates_amount_check" check (base_paise >= 0
     and (extra_hourly_paise is null or extra_hourly_paise >= 0)),
  constraint "staff_pay_rates_extra_check" check (extra_hours_paid or extra_hourly_paise is null)
  -- FKs + indexes
);
-- Pay is never visible to staff: payroll holders only, no "own rows" clause.
create policy "p_sel_staff_pay_rates" on public.staff_pay_rates for select to authenticated using (
  arena_id in (select private.app_arena_ids_with(array['payroll'])));

create table "public"."pay_policies" (                -- append-only, effective-dated arena pay rules
  "id"             uuid not null default gen_random_uuid(),
  "arena_id"       uuid not null,
  "effective_from" date not null,
  "policy"         jsonb not null,                    -- validated by _pay_policy(jsonb); shape in §5
  "created_by"     uuid not null,
  "created_at"     timestamptz not null default now(),
  constraint "pay_policies_pkey" primary key (id),
  constraint "pay_policies_arena_from_key" unique (arena_id, effective_from)
);
-- policy: app_arena_ids_with(['payroll'])

create table "public"."salary_runs" (
  "id"                 uuid not null,                 -- device/admin-generated
  "arena_id"           uuid not null,
  "period_start"       date not null,
  "period_end"         date not null,                 -- inclusive
  "status"             text not null default 'draft', -- draft | finalised | discarded
  "rules_snapshot"     jsonb not null,                -- {attendance:{…}, pay:{…}} used for this computation
  "computed_at"        timestamptz not null,
  "gross_paise"        bigint not null default 0,
  "deductions_paise"   bigint not null default 0,
  "adjustments_paise"  bigint not null default 0,
  "net_paise"          bigint not null default 0,
  "created_by"         uuid not null,
  "created_at"         timestamptz not null default now(),
  "finalised_by"       uuid,
  "finalised_at"       timestamptz,
  "updated_at"         timestamptz not null default now(),
  constraint "salary_runs_pkey" primary key (id),
  constraint "salary_runs_period_check" check (period_end >= period_start),
  constraint "salary_runs_status_check" check (status in ('draft','finalised','discarded')),
  constraint "salary_runs_final_check" check ((status = 'finalised') = (finalised_at is not null)),
  constraint "salary_runs_no_overlap" exclude using gist (
     arena_id with =, daterange(period_start, period_end, '[]') with &&) where (status <> 'discarded')
);
-- policy: app_arena_ids_with(['payroll','payroll_finalise'])

create table "public"."salary_run_lines" (            -- rebuilt while draft, frozen at finalise
  "id"                uuid not null default gen_random_uuid(),
  "arena_id"          uuid not null,
  "run_id"            uuid not null,
  "staff_id"          uuid not null,
  "pay_type"          text not null,
  "rates"             jsonb not null,                -- rate rows used, incl. mid-period changes
  "day_counts"        jsonb not null,                -- {present, late, half, absent, paid_leave, lop_leave, holiday, week_off}
  "worked_min"        integer not null,
  "regular_min"       integer not null,
  "ot_min"            integer not null,
  "base_paise"        bigint not null,
  "ot_paise"          bigint not null,
  "deductions"        jsonb not null,                -- [{code, label, units, rate_paise, amount_paise, applied, note}]
                                                     --   amount = suggestion; only applied ones count
  "deductions_paise"  bigint not null,
  "adjustments_paise" bigint not null,
  "net_paise"         bigint not null,
  "days"              jsonb not null,                -- per-day facts (status, worked, ot, flags) for the breakdown
  constraint "salary_run_lines_pkey" primary key (id),
  constraint "salary_run_lines_run_staff_key" unique (run_id, staff_id),
  constraint "salary_run_lines_run_fkey" foreign key (run_id) references public.salary_runs(id) on delete cascade
  -- + arena, staff FKs and indexes
);
create policy "p_sel_salary_run_lines" on public.salary_run_lines for select to authenticated using (
  arena_id in (select private.app_arena_ids_with(array['payroll','payroll_finalise'])));

create table "public"."salary_deduction_decisions" (  -- the owner's keep/waive per suggested deduction
  "id"          uuid not null default gen_random_uuid(),
  "arena_id"    uuid not null,
  "run_id"      uuid not null,
  "staff_id"    uuid not null,
  "code"        text not null,                         -- absent | lop_leave | half_day | late
  "applied"     boolean not null,
  "note"        text,
  "decided_by"  uuid not null,
  "decided_at"  timestamptz not null default now(),
  constraint "salary_deduction_decisions_pkey" primary key (id),
  constraint "salary_deduction_decisions_key" unique (run_id, staff_id, code),
  constraint "salary_deduction_decisions_code_check" check (code in ('absent','lop_leave','half_day','late')),
  constraint "salary_deduction_decisions_run_fkey" foreign key (run_id) references public.salary_runs(id) on delete cascade
  -- + arena, staff, decided_by FKs and indexes
);
-- Changed only while the run is a draft (op checks); each change also goes to audit_log.
-- No row = the suggestion applies. policy: payroll / payroll_finalise only.

create table "public"."salary_adjustments" (          -- append-only; undo = reversal row
  "id"           uuid not null,
  "arena_id"     uuid not null,
  "run_id"       uuid not null,
  "staff_id"     uuid not null,
  "kind"         text not null,                       -- bonus | advance | deduction | reversal
  "amount_paise" bigint not null,                     -- signed: bonus > 0; advance/deduction < 0
  "note"         text not null,
  "reverses_id"  uuid,
  "created_by"   uuid not null,
  "created_at"   timestamptz not null default now(),
  constraint "salary_adjustments_pkey" primary key (id),
  constraint "salary_adjustments_kind_check" check (kind in ('bonus','advance','deduction','reversal')),
  constraint "salary_adjustments_sign_check" check (amount_paise <> 0
     and (kind <> 'bonus' or amount_paise > 0)
     and (kind not in ('advance','deduction') or amount_paise < 0)
     and ((kind = 'reversal') = (reverses_id is not null))),
  constraint "salary_adjustments_reverses_key" unique (reverses_id)
);
-- policy: payroll / payroll_finalise only
```

### Push

```sql
create table "public"."push_devices" (
  "id"         uuid not null default gen_random_uuid(),
  "arena_id"   uuid not null,
  "user_id"    uuid not null,
  "device_id"  text not null,
  "fcm_token"  text not null,
  "platform"   text not null,                         -- android | ios
  "updated_at" timestamptz not null default now(),
  constraint "push_devices_pkey" primary key (id),
  constraint "push_devices_key" unique (arena_id, user_id, device_id),
  constraint "push_devices_platform_check" check (platform in ('android','ios'))
);
create policy "p_sel_push_devices" on public.push_devices for select to authenticated
  using (user_id = (select auth.uid()));

create table "public"."push_outbox" (                 -- written by op_* only; no client access at all
  "id"         bigint generated always as identity,
  "arena_id"   uuid not null,
  "user_id"    uuid not null,
  "kind"       text not null,                         -- leave.requested | leave.decided | attendance.flagged
  "title"      text not null,
  "body"       text not null,                         -- no pay amounts, ever
  "data"       jsonb not null default '{}',           -- {route, id}
  "created_at" timestamptz not null default now(),
  "sent_at"    timestamptz,
  "attempts"   integer not null default 0,
  "last_error" text,
  constraint "push_outbox_pkey" primary key (id)
);
-- after-insert trigger → net.http_post(<push-send function URL>, secret header).
-- URL and secret come from Vault (data set per environment, not schema). Requires pg_net.
```

### Client API

Each item below is a definer body in `private/functions/` plus a same-signature invoker wrapper in `public/functions/`.

- **Ops in `_sync_apply`:**
  - attendance: `attendance.punch`, `attendance.correct`, `attendance.review`, `attendance.device_register`, `attendance.device_retire`, `attendance.pin_set`
  - shifts and holidays: `shift.upsert`, `shift.assign`, `staff_holiday.upsert`, `staff_holiday.delete`
  - leave: `leave.request`, `leave.cancel`, `leave.decide` (approve with `paid_days`/`lop_days`, or reject), `leave.adjust`
  - pay: `hr_profile.save`, `pay_rate.add`, `pay_policy.add`
  - salary runs: `salary_run.create`, `salary_run.recalculate`, `salary_run.set_deduction`, `salary_run.finalise`, `salary_run.discard`, `salary_adjustment.add`, `salary_adjustment.reverse`
  - push: `push.register`, `push.unregister`
- **Read RPCs (computed):**
  - `attendance_days(arena, staff?, from, to)`: per-day facts, from the one calculation function
  - `whos_in(arena)`
  - `leave_balances(arena, staff?)`: allowance, used, pending, balance and current leave-year dates per person
  - `attendance_review_queue(arena)`: also closes stale entries
- **Server-only calculation functions:** `_att_close_stale`, `_att_day_facts`, `_leave_year(staff, d)` (anniversary window), `_leave_count_days`, `_leave_balance`, `_pay_build_line`.

---

## 4. Calculation logic

All instants are UTC. Days are IST dates. Minutes are whole numbers: each entry is floored to whole minutes before summing. Money is integer paise. Each money component is computed exactly (SQL `numeric`) and **rounded once, half-up, to paise**. Net = sum of the rounded components.

### 4.1 Worked minutes for one person-day — `_att_day_facts(staff, d, rules, now)`

```
blocks   = shifts assigned to staff on d (staff_shifts effective on d, shift.days ∋ isodow(d))
           each block: start = d@start_min IST, end = (end_min <= start_min ? d+1 : d)@end_min IST
sched    = Σ(block.end − block.start) − max(block.break_min)        # scheduled net minutes
holiday  = staff_holidays[d];  leave = approved leave covering d (full | first_half | second_half)
entries  = active attendance_entries where staff and work_date = d, ordered by in_at

for e in entries with e.out_at null:                                 # open entry
    deadline = (last block end  ?? arena close on d  ?? e.in_at + max_open_hours) + auto_out_after_min
    if now >= deadline: e.out = deadline − auto_out_after_min, flag auto_out, review pending  # also persisted by _att_close_stale
    else:               e.out = now, provisional = true

gross    = Σ floor((e.out − e.in) / 60s)
longest_gap = max gap between consecutive entries (0 if one entry)
brk      = (gross >= break_after_min and longest_gap < max(block.break_min)) ? max(block.break_min) : 0
net      = max(0, gross − brk)
worked   = round(net, rounding)        # exact | nearest_15 (x.5 rounds up) | down_15

late     = blocks and entries and first(e.in) > first(block.start) + late_grace_min
early    = blocks and entries and last(e.out) < last(block.end) − early_leave_min and not auto_out

status:
  if holiday:            Holiday         (worked > 0 → off_day_min = worked)
  elif no blocks:        Week off        (worked > 0 → off_day_min = worked)
  elif leave = full:     On leave        (worked > 0 → flag worked_on_leave)
  else:
     target = leave is half ? sched/2 : sched
     if   worked >= full_day_pct  × target: Present (Late if late)   ; half-leave → 0.5 present + 0.5 leave
     elif worked >= half_day_pct  × target: Half-day                 ; half-leave → 0.5 leave + 0.5 absent
     else:                                  Absent                   ; half-leave → 0.5 leave + 0.5 absent
  d > today → Scheduled / Leave / Holiday only (no Absent)

std      = staff.standard_day_min ?? hours.standard_day_min           # e.g. 480
extra    = holiday or week off : worked                                # every minute (S2)
           working day         : max(0, worked − std)                  # a 12 h Sunday vs 8 h std → 240
regular  = worked − extra
   (extra basis = week, optional): computed per week in 4.2
```

This one function backs today's hours, history, the calendar, who's in and the salary run. The floor app's live timer only shows elapsed time since the server's `in_at` ("on the clock 3h 12m"). "Counted today" comes from the RPC.

### 4.2 Salary line — `_pay_build_line(run, staff)`

```
P = [period_start .. period_end], N = days in P
pol = pay policy effective at period_start;  att = attendance rules (snapshotted into run)
emp(d) = joined_on <= d <= left_on (nulls = open)
rate(d) = staff_pay_rates row with max(effective_from) <= d
facts = [_att_day_facts(staff, d) for d in P if emp(d)]

counts  = tally of facts: present(incl. late), late, half, absent, paid_leave, lop_leave, holiday, week_off
          (a request's paid_days fill its earliest dates, then lop_days; a half-day request = 0.5)
lates   = late + (pol.early_leave_counts_as_late ? early : 0)
late_pen_days = floor(lates / pol.late_every) × pol.late_penalty_days       # if pay_type ∈ pol.late_applies_to

extra_min(d) = facts[d].extra
          weekly basis (optional): per week W whose last day ∈ P, max(0, Σ worked(W) − std × scheduled days(W))
          + off-day minutes; priced at rate(last day of W)

divisor(d)  = N | 30 | 26 | scheduled days in P   (pol.day_divisor; decided: N)
day_rate(d) = rate(d).base / divisor(d)                               # monthly
std_h       = std / 60
hourly(d)   = rate(d).extra_hourly ?? ( monthly: day_rate(d) / std_h
                                        daily:   rate(d).base / std_h
                                        hourly:  rate(d).base )

extra_pay = rate.extra_hours_paid
              ? Σ_d extra_min(d)/60 × hourly(d) × pol.extra_multiplier
              : (hourly: Σ_d extra_min(d)/60 × rate(d).base   # still paid, no multiplier
                 monthly, daily: 0)

monthly:
   base  = Σ_{d∈P, emp(d)} rate(d).base / N                         # prorates joins, exits, mid-period changes
   deductions:
     absent    = Σ_{absent days} day_rate(d) × pol.absent_factor
     lop_leave = Σ_{LOP units}  day_rate(d) × pol.lop_factor
     half_day  = Σ_{half days}  day_rate(d) × 0.5
     late      = late_pen_days × day_rate(period_end)
daily:
   base  = Σ_d units(d) × rate(d).base   ; units: present/late 1, half 0.5, paid leave units,
                                             paid holiday 1 if pol.daily_paid_holidays; LOP 0
   late  = late_pen_days × rate(period_end).base
hourly:
   base  = Σ_d regular(d)/60 × rate(d).base + Σ_{paid leave units} std_h × rate(d).base

gross      = base + extra_pay
suggested  = the deduction components above, each rounded
applied(c) = salary_deduction_decisions(run, staff, c).applied ?? true      # owner keeps or waives each one
deductions = Σ suggested where applied, capped so gross − deductions ≥ 0 (cap noted in breakdown)
adjust     = Σ salary_adjustments(run, staff) incl. reversals
net        = gross − deductions + adjust          # net < 0 blocks finalise with "net_negative"
```

### 4.3 Worked examples

**Example 1: Fixed monthly.** Ravi, ₹18,000/month, extra hours off. October 2026 (N = 31). Shift Mon–Sat 11:00–20:00 with a 60-min break, so Sunday is the week off. Rules: day divisor = calendar, late rule 3 lates → ½ day.

- **Calendar:**
  - 4 Sundays are week-offs.
  - 2 Oct is a paid staff holiday.
  - That leaves 26 scheduled days.
- **Ravi's 26 days:**
  - 22 present, of which 4 late
  - 1 half-day
  - a 2-day leave approved as 1 paid (his last balance day) + 1 LOP
  - 1 absent (no leave applied)
- On the timesheet the owner keeps all four suggested deductions. Waiving the late one instead would add 29,032 back, for a net of 1,504,838.

| Line | Formula | Paise |
|---|---|---|
| Base | 1,800,000 × 31/31 | 1,800,000 |
| Absent | 1 × 1,800,000/31 = 58,064.52 → | −58,065 |
| LOP leave | 1 × 58,064.52 → | −58,065 |
| Half-day | 0.5 × 58,064.52 = 29,032.26 → | −29,032 |
| Late (4 lates → floor(4/3)=1 → ½ day) | 0.5 × 58,064.52 → | −29,032 |
| Advance (note: "Oct 10 advance") | | −200,000 |
| Bonus (note: "Diwali") | | +50,000 |
| **Net** | | **1,475,806 = ₹14,758.06** |

**Example 2: Hourly.** Priya, ₹120/h. Weekly period Mon 5 Oct – Sun 11 Oct 2026. Shift 16:00–22:00 with a 30-min break, Wednesday off. Rules:

- break after 300 min
- rounding to the nearest 15
- standard day 480 min
- extra hours paid on for Priya, arena multiplier 1.5

| Day | Entries | Gross | Break | Net | Rounded | Regular / Extra |
|---|---|---|---|---|---|---|
| Mon | 16:02–22:10 | 368 | 30 | 338 | 345 | 345 / 0 |
| Tue | 15:55–21:48 | 353 | 30 | 323 | 330 | 330 / 0 |
| Wed | Week off | – | – | – | – | – |
| Thu | 12:00–14:00, 17:00–22:20 (split) | 440 | 0 (180-min gap ≥ 30) | 440 | 435 | 435 / 0 |
| Fri | 16:00–02:10 Sat (crosses midnight, work_date Fri) | 610 | 30 | 580 | 585 | 480 / 105 |
| Sat | 16:05 – (forgot) → auto-out 22:00, flagged, accepted | 355 | 30 | 325 | 330 | 330 / 0 |
| Sun | 16:00–22:00 | 360 | 30 | 330 | 330 | 330 / 0 |

- Regular: 2,250 min = 37.5 h × 12,000 = **450,000**.
- Extra: 105 min = 1.75 h × 12,000 × 1.5 = **31,500**.
- Late rule doesn't apply to hourly staff (S4).
- **Net 481,500 = ₹4,815.00.**

**Example 3: Fixed monthly + extra hours (long Sundays, holiday work, a raise).** Arjun, ₹20,000/month, raised to ₹22,000 from 16 Oct. Extra hours paid on, no own extra rate (so it is derived), arena multiplier 1.5. October 2026 (N = 31), standard day 480 min.

- **Shifts:** "Weekday" Tue–Sat 14:00–23:00 with a 60-min break (8 h). "Sunday" 11:00–00:00 with a 60-min break (12 h). Monday is the week off.
- **Calendar:** 2 Oct (Fri) is a staff holiday; Arjun worked 8 h anyway. He worked exactly his shift on every other scheduled day except:
  - 8 Oct: paid leave
  - 22 Oct: LOP (approved, no balance)
- **Extra hours:**
  - Holiday 2 Oct: all 8 h (S2)
  - Sundays 4, 11, 18, 25 Oct: 12 h − 8 h = 4 h each
  - At the ₹20,000 rate (2, 4, 11 Oct): 16 h. At the ₹22,000 rate (18, 25 Oct): 8 h.
- **Derived hourly:**
  - ₹20,000 rate: 2,000,000 / 31 / 8 = 8,064.52 paise/h
  - ₹22,000 rate: 2,200,000 / 31 / 8 = 8,870.97 paise/h

| Line | Formula | Paise |
|---|---|---|
| Base | (2,000,000 × 15 + 2,200,000 × 16) / 31 = 65,200,000 / 31 = 2,103,225.81 → | 2,103,226 |
| Extra hours | 16 h × 8,064.52 × 1.5 + 8 h × 8,870.97 × 1.5 = 193,548.39 + 106,451.61 | +300,000 |
| Paid leave 8 Oct | no deduction | 0 |
| LOP 22 Oct | 1 × 2,200,000 / 31 = 70,967.74 → | −70,968 |
| Deduction (note: "Cracked controller, 20 Oct") | | −30,000 |
| **Net** | | **2,302,258 = ₹23,022.58** |

These three examples become pgTAP fixtures, asserting to the paisa.

---

## 5. Settings

| Setting | Default | Stored | Edited in |
|---|---|---|---|
| Geofence centre (lat/lng) | unset → every punch `unknown` | `settings.attendance.geofence` | Admin › Settings › Attendance (map click). Floor: "Use this device's location" (needs `settings`) |
| Geofence radius | 100 m | same | same |
| Outside / unknown rule | new arenas: allow (location checks off); older arenas: flag (block / flag / allow) | `settings.attendance` | Admin › Settings › Attendance |
| Minimum GPS accuracy | 50 m | same | same |
| Mock location rule | block (block / flag) | same | same |
| Kiosk tablets | none | `attendance_devices` | Floor: "Make this a clock-in tablet" (needs `settings`). Admin list to retire |
| Kiosk PIN length / lockout | 4 digits; 5 tries → 15 min | `settings.attendance.kiosk` | Admin › Settings › Attendance |
| Late grace | 10 min | `settings.attendance.hours` | Admin › Settings › Working hours |
| Early-leave threshold | 15 min | same | same |
| Break applies after | 300 min worked | same | same |
| Rounding | exact (exact / nearest 15 / down 15) | same | same |
| Full-day / half-day threshold | 75% / 40% of scheduled | same | same |
| Standard day (extra hours start after it; also used for staff without a shift) | 480 min; per-person override | same; `staff_hr_profiles.standard_day_min` | same; Admin › Staff › Pay setup |
| Extra-hours basis | per day (per week optional) | same | same |
| Week starts on | Monday | same | same |
| Auto clock-out after shift end | 120 min | same | same |
| Max open entry (no shift, no hours) | 14 h | same | same |
| Shifts (name, times, days, break) | none | `shifts` | Admin › Staff › Shifts & holidays |
| Shift assignment | none (= every day is a week-off) | `staff_shifts` | same, and per person in Pay setup |
| Staff holidays (+ paid) | none; paid = yes | `staff_holidays` | same |
| Paid-leave allowance per year | 12 days; per-person override | `settings.leave_rules.paid_leave_days`; `staff_hr_profiles.paid_leave_days` | Admin › Staff › Leave › Allowance; Pay setup for the override |
| Leave year | from the joining date (anniversary) | fixed rule | — |
| Half-day leave allowed | yes | `settings.leave_rules` | Admin › Staff › Leave › Allowance |
| Unplanned leave backdating | up to 7 days | same | same |
| Self-approval | owner only | same | same |
| Pay period | monthly, cycle starts day 1 (weekly: Monday; custom per run) | `pay_policies.policy.period` | Admin › Staff › Payroll › Rules |
| Day divisor | calendar days | `pay_policies` | same |
| Absent / LOP / half-day factor | 1.0 / 1.0 / 0.5 day | same | same |
| Late rule | every 3 lates = 0.5 day; applies to monthly, daily | same | same |
| Early leave counts as late | yes | same | same |
| Extra-hours multiplier | 1.0 | same | same |
| Work on holiday / week-off | every minute is extra hours (decided) | fixed rule | — |
| Paid holidays for daily staff | off | same | same |
| Joined / left date, tracks attendance, employee code | — / — / on (off for owner) / — | `staff_hr_profiles` | Admin › Staff › Pay setup |
| Pay type, rate, extra hours paid, own extra-hours rate, effective from | none (must be set before a run includes the person); extra hours off; rate derived | `staff_pay_rates` | same |
| Permissions | none | `staff_profiles.perms` | Admin › Users (`payroll*` grantable by owner only) |

---

## 6. Screens

### Floor app (Flutter)

Entry point: the More screen's "Shift" placeholder becomes **Attendance**. A **Team** group appears when the user holds `attendance_review` or `leave_approve`, with badge counts. Screens reuse `ArenaRowGroup`/`ArenaListRow`, `StatusDotLabel`/`ArenaTag`, `ArenaSegmented` and the bottom-sheet patterns in `features/floor/presentation/sheets/`.

| Screen | Who | Main actions |
|---|---|---|
| Attendance (clock) | anyone tracked | Status card ("On the clock since 11:02 · 3h 12m" / "Clocked out"); location chip (Inside · 42 m · ±8 m); **Clock in / Clock out**; today's entries and counted minutes; fixes for denied, GPS off and outside |
| My attendance | self | Month list or calendar with day status; tap an entry to see a map pin per punch, inside/outside badge, flags and correction history |
| My profile & leave | self | Profile card: joined date, current leave year, paid-leave allowance, used, pending, balance. My requests by status (with paid/LOP split once decided). **Apply** sheet (dates, half-day, planned/unplanned, reason; shows the day count and "Likely paid 2 · LOP 1" from the balance). Cancel pending; request cancellation of approved |
| Clock-in tablet (kiosk) | registered tablet | Name grid → PIN pad → "Clock in Ravi?" → done. Auto-returns to the grid |
| Who's in | `attendance_review` | On the clock (since, badge, late); scheduled but not in; on leave today; tap → person's day |
| Leave approvals | `leave_approve` | Pending requests and cancellation requests. Shows the person's balance and team overlap. **Approve** with a paid/LOP split (pre-filled from the balance, editable), or **Reject**; optional note |
| Flagged entries | `attendance_review` | Auto-out, outside, unknown, mock, worked-on-leave. **Accept**, **Correct times** (reason), **Void** (reason), **Add missing entry** |

### Admin web (Angular)

Nav group **Staff** has three screens, each in the usual list/detail frame. **Team** lists employees
only (staff, and an owner only when "Works here as staff" is on: their HR profile tracks attendance);
Add staff sends a staff invitation (never owner access). An employee opens with tabs: Overview
(contact, role, status, employment details), Attendance (their month), Leave (balance, history,
record, adjust), Salary (pay rate history), Schedule (shift assignments) and Access (permissions,
access on/off), each shown only with its permission. **Attendance** lists employees for Today or the
month (Calendar; everyone's grid beside the list on wide screens), with Needs review and Leave
requests at the top when there are any; Detailed records (`/staff/attendance/records`) and leave
requests and balances (`/staff/attendance/leave`) are in its menu. **Payroll** is period-based.
Settings has **Owners & access** (owners, inviting another owner: owners only) and **Staff**
(location checks, working hours, paid leave; shifts and holidays at `/settings/schedule`; the
attendance, working-hour, leave and payroll rules under Advanced settings). The old Users screen is
gone: employee access is on Team, owners in Settings. Employees without a login are not supported
(`staff_profiles.user_id` is required), so adding staff always sends an invitation. The table below lists what each part does. Each item is hidden unless the user holds the permission it needs. Screens use the `list-detail` frame, `stat-tile`, `status-pill`, `confirm-dialog` and `unsaved-bar`. Writes go through `pushOps`.

| Screen | Perm | Main actions |
|---|---|---|
| Settings › Attendance | settings | Map (Leaflet + OSM) to set the centre and radius circle; the outside, mock and accuracy rules; kiosk tablets (retire); reset someone's PIN |
| Settings › Working hours | settings | Grace, early leave, break threshold, rounding, half-day %, standard day, extra-hours basis, auto-out |
| Staff › Shifts & holidays | settings | Shift list-detail; assign staff with effective dates; staff holiday list; "Copy from arena holidays" |
| Staff › Pay setup | payroll | Per person: joined/left, tracks attendance, standard-day and leave-allowance overrides; pay type, rate, extra hours paid on/off and optional own extra rate, as a history with "New rate from …" (past periods locked). Pay rules section (effective-dated): multiplier, deduction factors, late rule |
| Staff › Attendance log | attendance_review | Table filtered by dates, staff, inside/outside/unknown, flags and source; **Map view** with pins and the geofence circle; entry detail with punch evidence and supersede chain; correct, void, add, accept; CSV |
| Staff › Calendar | attendance_review | Month grid per person (status chips, extra hours), totals row; click a day → entries |
| Staff › Leave | leave_approve (allowance: settings) | Arena allowance and leave rules; requests with filters, approve (paid/LOP split), reject and cancel; balances table (allowance, used, balance, leave year per person); adjust balance (reason) |
| Staff › Payroll | payroll (finalise: payroll_finalise) | Runs list. **New draft** for the next period opens the **month-end timesheet**: per person, days by status, hours, extra hours, paid leave / LOP, lates and flags, with day-by-day entries on click. Each suggested deduction has a **Keep / Waive** switch and an optional note. The breakdown drawer shows days, hours, rates, each deduction (applied or waived), each adjustment and net. Add or reverse an adjustment; **Recalculate**; **Finalise** (confirm dialog); discard draft; **Export timesheet / summary CSV, Print PDF** |
| Users | owner/settings | Four new permission toggles; `payroll*` toggles only for the owner |

---

## 7. Build order

Every phase ships on its own and passes `bash tool/verify_all.sh` (plus `--with-it` from P1 on). Each phase follows the declarative schema workflow from CLAUDE.md and adds pgTAP tests, Dart unit and widget tests (phone and desktop) and admin Vitest tests. Each ends with a route list and a click-through checklist for you.

**P1 — Clock in/out with GPS and the geo-tagged log (only this).** ✅ built 2026-10-15

- **Server:**
  - `attendance_punches`, `attendance_entries` (no review or correction ops yet)
  - `app_my_staff_ids`, `_geo_distance_m`
  - the `attendance` settings key (geofence, outside, mock and accuracy rules only)
  - the new perm `attendance_review` (needed for the admin log)
  - op `attendance.punch` (own device only)
  - forgot-out fallback: the next clock-in auto-closes an entry older than `max_open_hours` and flags it
- **Floor:**
  - `geolocator`, `flutter_map` + `latlong2`
  - Android `ACCESS_FINE/COARSE_LOCATION`; iOS `NSLocationWhenInUseUsageDescription`
  - a `LocationProbe` (fix, accuracy, mock, status, 15 s timeout)
  - a direct online push path that skips the outbox (reusing `data/sync/sync_transport.dart`)
  - `AttendanceRepository`, `AttendanceActions`
  - the Attendance clock screen and the My attendance log with map pins
- **Admin:**
  - `leaflet`
  - Settings › Attendance (geofence and rules)
  - Staff › Attendance log (table, filters, map, CSV)
  - Users toggle for `attendance_review`
  - `realtime-sync.ts` targets
- **Tests:**
  - pgTAP `28_attendance_punch_test.sql`: own-vs-review RLS, block/flag/allow, mock, low accuracy, no fix, double in/out, `op_id` replay, `device_at` ignored, anon refused
  - Dart: action guard and failure mapping; widget tests for the clock screen states
  - `sync_it` round trip

**P2 — Review, corrections, who's in, kiosk tablet.** Corrections + review ✅ built 2026-10-16 (admin web). Kiosk tablet dropped for now; who's-in board not built.

- Ops `attendance.correct`, `attendance.review`, `attendance.device_register`, `attendance.device_retire`, `attendance.pin_set`, and kiosk punches.
- `attendance_devices`, `attendance_pins`, `staff_hr_profiles` (`tracks_attendance`).
- The `audit_log` entries.
- Floor: Who's in and Flagged entries screens, and kiosk mode.
- Admin: correct, void and add from the log.

**P3 — Shifts, holidays, daily status.** ✅ built 2026-10-16 (settings key `work_hours`, not `attendance.hours`)

- `shifts`, `staff_shifts`, `staff_holidays`.
- The working-hours settings.
- `_att_day_facts`, `attendance_days`, and auto clock-out at shift end (`_att_close_stale`, lazy).
- Floor: day status in history.
- Admin: Shifts & holidays, Working hours, Calendar.
- pgTAP covers midnight crossing, split shifts, rounding, late/early and half-day/absent thresholds.

**P4 — Leave.** ✅ built 2026-10-16 (approvals on admin web only)

- `leave_requests`, `leave_adjustments`, the `leave_rules` key, `staff_hr_profiles.paid_leave_days`, the perm `leave_approve`.
- Ops `leave.request`, `leave.cancel`, `leave.decide` (paid/LOP split), `leave.adjust`; RPC `leave_balances`; `_leave_year` (joining anniversary).
- pgTAP: anniversary windows (incl. 29 Feb joiners), a request crossing the anniversary, split suggestion vs. approver override, backdating limits.
- Floor: My profile & leave, and Leave approvals.
- Admin: Leave.
- Calendar and day facts pick up leave.

**P5 — Push notifications (FCM).**

- `push_devices`, `push_outbox`, pg_net trigger, Edge Function `push-send` (FCM HTTP v1, service-account secret in Supabase secrets).
- `firebase_core` + `firebase_messaging` in the floor app (Android `google-services.json`, iOS APNs key).
- Ops `push.register` and `push.unregister`; notification taps deep-link to the request.
- Senders: `leave.request` → approvers, `leave.decide` → staff, optionally a new flag → reviewers.
- Local dev: the function runs with `supabase functions serve` in dry-run (logs instead of FCM).
- Update CLAUDE.md, `supabase/README.md` and `docs/RELEASE.md`. **Needs a Firebase project from you.**

**P6 — Pay setup.** ✅ built 2026-10-16

- `staff_pay_rates`, `pay_policies`, the perms `payroll` and `payroll_finalise`.
- Ops `hr_profile.save`, `pay_rate.add`, `pay_policy.add` (effective date after the last finalised period).
- Admin: Pay setup and Payroll › Rules.

**P7 — Salary runs.** ✅ built 2026-10-16

- `salary_runs`, `salary_run_lines`, `salary_adjustments`, `salary_deduction_decisions`, `_pay_build_line`.
- Ops: create, recalculate, finalise, discard; `salary_run.set_deduction` (keep/waive, drafts only); add and reverse adjustment.
- The finalised-period lock on attendance and leave ops.
- Admin: month-end timesheet, keep/waive switches, breakdown, CSV and print-to-PDF.
- pgTAP: the three worked examples to the paisa, a waived deduction (and that it survives Recalculate), overlap refusal, lock behaviour, staff unable to read any pay table.
- Run `tool/pricing_parity.sh`, since this touches money and time.

**P8 — Optional.**

- pg_cron hourly `_att_close_stale`
- browser push for admin
- advance instalments
- "mark paid"
- cross-arena owner summary

### Files touched (representative)

- **Supabase:**
  - `supabase/schemas/public/functions/_known_perms.sql`, `_create_arena_with_owner.sql`, `bootstrap_owner.sql`
  - `_sync_apply.sql` (dispatch), `op_settings_save.sql` (whitelist)
  - new `public/tables/*.sql`, `public/functions/op_*.sql`, `_att_*.sql`, `_pay_*.sql`
  - `private/functions/app_my_staff_ids.sql` + RPC bodies
  - `supabase/tests/28_…`–`3x_…`, `supabase/README.md`
- **Floor app (`apps/mobile`):**
  - `lib/domain/auth/permission.dart` and the `_phrase` switch in `permission_guard.dart`
  - `lib/features/more/presentation/more_screen.dart` (Shift row → Attendance, Team group)
  - new `lib/features/attendance/`, `lib/features/leave/`, `lib/features/team/`
  - `lib/app/controllers/attendance_actions.dart`, `leave_actions.dart`
  - `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
  - no Drift schema change: the module is online-only
- **Admin (`apps/admin`):**
  - `src/app/core/layout/nav.ts`, `app.routes.ts` (`BUILT`), `core/sync/realtime-sync.ts`
  - `features/users/data/user.models.ts`
  - `features/settings/`
  - new `features/attendance/`, `features/leave/`, `features/payroll/`, `features/shifts/`
  - CSV via the `sales-csv.ts` download pattern
- **Docs:**
  - new `docs/STAFF.md` (this spec)
  - S1–S22 rows in `docs/OWNER_CONFIRMATION.md`
  - CLAUDE.md: the new perms, the Edge Function exception (P5), and "staff module is online-only, not in sync_pull"

### Verification

- **After each phase:**
  - `bash tool/verify_all.sh --with-it`
  - `supabase test db --local` and `supabase db advisors --local --type all` (no unindexed FKs, no stray grants)
  - the declarative sync re-run says "No schema changes found"
- **P7 adds:** `--with-psql` plus `tool/pricing_parity.sh`.
- No manual or visual testing by me. Each phase ends with a click-through checklist for you.
