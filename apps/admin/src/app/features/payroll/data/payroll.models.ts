import { PillTone } from '../../../shared/status-pill/status-pill';
import { formatRange, isoWeekday, rangesOverlap } from '../../../shared/staff/staff-format';
import { addDays, daysBetween } from '../../../shared/time/ist';
import { PayPolicy, PayType } from './pay-policy';

/**
 * Salary runs (docs/STAFF_API.md › salary_runs, salary_run_lines, salary_adjustments). The
 * server computes every figure (docs/STAFF.md §4); the dashboard only shows them and sends the
 * owner's decisions: keep or waive each suggested deduction, adjustments, finalise. Money is
 * integer paise; minutes are whole numbers; days are IST dates.
 */
export type RunStatus = 'draft' | 'finalised' | 'discarded';
export type DeductionCode = 'absent' | 'lop_leave' | 'half_day' | 'late';
export type AdjustmentKind = 'bonus' | 'advance' | 'deduction' | 'reversal';
/** What the owner may add (a reversal is made by Reverse). */
export type NewAdjustmentKind = Exclude<AdjustmentKind, 'reversal'>;

export interface SalaryRun {
  readonly id: string;
  readonly periodStart: string;
  readonly periodEnd: string;
  readonly status: RunStatus;
  readonly computedAt: string | null;
  readonly staffCount: number;
  readonly grossPaise: number;
  readonly deductionsPaise: number;
  readonly adjustmentsPaise: number;
  readonly netPaise: number;
  readonly createdBy: string;
  readonly createdAt: string;
  readonly finalisedBy: string | null;
  readonly finalisedAt: string | null;
}

/** A pay rate a line used (several when it changed inside the period). */
export interface RateUsed {
  readonly effectiveFrom: string;
  readonly payType: PayType;
  readonly basePaise: number;
  readonly extraHoursPaid: boolean;
  readonly extraHourlyPaise: number | null;
}

export interface DayCounts {
  readonly scheduled: number;
  readonly present: number;
  readonly late: number;
  readonly halfDay: number;
  readonly absent: number;
  readonly paidLeave: number;
  readonly lopLeave: number;
  readonly holiday: number;
  readonly weekOff: number;
}

export interface Deduction {
  readonly code: DeductionCode;
  readonly label: string;
  /** Days of pay (0.5 for a half day). */
  readonly units: number;
  /** The day rate (may carry fractions of a paisa: the server rounds the amount once). */
  readonly ratePaise: number;
  /** The suggestion, positive. */
  readonly amountPaise: number;
  /** Kept (true) or waived (false); suggestions start kept. */
  readonly applied: boolean;
  readonly note: string | null;
}

/** One day of a person's timesheet. */
export interface DayFact {
  readonly day: string;
  readonly status: string;
  readonly workedMin: number;
  readonly extraMin: number;
  readonly late: boolean;
  readonly early: boolean;
  readonly presentUnits: number;
  readonly absentUnits: number;
  readonly leavePaid: number;
  readonly leaveLop: number;
  /** The staff holiday's name, or null. */
  readonly holiday: string | null;
  readonly flags: readonly string[];
}

export interface RunLine {
  readonly id: string;
  readonly runId: string;
  readonly staffId: string;
  readonly staffName: string;
  readonly payType: PayType;
  readonly rates: readonly RateUsed[];
  readonly dayCounts: DayCounts;
  readonly workedMin: number;
  readonly regularMin: number;
  readonly extraMin: number;
  readonly basePaise: number;
  readonly extraPaise: number;
  readonly grossPaise: number;
  readonly deductionsPaise: number;
  readonly adjustmentsPaise: number;
  readonly netPaise: number;
  readonly deductions: readonly Deduction[];
  readonly days: readonly DayFact[];
  readonly notes: readonly string[];
}

export interface SalaryAdjustment {
  readonly id: string;
  readonly runId: string;
  readonly staffId: string;
  readonly kind: AdjustmentKind;
  /** Signed: bonus > 0; advance and deduction < 0; a reversal undoes another. */
  readonly amountPaise: number;
  readonly note: string;
  readonly reversesId: string | null;
  readonly createdBy: string;
  readonly createdAt: string;
}

/** A run's lines and adjustments (the run detail). */
export interface RunDetail {
  readonly lines: readonly RunLine[];
  readonly adjustments: readonly SalaryAdjustment[];
}

const RUN_STATUS: Readonly<Record<RunStatus, { label: string; tone: PillTone }>> = {
  draft: { label: 'Draft', tone: 'warning' },
  finalised: { label: 'Finalised', tone: 'success' },
  discarded: { label: 'Discarded', tone: 'info' },
};

export function runStatus(s: RunStatus): { label: string; tone: PillTone } {
  return RUN_STATUS[s];
}

