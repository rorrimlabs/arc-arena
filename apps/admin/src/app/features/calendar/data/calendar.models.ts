import { PillTone } from '../../../shared/status-pill/status-pill';
import { addDays, istDayStartOf } from '../../../shared/time/ist';

/**
 * Staff › Calendar: one row per tracked staff member and one cell per IST day, from the read
 * RPC `attendance_days(p_arena, p_from, p_to)` (docs/STAFF_API.md). The server computes every
 * figure (the same function the salary run uses); this screen only arranges and words them.
 */
export type DayStatus =
  | 'present'
  | 'late'
  | 'half_day'
  | 'absent'
  | 'on_leave'
  | 'half_leave'
  | 'holiday'
  | 'week_off'
  | 'upcoming'
  | 'not_employed';

/** One person-day, as attendance_days returns it. Minutes are integers; units may be halves. */
export interface AttendanceDay {
  readonly staffId: string;
  readonly staffName: string;
  readonly workDate: string;
  readonly status: DayStatus;
  readonly schedMin: number;
  readonly workedMin: number;
  readonly regularMin: number;
  readonly extraMin: number;
  readonly late: boolean;
  readonly early: boolean;
  readonly presentUnits: number;
  readonly absentUnits: number;
  /** Worked enough for half a day only (the half-day threshold). */
  readonly halfDay: boolean;
  readonly leavePaid: number;
  readonly leaveLop: number;
  readonly holidayName: string | null;
  readonly flags: readonly string[];
  /** Still on the clock. */
  readonly open: boolean;
  /** How many active entries the day has (the log lists them). */
  readonly entries: number;
}

export interface StaffTotals {
  readonly present: number;
  readonly late: number;
  readonly halfDay: number;
  readonly absent: number;
  readonly leave: number;
  readonly workedMin: number;
  readonly extraMin: number;
}

export interface CalendarRow {
  readonly staffId: string;
  readonly staffName: string;
  /** One per day of the month, in order (null: the RPC returned nothing for that day). */
  readonly cells: readonly (AttendanceDay | null)[];
  readonly totals: StaffTotals;
}

type Row = Record<string, unknown>;

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

const STATUSES: readonly DayStatus[] = [
  'present',
  'late',
  'half_day',
  'absent',
  'on_leave',
  'half_leave',
  'holiday',
  'week_off',
  'upcoming',
  'not_employed',
];

/** One attendance_days row → a day. */
export function toAttendanceDay(r: Row): AttendanceDay {
  const status = String(r['status']) as DayStatus;
  return {
    staffId: String(r['staff_id']),
    staffName: String(r['staff_name'] ?? ''),
    workDate: String(r['work_date']),
    status: STATUSES.includes(status) ? status : 'upcoming',
    schedMin: num(r['sched_min']),
    workedMin: num(r['worked_min']),
    regularMin: num(r['regular_min']),
    extraMin: num(r['extra_min']),
    late: r['late'] === true,
    early: r['early'] === true,
    presentUnits: num(r['present_units']),
    absentUnits: num(r['absent_units']),
    halfDay: r['half_day'] === true,
    leavePaid: num(r['leave_paid']),
    leaveLop: num(r['leave_lop']),
    holidayName: r['holiday_name'] ? String(r['holiday_name']) : null,
    flags: (r['flags'] as string[] | null) ?? [],
    open: r['open'] === true,
    entries: Math.max(0, Math.round(num(r['entries']))),
  };
}

/** The chip a status gets: a short mark, its words and a tone. */
export interface StatusChip {
  readonly mark: string;
  readonly label: string;
  readonly tone: PillTone;
}

const CHIPS: Readonly<Record<DayStatus, StatusChip>> = {
  present: { mark: '✓', label: 'present', tone: 'success' },
  late: { mark: 'L', label: 'late', tone: 'warning' },
  half_day: { mark: '½', label: 'half day', tone: 'warning' },
  absent: { mark: 'A', label: 'absent', tone: 'danger' },
  on_leave: { mark: 'Lv', label: 'on leave', tone: 'primary' },
  half_leave: { mark: '½Lv', label: 'half-day leave', tone: 'primary' },
  holiday: { mark: 'H', label: 'holiday', tone: 'info' },
  week_off: { mark: '–', label: 'week off', tone: 'info' },
  upcoming: { mark: '·', label: 'upcoming', tone: 'info' },
  not_employed: { mark: '', label: 'not employed', tone: 'info' },
};

export function statusChip(status: DayStatus): StatusChip {
  return CHIPS[status] ?? CHIPS.upcoming;
}

/** The legend, in the order a month reads. */
export const LEGEND: readonly (StatusChip & { status: DayStatus })[] = (
  [
    'present',
    'late',
    'half_day',
    'absent',
    'on_leave',
    'half_leave',
    'holiday',
    'week_off',
    'upcoming',
  ] as const
).map((status) => ({ status, ...CHIPS[status] }));

