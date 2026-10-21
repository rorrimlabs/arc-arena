import { addDays, istDayStartOf } from '../../../shared/time/ist';
import { WEEKDAYS } from '../../settings/data/work-hours';

/**
 * Shifts, who works them and the staff holidays (docs/STAFF_API.md: `shifts`, `staff_shifts`,
 * `staff_holidays`). Times are minutes after IST midnight (0–1439); a shift whose end is at or
 * before its start ends the next day. Days are IST dates ("2026-10-15") and ISO weekdays
 * (1 = Monday … 7 = Sunday).
 */
export interface Shift {
  readonly id: string;
  readonly name: string;
  readonly startMin: number;
  readonly endMin: number;
  /** ISO weekdays, ascending. */
  readonly days: readonly number[];
  /** Unpaid break, minutes. */
  readonly breakMin: number;
  readonly active: boolean;
}

/** One person on one shift from `effectiveFrom` to `effectiveTo` (inclusive; null = open-ended). */
export interface ShiftAssignment {
  readonly id: string;
  readonly staffId: string;
  readonly shiftId: string;
  readonly effectiveFrom: string;
  readonly effectiveTo: string | null;
}

export interface StaffHoliday {
  readonly id: string;
  readonly day: string;
  readonly name: string;
  readonly paid: boolean;
}

/** A staff profile as these screens name it. */
export interface StaffName {
  readonly id: string;
  readonly name: string;
  readonly active: boolean;
}

/** An arena holiday from the price list (`holidays`), offered as a staff holiday. */
export interface ArenaHoliday {
  readonly day: string;
  readonly name: string;
}

export interface ShiftsData {
  readonly shifts: readonly Shift[];
  readonly assignments: readonly ShiftAssignment[];
  readonly holidays: readonly StaffHoliday[];
  readonly staff: readonly StaffName[];
}

export const MINUTES_PER_DAY = 1440;
export const MAX_BREAK_MIN = 719;
export const MAX_SHIFT_NAME = 60;

/** Refusals of the shift, assignment and staff-holiday ops, in plain words. */
export const SHIFT_MESSAGES: Readonly<Record<string, string>> = {
  invalid_shift: 'Check the shift: a name, start and end times, at least one day and a break shorter than the shift',
  duplicate: 'Another shift already has that name',
  assignment_overlap:
    'They already have this shift for some of those dates. Change the dates, or edit the other assignment',
  not_found: 'That is no longer there. Refresh',
  invalid_payload: 'Check the values and try again',
  forbidden: 'You need the Settings permission for that',
  shift_in_use:
    'People are still on this shift from today on. End their assignments first, then turn it off',
  shift_inactive: 'This shift is not in use. Turn it back on before putting anyone on it',
  period_finalised:
    'Pay for some of those days is already finalised, so the roster for them can’t change. Pick later dates',
};