export function periodLabel(r: { periodStart: string; periodEnd: string }): string {
  return formatRange(r.periodStart, r.periodEnd);
}

const DAY_STATUS: Readonly<Record<string, { label: string; tone: PillTone }>> = {
  present: { label: 'Present', tone: 'success' },
  late: { label: 'Late', tone: 'warning' },
  half_day: { label: 'Half-day', tone: 'warning' },
  absent: { label: 'Absent', tone: 'danger' },
  on_leave: { label: 'On leave', tone: 'primary' },
  half_leave: { label: '½ leave', tone: 'primary' },
  holiday: { label: 'Holiday', tone: 'info' },
  week_off: { label: 'Week off', tone: 'info' },
  upcoming: { label: 'Scheduled', tone: 'info' },
  not_employed: { label: 'Not employed', tone: 'info' },
};

export function dayStatus(status: string): { label: string; tone: PillTone } {
  return DAY_STATUS[status] ?? { label: status, tone: 'info' };
}

const FLAG_LABEL: Readonly<Record<string, string>> = {
  auto_out: 'Closed automatically',
  past_shift_end: 'Out after shift end',
  worked_on_leave: 'Worked on leave',
  outside: 'Outside the arena',
  unknown: 'Location unknown',
  mock: 'Fake location',
  manual: 'Corrected',
  pending_review: 'Needs review',
  provisional: 'Still open',
};

export function dayFlagLabel(flag: string): string {
  return FLAG_LABEL[flag] ?? flag.replace(/_/g, ' ');
}

export function adjustmentLabel(kind: AdjustmentKind): string {
  return { bonus: 'Bonus', advance: 'Advance', deduction: 'Deduction', reversal: 'Reversal' }[kind];
}

export const NEW_ADJUSTMENT_KINDS: readonly {
  value: NewAdjustmentKind;
  label: string;
  sub: string;
}[] = [
  { value: 'bonus', label: 'Bonus', sub: 'Added to pay (festival bonus, incentive)' },
  { value: 'advance', label: 'Advance', sub: 'Taken off pay: money already given' },
  { value: 'deduction', label: 'Deduction', sub: 'Taken off pay (damage, shortage)' },
];

/** An adjustment has been undone by a reversal row. */
export function isReversed(a: SalaryAdjustment, all: readonly SalaryAdjustment[]): boolean {
  return all.some((x) => x.reversesId === a.id);
}

/** The days of the period each rate a line used covered ("1–15 Oct 2026", "16–31 Oct 2026"). */
export function rateSpans(
  rates: readonly RateUsed[],
  periodStart: string,
  periodEnd: string,
): { rate: RateUsed; first: string; last: string }[] {
  const sorted = [...rates].sort((a, b) => a.effectiveFrom.localeCompare(b.effectiveFrom));
  return sorted
    .map((rate, i) => {
      const first = rate.effectiveFrom > periodStart ? rate.effectiveFrom : periodStart;
      const next = sorted[i + 1]?.effectiveFrom;
      const last = next && next <= periodEnd ? addDays(next, -1) : periodEnd;
      return { rate, first, last };
    })
    .filter((s) => s.first <= s.last);
}

// ---------------------------------------------------------------- next period & checks

/** The longest period a run may cover (the server's `invalid_period`). */
export const MAX_RUN_DAYS = 62;

export interface Period {
  readonly first: string;
  readonly last: string;
}

/** The monthly cycle (starting on `startDay`) that contains `day`. */
export function monthlyCycleOf(day: string, startDay: number): Period {
  const [y, m, d] = day.split('-').map(Number);
  let year = y;
  let month = m;
  if (d < startDay) {
    month -= 1;
    if (month === 0) {
      month = 12;
      year -= 1;
    }
  }
  const first = `${year}-${String(month).padStart(2, '0')}-${String(startDay).padStart(2, '0')}`;
  const nextMonth = month === 12 ? 1 : month + 1;
  const nextYear = month === 12 ? year + 1 : year;
  const next = `${nextYear}-${String(nextMonth).padStart(2, '0')}-${String(startDay).padStart(2, '0')}`;
  return { first, last: addDays(next, -1) };
}

/** The week (starting on ISO weekday `weekStart`, 1 = Monday) that contains `day`. */
export function weekOf(day: string, weekStart: number): Period {
  const back = (isoWeekday(day) - weekStart + 7) % 7;
  const first = addDays(day, -back);
  return { first, last: addDays(first, 6) };
}

/**
 * The period a new draft suggests: the one right after the latest run that wasn't discarded;
 * with no run yet, the last complete period before today. Monthly from the cycle start day,
 * weekly from the week start (Working hours), custom: the 30 days after the last run (or the
 * previous calendar month).
 */
