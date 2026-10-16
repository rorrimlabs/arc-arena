# Staff module: server contract (salary round)

This is the contract between `supabase/` and both apps for shifts, working hours, corrections,
leave, pay setup and salary runs. The design and its reasons are in `docs/STAFF.md`; open business
rules are in `docs/OWNER_CONFIRMATION.md` (S-rows).

Conventions (same as the rest of the app):
- Every write is an op through `sync_push(p_arena, [{op_id, kind, payload}], p_device)`. Device or
  dashboard ids are uuid v4. Each op's refusal code is its `error` and the server hint is its
  `detail`.
- Times are ISO-8601 UTC (`timestamptz`). Days are IST dates (`YYYY-MM-DD`). Minutes after IST
  midnight are integers 0–1439. Money is integer paise.
- **None of these tables are in the `sync_pull` feed.** Apps read them online through RLS
  selects and the read RPCs below. The floor app sends its ops straight to `sync_push`, with no
  outbox.
- `period_finalised`: a change that would alter a day inside a **finalised** salary run is
  refused. The fix goes in the next run as an adjustment.

## Permissions

| Code | Grants | Who may grant it |
|---|---|---|
| `attendance_review` | Read everyone's attendance; correct, void, add and accept entries | `settings` holder |
| `leave_approve` | Read everyone's leave; approve, reject, cancel; adjust balances | `settings` holder |
| `payroll` | HR profiles, pay rates, pay rules, salary drafts, deductions keep/waive, adjustments; read all pay | owner level only (like `money`) |
| `payroll_finalise` | Finalise or discard a salary run | owner level only |

`role = 'owner'` holds everything. Any active member may clock in, read their own attendance and
leave, and apply for or cancel their own leave.

**Own-record rule:** nobody approves their own leave or corrects or accepts their own attendance,
unless they are `role = 'owner'`. The refusal code is `own_record`.

## Settings keys (op `settings.save {key, json}`, needs `settings`)

The **whole object** must be sent and no other keys are allowed. Defaults apply while no row
exists.

`work_hours`. Refusal code: `invalid_work_hours`; the hint names the field.

