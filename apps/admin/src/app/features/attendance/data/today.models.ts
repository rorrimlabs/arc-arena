import { PillTone } from '../../../shared/status-pill/status-pill';
import { AttendanceDay } from '../../calendar/data/calendar.models';
import { AttendanceEntry, LogRow } from './attendance.models';

/**
 * The Attendance screen's plain words for a person-day. Every figure and status comes from the
 * server (attendance_days, the same calculation the salary run uses); this only picks the words
 * an owner reads. Nobody is shown absent before the server says so: it judges a day only once
 * the person's shift has ended, and a day without a shift is a day off.
 */
export type DayWord =
  | 'working'
  | 'completed'
  | 'not_in'
  | 'upcoming'
  | 'absent'
  | 'on_leave'
  | 'day_off';

export interface DayLabel {
  readonly word: DayWord;
  readonly label: string;
  readonly tone: PillTone;
  /** A second, smaller note: "Late", "Half day", "Holiday: Diwali", "Half-day leave". */
  readonly note: string | null;
}

/**
 * The words for a person-day (`today`: the IST date now); null for a day they were not employed
 * (not listed).
 */
export function dayLabel(d: AttendanceDay, today: string): DayLabel | null {
  if (d.status === 'not_employed') return null;
  const late = d.late ? 'Late' : null;
  if (d.open) return { word: 'working', label: 'Working', tone: 'success', note: late };
  switch (d.status) {
    case 'present':
    case 'late':
      return { word: 'completed', label: 'Completed', tone: 'info', note: late };
    case 'half_day':
      return { word: 'completed', label: 'Completed', tone: 'warning', note: 'Half day' };
    case 'absent':
      return { word: 'absent', label: 'Absent', tone: 'danger', note: null };
    case 'on_leave':
      return { word: 'on_leave', label: 'On leave', tone: 'primary', note: leaveNote(d) };
    case 'half_leave':
      return d.workedMin > 0
        ? { word: 'completed', label: 'Completed', tone: 'info', note: 'Half-day leave' }
        : { word: 'on_leave', label: 'On leave', tone: 'primary', note: 'Half day' };
    case 'holiday':
    case 'week_off':
      if (d.workedMin > 0) {
        return { word: 'completed', label: 'Completed', tone: 'info', note: 'Worked a day off' };
      }
      return {
        word: 'day_off',
        label: 'Day off',
        tone: 'info',
        note: d.status === 'holiday' ? (d.holidayName ? `Holiday: ${d.holidayName}` : 'Holiday') : null,
      };
    default:
      // upcoming: a later day, or today before the shift has ended without a clock-in.
      if (d.schedMin <= 0) return { word: 'day_off', label: 'Day off', tone: 'info', note: null };
      return d.workDate > today
        ? { word: 'upcoming', label: 'Scheduled', tone: 'info', note: null }
        : { word: 'not_in', label: 'Not clocked in', tone: 'warning', note: null };
  }
}

function leaveNote(d: AttendanceDay): string | null {
  if (d.leavePaid > 0 && d.leaveLop > 0) return 'Part paid';
  if (d.leaveLop > 0) return 'Unpaid';
  return d.leavePaid > 0 ? 'Paid' : null;
}

/** One person's row for a day: the server's day, and their entries that day (newest last). */
export interface DayRow {
  readonly staffId: string;
  readonly staffName: string;
  readonly day: AttendanceDay;
  readonly label: DayLabel;
  readonly entries: readonly LogRow[];
  /** First clock-in and last clock-out of the day (null: none, or still on the clock). */
  readonly firstIn: string | null;
  readonly lastOut: string | null;
  /** Entries waiting for a reviewer. */
  readonly pending: number;
}

/** The people for one day, by name; days they were not employed are left out. */
export function dayRows(
  days: readonly AttendanceDay[],
  rows: readonly LogRow[],
  day: string,
  today: string,
): DayRow[] {
  const byStaff = new Map<string, LogRow[]>();
  for (const r of rows) {
    if (r.entry.workDate !== day || r.entry.status !== 'active') continue;
    const list = byStaff.get(r.entry.staffId) ?? [];
    list.push(r);
    byStaff.set(r.entry.staffId, list);
  }
  const out: DayRow[] = [];
  for (const d of days) {
    if (d.workDate !== day) continue;
    const label = dayLabel(d, today);
    if (!label) continue;
    const entries = (byStaff.get(d.staffId) ?? []).sort(
      (a, b) => Date.parse(a.entry.inAt) - Date.parse(b.entry.inAt),
    );
    const last = entries[entries.length - 1]?.entry;
    out.push({
      staffId: d.staffId,
      staffName: d.staffName,
      day: d,
      label,
      entries,
      firstIn: entries[0]?.entry.inAt ?? null,
      lastOut: last && last.outAt ? last.outAt : null,
      pending: entries.filter((r) => r.entry.review === 'pending').length,
    });
  }
  return out.sort((a, b) => a.staffName.localeCompare(b.staffName));
}

/** "3 working · 1 not clocked in · 1 on leave" counts for the summary line. */
export function dayCounts(rows: readonly DayRow[]): Record<DayWord, number> {
  const c: Record<DayWord, number> = {
    working: 0,
    completed: 0,
    not_in: 0,
    upcoming: 0,
    absent: 0,
    on_leave: 0,
    day_off: 0,
  };
  for (const r of rows) c[r.label.word]++;
  return c;
}

/**
 * Why an entry waits for review, in an owner's words: the most telling reason first. Location
 * reasons are left out while the arena does not check locations.
 */
export function reviewReason(e: AttendanceEntry, locationChecked: boolean): string {
  const f = new Set(e.flags);
  if (f.has('auto_out') || e.outSource === 'auto') return 'Clock-out missing: closed automatically';
  if ([...f].some((x) => x.startsWith('mock'))) return 'The phone reported a fake location';
  if (locationChecked && [...f].some((x) => x.startsWith('outside'))) {
    return f.has('outside_out') && !f.has('outside_in')
      ? 'Clock-out recorded outside the venue'
      : 'Clock-in recorded outside the venue';
  }
  if (locationChecked && [...f].some((x) => x.startsWith('unknown'))) {
    return 'Location could not be confirmed';
  }
  if (f.has('worked_on_leave')) return 'Worked on a leave day';
  if (f.has('past_shift_end')) return 'Clocked out long after the shift ended';
  return 'Attendance needs confirmation';
}

/** Flags worth showing to an owner (location ones only while locations are checked). */
export function visibleFlags(flags: readonly string[], locationChecked: boolean): string[] {
  return locationChecked
    ? [...flags]
    : flags.filter((f) => !/^(outside|unknown|low_accuracy|no_geofence)(_in|_out)?$/.test(f));
}