export function suggestNextPeriod(
  policy: PayPolicy,
  runs: readonly SalaryRun[],
  weekStart: number,
  today: string,
): Period {
  const live = runs.filter((r) => r.status !== 'discarded');
  const lastEnd =
    live
      .map((r) => r.periodEnd)
      .sort()
      .at(-1) ?? null;
  const cycle = (day: string): Period =>
    policy.periodKind === 'weekly'
      ? weekOf(day, weekStart)
      : monthlyCycleOf(day, policy.cycleStartDay);
  if (policy.periodKind === 'custom') {
    if (lastEnd) {
      const first = addDays(lastEnd, 1);
      return { first, last: addDays(first, 29) };
    }
    return monthlyCycleOf(addDays(monthlyCycleOf(today, 1).first, -1), 1);
  }
  if (lastEnd) {
    const after = addDays(lastEnd, 1);
    const c = cycle(after);
    // A run that ended mid-cycle: the rest of that cycle.
    return c.first === after ? c : { first: after, last: c.last };
  }
  const current = cycle(today);
  return cycle(addDays(current.first, -1));
}

/** Why a period can't be a new run (checked here before the server does), or null. */
export function newRunProblem(p: Period, runs: readonly SalaryRun[]): string | null {
  const span = daysBetween(p.first, p.last);
  if (Number.isNaN(span)) return 'Pick both dates';
  if (span < 0) return 'The first day is after the last';
  if (span + 1 > MAX_RUN_DAYS) return `A run covers at most ${MAX_RUN_DAYS} days`;
  const clash = runs.find(
    (r) => r.status !== 'discarded' && rangesOverlap(r.periodStart, r.periodEnd, p.first, p.last),
  );
  if (clash) {
    return `Overlaps the ${runStatus(clash.status).label.toLowerCase()} run for ${periodLabel(clash)}`;
  }
  return null;
}

/** The end of the latest finalised run (rates and rules must start after it), or null. */
export function lastFinalisedEnd(
  runs: readonly { status: RunStatus; periodEnd: string }[],
): string | null {
  return (
    runs
      .filter((r) => r.status === 'finalised')
      .map((r) => r.periodEnd)
      .sort()
      .at(-1) ?? null
  );
}

// ---------------------------------------------------------------- payloads

export function createRunPayload(id: string, p: Period): Record<string, unknown> {
  return { id, period_start: p.first, period_end: p.last };
}

export function setDeductionPayload(
  runId: string,
  staffId: string,
  code: DeductionCode,
  applied: boolean,
  note: string,
): Record<string, unknown> {
  const payload: Record<string, unknown> = { run_id: runId, staff_id: staffId, code, applied };
  const n = note.trim();
  if (n) payload['note'] = n;
  return payload;
}

/** salary_adjustment.add: the amount is always positive; the server signs it by kind. */
export function adjustmentPayload(
  id: string,
  runId: string,
  staffId: string,
  kind: NewAdjustmentKind,
  amountPaise: number,
  note: string,
): Record<string, unknown> {
  return {
    id,
    run_id: runId,
    staff_id: staffId,
    kind,
    amount_paise: Math.abs(Math.round(amountPaise)),
    note: note.trim(),
  };
}

export function reversePayload(
  id: string,
  reversesId: string,
  note: string,
): Record<string, unknown> {
  return { id, reverses_id: reversesId, note: note.trim() };
}

/** Refusals of the salary-run ops (docs/STAFF_API.md › Salary runs), in plain words. */
export const PAYROLL_MESSAGES: Readonly<Record<string, string>> = {
  forbidden:
    'You need the Payroll permission for that (finalising or discarding needs Finalise pay)',
  not_found: 'That run, person or adjustment is no longer there. Refresh',
  own_record: 'You can’t change your own pay line. The owner must',
  invalid_period: 'A run must end on or after its first day and cover at most 62 days',
  run_overlap: 'Another run already covers some of these dates',
  run_not_draft: 'This run is no longer a draft: finalised and discarded runs can’t change',
  period_not_over:
    'This period isn’t over yet. Finalise once its last shifts are over, or end the run today',
  entries_open:
    'Someone is still clocked in during this period. Close or correct their entry in Attendance first',
  entries_pending_review:
    'Some entries in this period still need review. Accept or correct them in Attendance first',
  note_required: 'Write a note saying what this is for',
  invalid_payload: 'Check the values and try again',
  already_reversed: 'That adjustment was already reversed',
  net_negative:
    'Someone’s net pay would be below zero. Waive a deduction or reverse an adjustment first',
};

/** The person whose net is below zero (for `net_negative`), from the run's lines. */
export function negativeNetNames(lines: readonly RunLine[]): string[] {
  return lines.filter((l) => l.netPaise < 0).map((l) => l.staffName);
}