/** 540 → "9:00 AM", 0 → "12:00 AM", 1230 → "8:30 PM". */
export function clockLabel(min: number): string {
  const m = ((min % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  const h = Math.floor(m / 60);
  const mm = String(m % 60).padStart(2, '0');
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${mm} ${h < 12 ? 'AM' : 'PM'}`;
}

/** 540 → "09:00" (an `<input type="time">` value). */
export function toTimeValue(min: number): string {
  return `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;
}

/** "09:00" → 540; null when not a time of day. */
export function fromTimeValue(value: string): number | null {
  const m = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(value.trim());
  if (!m) return null;
  const h = +m[1];
  const mm = +m[2];
  return h < 24 && mm < 60 ? h * 60 + mm : null;
}

/** The shift ends the next day (end at or before start). */
export function crossesMidnight(s: Pick<Shift, 'startMin' | 'endMin'>): boolean {
  return s.endMin <= s.startMin;
}

/** Start to end, in minutes (a shift ending at its own start time lasts 24 h). */
export function shiftSpan(s: Pick<Shift, 'startMin' | 'endMin'>): number {
  return crossesMidnight(s) ? MINUTES_PER_DAY - s.startMin + s.endMin : s.endMin - s.startMin;
}

/** Paid length: start to end minus the unpaid break. */
export function shiftLength(s: Pick<Shift, 'startMin' | 'endMin' | 'breakMin'>): number {
  return Math.max(0, shiftSpan(s) - s.breakMin);
}

/** "9:00 AM – 6:00 PM", or "6:00 PM → 2:00 AM next day". */
export function shiftTimes(s: Pick<Shift, 'startMin' | 'endMin'>): string {
  return crossesMidnight(s)
    ? `${clockLabel(s.startMin)} → ${clockLabel(s.endMin)} next day`
    : `${clockLabel(s.startMin)} – ${clockLabel(s.endMin)}`;
}

/** [1..7] → "Every day", [1..5] → "Mon–Fri", [6,7] → "Sat–Sun", [1,3,5] → "Mon, Wed, Fri". */
export function daysLabel(days: readonly number[]): string {
  const sorted = [...new Set(days)].sort((a, b) => a - b);
  if (!sorted.length) return 'No days';
  if (sorted.length === 7) return 'Every day';
  const short = (d: number) => WEEKDAYS[d - 1]?.short ?? String(d);
  const run = sorted.every((d, i) => i === 0 || d === sorted[i - 1] + 1);
  if (run && sorted.length >= 3) return `${short(sorted[0])}–${short(sorted[sorted.length - 1])}`;
  return sorted.map(short).join(', ');
}

/** The ISO weekday (1 = Monday … 7 = Sunday) of an IST date. */
export function isoWeekday(day: string): number {
  const [y, m, d] = day.split('-').map(Number);
  const w = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return w === 0 ? 7 : w;
}

/** A shift as the `shift.upsert` payload (days sorted and unique). */
export function shiftPayload(s: Shift): Record<string, unknown> {
  return {
    id: s.id,
    name: s.name.trim(),
    start_min: s.startMin,
    end_min: s.endMin,
    days: [...new Set(s.days)].sort((a, b) => a - b),
    break_min: s.breakMin,
    active: s.active,
  };
}

/** What the server would refuse in a shift, in plain words (null when none). */
export function shiftProblem(s: Shift, others: readonly Shift[]): string | null {
  const name = s.name.trim();
  if (!name || name.length > MAX_SHIFT_NAME) {
    return `Enter a name of up to ${MAX_SHIFT_NAME} characters`;
  }
  if (others.some((o) => o.id !== s.id && o.name.trim().toLowerCase() === name.toLowerCase())) {
    return SHIFT_MESSAGES['duplicate'];
  }
  const inDay = (n: number) => Number.isInteger(n) && n >= 0 && n < MINUTES_PER_DAY;
  if (!inDay(s.startMin) || !inDay(s.endMin)) return 'Pick a start and an end time';
  if (!s.days.length) return 'Pick at least one day of the week';
  if (!Number.isInteger(s.breakMin) || s.breakMin < 0 || s.breakMin > MAX_BREAK_MIN) {
    return `The break must be a whole number of minutes from 0 to ${MAX_BREAK_MIN}`;
  }
  if (s.breakMin >= shiftSpan(s)) return 'The break must be shorter than the shift';
  return null;
}

/** An assignment as the `shift.assign` payload (an open end is sent as null). */
export function assignPayload(a: ShiftAssignment): Record<string, unknown> {
  return {
    id: a.id,
    staff_id: a.staffId,
    shift_id: a.shiftId,
    effective_from: a.effectiveFrom,
    effective_to: a.effectiveTo,
  };
}

/** Two inclusive date ranges share a day (null end = open-ended). */
export function rangesOverlap(
  a: Pick<ShiftAssignment, 'effectiveFrom' | 'effectiveTo'>,
  b: Pick<ShiftAssignment, 'effectiveFrom' | 'effectiveTo'>,
): boolean {
  const aEndsBeforeB = a.effectiveTo !== null && a.effectiveTo < b.effectiveFrom;
  const bEndsBeforeA = b.effectiveTo !== null && b.effectiveTo < a.effectiveFrom;
  return !aEndsBeforeB && !bEndsBeforeA;
}

/** Another assignment of the same person and shift whose dates overlap `a` (as the server checks). */
export function overlappingAssignment(
  a: ShiftAssignment,
  all: readonly ShiftAssignment[],
): ShiftAssignment | undefined {
  return all.find(
    (o) =>
      o.id !== a.id && o.staffId === a.staffId && o.shiftId === a.shiftId && rangesOverlap(a, o),
  );
}

/** The assignment covers `day` (inclusive). */
export function coversDay(a: ShiftAssignment, day: string): boolean {
  return a.effectiveFrom <= day && (a.effectiveTo === null || a.effectiveTo >= day);
}

const longDay = new Intl.DateTimeFormat('en-IN', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  timeZone: 'UTC',
});
const shortDay = new Intl.DateTimeFormat('en-IN', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: 'UTC',
});