| Field | Type / range | Default |
|---|---|---|
| `late_grace_min` | int 0–120 | 10 |
| `early_leave_min` | int 0–240 | 15 |
| `break_after_min` | int 0–1440 (the shift break is deducted when the day's clocked minutes reach this) | 300 |
| `rounding` | `exact` \| `nearest_15` \| `down_15` (applied to the day's total after the break) | `exact` |
| `full_day_pct` | int 1–100; must be > `half_day_pct` | 75 |
| `half_day_pct` | int 1–99 | 40 |
| `standard_day_min` | int 60–1440 (extra hours start after this on a working day; also used for staff without a shift) | 480 |
| `extra_basis` | `day` \| `week` | `day` |
| `week_start` | int 1–7 (ISO, 1 = Monday) | 1 |
| `auto_out_after_min` | int 0–720 (grace after the shift end before a still-open clock-in counts as forgotten) | 120 |

`leave_rules`. Refusal code: `invalid_leave_rules`.

| Field | Type / range | Default |
|---|---|---|
| `paid_leave_days` | number 0–366 in steps of 0.5 (the paid allowance per leave year) | 12 |
| `half_day_allowed` | bool | true |
| `unplanned_backdate_days` | int 0–31 | 7 |

(`attendance` key: unchanged from phase 1. A new arena is created with it saved as
`outside_rule: allow`, no geofence: location checks off until the owner turns them on. Arenas
created earlier keep the built-in default, `flag`.)

## Tables (read through RLS)

### `staff_hr_profiles`
- Readable by the member themselves, or by holders of `attendance_review`, `leave_approve` or
  `payroll`.
- Columns:
  - `staff_id` (PK, references `staff_profiles.id`)
  - `arena_id`
  - `joined_on`, `left_on`: date or null
  - `tracks_attendance`: bool
  - `employee_code`: text or null
  - `paid_leave_days`: numeric or null (null = arena default)
  - `standard_day_min`: int or null (null = arena default)
  - `created_at`, `updated_at`
- **No row** means: joined on the profile's creation date (IST), not left, `tracks_attendance =
  (role <> 'owner')`, arena defaults for the rest.

### `shifts` (readable by all members)
- `id`, `arena_id`
- `name` (unique per arena, case-insensitive)
- `start_min`, `end_min` (0–1439; `end_min <= start_min` means the shift ends the next day)
- `days` smallint[] (ISO 1–7)
- `break_min` (0–719)
- `active`, `created_at`, `updated_at`

### `staff_shifts` (readable by all members)
- `id`, `arena_id`, `staff_id`, `shift_id`
- `effective_from` (date)
- `effective_to` (date, inclusive; null = open-ended)
- A person can hold several shifts at once, which makes a split shift.
- The same person + shift may not have overlapping date ranges.
- A day where none of the person's shifts apply is a **week off**.

### `staff_holidays` (readable by all members)
- `id`, `arena_id`, `day` (unique per arena), `name`, `paid` (default true)

### `attendance_entries` (phase 1) changes
- New `out_source` value: `manual`.
- New flags: `past_shift_end` (clocked out after the shift end + grace; kept, put up for review)
  and `auto_out`.
- Corrections add rows with `source = 'manual'`, `replaces_id`, `reason`, `review = 'corrected'`.
  The old row becomes `superseded`, or `voided` on a void.

### `leave_requests`
- Readable by the member themselves, or by holders of `leave_approve`, `attendance_review` or
  `payroll`.
- Columns:
  - `id` (client uuid), `arena_id`, `staff_id`
  - `kind`: `planned` \| `unplanned`
  - `from_date`, `to_date`
  - `half_day`: `none` \| `first_half` \| `second_half` (single-day requests only)
  - `days` (numeric; working days only, counted by the server)
  - `paid_days`, `lop_days`: numeric or null until approved
  - `day_split`: jsonb `[{day, units, paid_units}]`, fixed at approval
  - `reason`
  - `status`: `pending` \| `approved` \| `rejected` \| `cancelled` \| `cancel_pending`
  - `decided_by`, `decided_at`, `decision_note`
  - `cancel_reason`
  - `created_by`, `created_at`, `updated_at`

### `leave_adjustments`
- Same read rule as `leave_requests`. Append-only.
- `id`, `arena_id`, `staff_id`
- `year_start` (date: the leave year it counts in)
- `days` (signed)
- `reason`, `created_by`, `created_at`

### `staff_pay_rates`
- Readable with `payroll` only. Append-only and effective-dated.
- `id`, `arena_id`, `staff_id`, `effective_from`
- `pay_type`: `monthly` \| `daily` \| `hourly`
- `base_paise`: per month, day or hour
- `extra_hours_paid`: bool
- `extra_hourly_paise`: bigint or null (null = derived from the pay)
- `note`, `created_by`, `created_at`

### `pay_policies`
- Readable with `payroll` only. Append-only and effective-dated.
- `id`, `arena_id`, `effective_from`, `policy` (jsonb, see below), `created_by`, `created_at`
- With no row, the defaults apply. A run uses the row in force on its `period_start`.

`policy` (all keys required). Refusal code: `invalid_pay_policy`.

| Field | Type / range | Default |
|---|---|---|
| `period_kind` | `monthly` \| `weekly` \| `custom` | `monthly` |
| `cycle_start_day` | int 1–28 (monthly) | 1 |
| `day_divisor` | `calendar` \| `30` \| `26` \| `scheduled` | `calendar` |
| `absent_factor` | number 0–3 (days of pay per absent day) | 1 |
| `lop_factor` | number 0–3 | 1 |
| `half_day_factor` | number 0–1 | 0.5 |
| `late_every` | int 0–31 (0 = no late rule) | 3 |
| `late_penalty_days` | number 0–1 | 0.5 |
| `late_applies_to` | array of `monthly`, `daily`, `hourly` | `["monthly","daily"]` |
| `early_leave_counts_as_late` | bool | true |
| `extra_multiplier` | number 1–5 | 1 |
| `daily_paid_holidays` | bool | false |

### `salary_runs`
- Readable with `payroll` or `payroll_finalise`.
- `id` (client uuid), `arena_id`
- `period_start`, `period_end` (inclusive)
- `status`: `draft` \| `finalised` \| `discarded`
- `rules_snapshot` (jsonb `{work_hours, attendance, leave_rules, pay_policy}`), `computed_at`
- Totals: `staff_count`, `gross_paise`, `deductions_paise`, `adjustments_paise`, `net_paise`
- `created_by`, `created_at`, `finalised_by`, `finalised_at`, `updated_at`
- Runs that are not discarded never overlap.

### `salary_run_lines`
One row per person per run, rebuilt while the run is a draft and frozen at finalise.
- Same read rule as `salary_runs`.
- Identity: `id`, `arena_id`, `run_id`, `staff_id`
- Snapshots: `staff_name`, `pay_type`
- `rates`: jsonb, the rate rows used, e.g. `[{effective_from, pay_type, base_paise,
  extra_hours_paid, extra_hourly_paise}]`
- `day_counts`: jsonb `{scheduled, present, late, half_day, absent, paid_leave, lop_leave,
  holiday, week_off}`
- Minutes: `worked_min`, `regular_min`, `extra_min`
- Money: `base_paise`, `extra_paise`, `gross_paise`, `deductions_paise`, `adjustments_paise`,
  `net_paise`
- `deductions`: jsonb `[{code, label, units, rate_paise, amount_paise, applied, note}]`. `code` is
  one of `absent`, `lop_leave`, `half_day`, `late`. `amount_paise` is the suggestion (positive).
  Only rows with `applied = true` count.
- `days`: jsonb, one entry per day in the period: `{day, status, worked_min, extra_min, late, early,
  present_units, absent_units, leave_paid, leave_lop, holiday, flags}`. This is the timesheet.
- `notes`: jsonb array of strings, e.g. "no pay rate for 1–9 Oct" or "deductions capped at gross".

### `salary_deduction_decisions`
- Same read rule as `salary_runs`.
- `id`, `arena_id`, `run_id`, `staff_id`, `code`, `applied`, `note`, `decided_by`, `decided_at`
- Unique on (`run_id`, `staff_id`, `code`). No row means the suggestion applies.

### `salary_adjustments`
- Same read rule as `salary_runs`. Append-only.
- `id`, `arena_id`, `run_id`, `staff_id`
- `kind`: `bonus` \| `advance` \| `deduction` \| `reversal`
- `amount_paise`: signed (bonus > 0; advance and deduction < 0)
- `note`, `reverses_id`, `created_by`, `created_at`

## Ops

All refusal codes are listed. `forbidden` = missing permission; `not_found` (hint names what);
`invalid_payload` (hint names the field).

### Shifts, holidays and HR profiles
- **`shift.upsert`**: `{id, name, start_min, end_min, days, break_min, active}`. Needs `settings`.
  - Refusals: `invalid_shift` (hint), `duplicate` (name taken).
- **`shift.assign`**: `{id, staff_id, shift_id, effective_from, effective_to?}`. Upserts by `id`.
  Needs `settings`.
  - Refusals: `not_found`, `invalid_payload`, `assignment_overlap`.
- **`shift.unassign`**: `{id}`. Deletes the assignment. Needs `settings`.
- **`staff_holiday.upsert`**: `{day, name, paid?}`. Needs `settings`.
- **`staff_holiday.delete`**: `{day}`. Needs `settings`.
- **`hr_profile.save`**: `{staff_id, joined_on?, left_on?, tracks_attendance?, employee_code?,
  paid_leave_days?, standard_day_min?}`. Needs `payroll`.
  - A key left out keeps its value; an explicit `null` clears it.
  - Refusals: `not_found`, `invalid_payload`.

### Attendance corrections (needs `attendance_review`)
- **`attendance.correct`**, one of three actions:
  - `{action:'edit', entry_id, in_at, out_at|null, reason}`
  - `{action:'void', entry_id, reason}`
  - `{action:'add', staff_id, in_at, out_at, reason}`
  - Returns `{entry_id}`: the new row's id, or the voided row's id.
  - Refusals: `reason_required`, `not_found`, `own_record`, `not_active` (the entry was already
    superseded or voided), `invalid_times` (out ≤ in, in the future, or longer than 24 h),
    `overlap` (another active entry), `period_finalised`.
- **`attendance.review`**: `{entry_id, note?}`. Changes `pending` to `accepted`.
  - Refusals: `not_found`, `own_record`, `not_pending`.

### Leave
- **`leave.request`**: `{id, kind, from_date, to_date, half_day, reason}`. For the caller only.
  Returns `{days}`.
  - Refusals:
    - `reason_required`
    - `invalid_dates`
    - `half_day_not_allowed`
    - `planned_in_past` (a planned request must start today or later)
    - `too_far_back` (an unplanned request may go back at most `unplanned_backdate_days`)
    - `leave_overlap`
    - `no_working_days`
    - `period_finalised`
- **`leave.cancel`**: `{id, reason?}`. For the caller's own requests.
  - `pending` becomes `cancelled`; `approved` becomes `cancel_pending`.
  - Refusals: `not_found`, `invalid_state`, `period_finalised`.
- **`leave.decide`**: `{id, approve, paid_days?, note?}`. Needs `leave_approve`.
  - On `pending`: approve gives `approved` (with `paid_days`; the default is min(days, the
    available balance)); reject gives `rejected`.
  - On `cancel_pending`: approve gives `cancelled`; reject gives `approved`.
  - `paid_days` is 0–days in steps of 0.5; `lop_days = days − paid_days`.
  - Refusals: `not_found`, `own_record`, `invalid_state`, `invalid_paid_days`,
    `period_finalised`.
- **`leave.record`**: `{id, staff_id, from_date, to_date, half_day, paid, reason?}`. Needs
  `leave_approve`. A manager records someone's leave already approved: every working day paid
  (`paid: true`) or every day loss of pay. Same row and `day_split` as request + decide; no
  backdating limit; `kind` = planned from today on, else unplanned; reason defaults to
  "Recorded by a manager". Audit action `record`. Returns `{days, paid_days, lop_days}`.
  - Refusals: `not_found`, `own_record`, `invalid_payload`, `invalid_dates`,
    `half_day_not_allowed`, `period_finalised`, `leave_overlap`, `no_working_days`.
- **`leave.adjust`**: `{staff_id, days, reason}`. Needs `leave_approve`. Counts in the person's
  current leave year.
  - Refusals: `reason_required`, `invalid_payload`, `not_found`.

### Pay
- **`pay_rate.add`**: `{id, staff_id, effective_from, pay_type, base_paise, extra_hours_paid,
  extra_hourly_paise?, note?}`. Needs `payroll`.
  - Refusals: `invalid_rate` (hint), `duplicate` (that date already has a rate),
    `rate_in_finalised_period`.
- **`pay_policy.add`**: `{id, effective_from, policy}`. Needs `payroll`.
  - Refusals: `invalid_pay_policy` (hint), `duplicate`, `rate_in_finalised_period`.

### Salary runs
- **`salary_run.create`**: `{id, period_start, period_end}`. Needs `payroll`. Returns
  `{staff_count}`.
  - Refusals: `invalid_period` (end before start, or longer than 62 days), `run_overlap`.
  - First closes forgotten clock-ins for the arena. Then it builds one line per person who has a
    pay rate in force on or before `period_end` and was employed for part of the period.
- **`salary_run.recalculate`**: `{id}`. Needs `payroll`. Rebuilds every line from live data plus
  the decisions and adjustments.
  - Refusal: `run_not_draft`.
- **`salary_run.set_deduction`**: `{run_id, staff_id, code, applied, note?}`. Needs `payroll`.
  Rebuilds that person's line.
  - Refusals: `run_not_draft`, `invalid_payload`.
- **`salary_adjustment.add`**: `{id, run_id, staff_id, kind: bonus|advance|deduction,
  amount_paise > 0, note}`. Needs `payroll`. Stored signed.
  - Refusals: `run_not_draft`, `note_required`, `invalid_payload`, `not_found`.
- **`salary_adjustment.reverse`**: `{id, reverses_id, note}`. Needs `payroll`.
  - Refusals: `run_not_draft`, `already_reversed`, `not_found`.
- **`salary_run.finalise`**: `{id}`. Needs `payroll_finalise`. Recalculates, then locks.
  - Refusals: `run_not_draft`, `net_negative` (hint names the person).
- **`salary_run.discard`**: `{id}`. Needs `payroll_finalise`.
  - Refusal: `run_not_draft`.

## Read RPCs (client API)

- **`attendance_days(p_arena uuid, p_from date, p_to date, p_staff uuid default null)`**: rows of
  `{staff_id, staff_name, work_date, status, sched_min, worked_min, regular_min, extra_min, late,
  early, present_units, absent_units, leave_paid, leave_lop, holiday_name, flags, open, entries}`.
  - With `p_staff` null, it covers every tracked staff member and needs `attendance_review` or
    `payroll`. Your own `p_staff` is always allowed.
  - At most 62 days. Closes forgotten clock-ins first.
  - `status`: `present` \| `late` \| `half_day` \| `absent` \| `on_leave` \| `half_leave` \|
    `holiday` \| `week_off` \| `upcoming` \| `not_employed`.
- **`leave_balances(p_arena uuid, p_staff uuid default null)`**: rows of `{staff_id, staff_name,
  joined_on, year_start, year_end, allowance, adjustments, used, pending, balance}`.
  - With `p_staff` null, it covers every staff member and needs `leave_approve` or `payroll`. Your
    own is always allowed.