/** 485 → "8 h 05 m"; 45 → "0 h 45 m". */
export function hoursLong(minutes: number): string {
  const m = Math.max(0, Math.round(minutes));
  return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} m`;
}

/** 90 → "1.5h", 60 → "1h", 20 → "20m": the small extra-hours note in a cell. */
export function extraShort(minutes: number): string {
  if (minutes < 60) return `${Math.round(minutes)}m`;
  const h = Math.round((minutes / 60) * 10) / 10;
  return `${h}h`;
}

/** 12.5 → "12½", 0.5 → "½", 3 → "3". */
export function units(n: number): string {
  const whole = Math.floor(n);
  const half = Math.round((n - whole) * 2) === 1;
  if (!half) return String(Math.round(n));
  return whole ? `${whole}½` : '½';
}

const cellDay = new Intl.DateTimeFormat('en-IN', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: 'UTC',
});

/** 0 → "No entries", 1 → "1 entry", 2 → "2 entries". */
export function entriesLabel(n: number): string {
  if (!n) return 'No entries';
  return n === 1 ? '1 entry' : `${n} entries`;
}

/** "2026-10-15" → "Thu 15 Oct". */
export function cellDate(day: string): string {
  return cellDay.format(new Date(`${day}T00:00:00Z`)).replace(',', '');
}

/** "Ravi, Thu 15 Oct: present, 8 h 05 m, 1 h 00 m extra" — what a screen reader hears. */
export function cellLabel(name: string, day: string, d: AttendanceDay | null): string {
  const head = `${name}, ${cellDate(day)}`;
  if (!d) return `${head}: no figures`;
  if (d.status === 'not_employed') return `${head}: not employed`;
  const parts = [statusChip(d.status).label];
  if (d.holidayName && d.status === 'holiday') parts[0] = `holiday (${d.holidayName})`;
  if (d.workedMin > 0 || ['present', 'late', 'half_day'].includes(d.status)) {
    parts.push(hoursLong(d.workedMin));
  }
  if (d.halfDay && d.status !== 'half_day') parts.push('half day');
  if (d.extraMin > 0) parts.push(`${hoursLong(d.extraMin)} extra`);
  if (d.open) parts.push('still on the clock');
  return `${head}: ${parts.join(', ')}`;
}

/**
 * The person's totals for the month (units from the server, so halves add up). Days before
 * they joined or after they left (`not_employed`) count for nothing.
 */
export function staffTotals(days: readonly AttendanceDay[]): StaffTotals {
  const t = { present: 0, late: 0, halfDay: 0, absent: 0, leave: 0, workedMin: 0, extraMin: 0 };
  for (const d of days) {
    if (d.status === 'not_employed') continue;
    t.present += d.presentUnits;
    if (d.late) t.late++;
    if (d.halfDay || d.status === 'half_day') t.halfDay++;
    t.absent += d.absentUnits;
    t.leave += d.leavePaid + d.leaveLop;
    t.workedMin += d.workedMin;
    t.extraMin += d.extraMin;
  }
  return t;
}

/** The days → one row per person (by name), one cell per day of `days`. */
export function calendarRows(rows: readonly AttendanceDay[], days: readonly string[]): CalendarRow[] {
  const byStaff = new Map<string, AttendanceDay[]>();
  for (const r of rows) {
    const list = byStaff.get(r.staffId) ?? [];
    list.push(r);
    byStaff.set(r.staffId, list);
  }
  return [...byStaff.entries()]
    .map(([staffId, list]) => {
      const byDay = new Map(list.map((d) => [d.workDate, d]));
      return {
        staffId,
        staffName: list[0].staffName,
        cells: days.map((day) => byDay.get(day) ?? null),
        totals: staffTotals(list.filter((d) => days.includes(d.workDate))),
      };
    })
    .sort((a, b) => a.staffName.localeCompare(b.staffName));
}

/** "2026-10" → the IST days 1…31 of that month; null when not a month. */
export function monthDays(month: string): string[] | null {
  const m = /^(\d{4})-(\d{2})$/.exec(month);
  if (!m || +m[2] < 1 || +m[2] > 12) return null;
  const first = `${month}-01`;
  if (!istDayStartOf(first)) return null;
  const days = [first];
  for (;;) {
    const next = addDays(days[days.length - 1], 1);
    if (!next.startsWith(month)) return days;
    days.push(next);
  }
}

/** "2026-10" ± n months. */
export function shiftMonth(month: string, n: number): string {
  const [y, m] = month.split('-').map(Number);
  const index = y * 12 + (m - 1) + n;
  return `${Math.floor(index / 12)}-${String((index % 12) + 1).padStart(2, '0')}`;
}

const monthName = new Intl.DateTimeFormat('en-IN', {
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});

/** "2026-10" → "October 2026". */
export function monthLabel(month: string): string {
  return monthName.format(new Date(`${month}-01T00:00:00Z`));
}