/** "2026-10-15" → "15 Oct 2026" (already an IST date: no zone shift). */
export function formatDay(day: string): string {
  return longDay.format(new Date(`${day}T00:00:00Z`));
}

/** "2026-10-15" → "Thu, 15 Oct". */
export function formatWeekday(day: string): string {
  return shortDay.format(new Date(`${day}T00:00:00Z`));
}

/** "From 1 Oct 2026 · no end date" or "1 Oct 2026 – 31 Dec 2026". */
export function assignmentDates(a: Pick<ShiftAssignment, 'effectiveFrom' | 'effectiveTo'>): string {
  return a.effectiveTo
    ? `${formatDay(a.effectiveFrom)} – ${formatDay(a.effectiveTo)}`
    : `From ${formatDay(a.effectiveFrom)} · no end date`;
}

/** The seven IST dates of the Monday-to-Sunday week containing `day`. */
export function weekOf(day: string): string[] {
  const monday = addDays(day, 1 - isoWeekday(day));
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
}

export interface RosterRow {
  readonly staff: StaffName;
  /** Per day of the week: the names of the shifts worked that day (empty: week off). */
  readonly cells: readonly (readonly string[])[];
}

/**
 * The weekly roster: one row per active staff member (and anyone inactive still assigned that
 * week), one cell per day listing the active shifts whose assignment covers the day and whose
 * weekdays include it. Read-only; derived from assignments and shift days only.
 */
export function rosterRows(data: ShiftsData, days: readonly string[]): RosterRow[] {
  const shifts = new Map(data.shifts.map((s) => [s.id, s]));
  return data.staff
    .map((staff) => {
      const mine = data.assignments.filter((a) => a.staffId === staff.id);
      const cells = days.map((day) => {
        const weekday = isoWeekday(day);
        return mine
          .filter((a) => coversDay(a, day))
          .map((a) => shifts.get(a.shiftId))
          .filter((s): s is Shift => !!s && s.active && s.days.includes(weekday))
          .sort((a, b) => a.startMin - b.startMin)
          .map((s) => s.name);
      });
      return { staff, cells };
    })
    .filter((r) => r.staff.active || r.cells.some((c) => c.length))
    .sort((a, b) => a.staff.name.localeCompare(b.staff.name));
}

/** The arena holidays not yet staff holidays (by day), in date order. */
export function missingHolidays(
  arena: readonly ArenaHoliday[],
  staff: readonly StaffHoliday[],
): ArenaHoliday[] {
  const have = new Set(staff.map((h) => h.day));
  return [...arena].filter((h) => !have.has(h.day)).sort((a, b) => a.day.localeCompare(b.day));
}

/**
 * The days "Copy from arena holidays" looks at: the first of this IST month to the last day of
 * the twelfth month after it.
 */
export function copyWindow(today: string): { first: string; last: string } {
  const [y, m] = today.split('-').map(Number);
  const first = `${y}-${String(m).padStart(2, '0')}-01`;
  // The month after the window's last one (m is 1-based: m + 12 is its 0-based index).
  const after = m + 12;
  const ey = y + Math.floor(after / 12);
  const em = (after % 12) + 1;
  const nextFirst = `${ey}-${String(em).padStart(2, '0')}-01`;
  return { first, last: addDays(nextFirst, -1) };
}

/** True for a real "YYYY-MM-DD" date. */
export function isDay(day: string): boolean {
  return istDayStartOf(day) !== null;
}
