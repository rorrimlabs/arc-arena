import { addDays } from '../../../shared/time/ist';
import { isoWeekday } from '../../shifts/data/shifts.models';
import { CalendarApi } from './calendar-api';
import { AttendanceDay } from './calendar.models';

/** The sample "today" (page-test NOW is 13 Oct 2026, 7:30 pm IST): later days are upcoming. */
const TODAY = '2026-10-13';

function day(staffId: string, staffName: string, workDate: string): AttendanceDay {
  const base: AttendanceDay = {
    staffId,
    staffName,
    workDate,
    status: 'present',
    schedMin: 480,
    workedMin: 480,
    regularMin: 480,
    extraMin: 0,
    late: false,
    early: false,
    presentUnits: 1,
    absentUnits: 0,
    halfDay: false,
    leavePaid: 0,
    leaveLop: 0,
    holidayName: null,
    flags: [],
    open: false,
    entries: 1,
  };
  const zero = { ...base, schedMin: 0, workedMin: 0, regularMin: 0, presentUnits: 0, entries: 0 };
  if (staffId === 's2' && workDate < '2026-10-02') return { ...zero, status: 'not_employed' };
  if (workDate > TODAY) return { ...zero, status: 'upcoming', schedMin: 480 };
  if (isoWeekday(workDate) === 7) return { ...zero, status: 'week_off' };
  const special = OVERRIDES[`${staffId}|${workDate}`];
  return special ? { ...base, ...special } : base;
}

const OVERRIDES: Readonly<Record<string, Partial<AttendanceDay>>> = {
  's1|2026-10-05': { status: 'late', late: true, workedMin: 470, regularMin: 470 },
  's1|2026-10-06': {
    status: 'half_day',
    halfDay: true,
    workedMin: 240,
    regularMin: 240,
    presentUnits: 0.5,
    absentUnits: 0.5,
  },
  's1|2026-10-07': {
    status: 'absent',
    workedMin: 0,
    regularMin: 0,
    presentUnits: 0,
    absentUnits: 1,
    entries: 0,
  },
  's1|2026-10-08': {
    workedMin: 545,
    extraMin: 65,
    entries: 2,
  },
  's1|2026-10-13': { workedMin: 600, regularMin: 480, extraMin: 120, open: true },
  's2|2026-10-02': {
    status: 'holiday',
    holidayName: 'Gandhi Jayanti',
    schedMin: 0,
    workedMin: 0,
    regularMin: 0,
    presentUnits: 0,
    entries: 0,
  },
  's2|2026-10-09': {
    status: 'on_leave',
    workedMin: 0,
    regularMin: 0,
    presentUnits: 0,
    leavePaid: 1,
    entries: 0,
  },
  's2|2026-10-12': {
    status: 'half_leave',
    workedMin: 240,
    regularMin: 240,
    presentUnits: 0.5,
    leavePaid: 0.5,
  },
};

/**
 * Deterministic attendance_days for tests: Priya and Rohan (who joined on 2 Oct), every day
 * asked.
 */
export class SampleCalendarApi extends CalendarApi {
  staff = [
    { id: 's2', name: 'Rohan Das' },
    { id: 's1', name: 'Priya Nair' },
  ];
  /** Every read, as [first, last]. */
  readonly reads: [string, string][] = [];

  async days(_arenaId: string, first: string, last: string): Promise<AttendanceDay[]> {
    this.reads.push([first, last]);
    const out: AttendanceDay[] = [];
    for (const s of this.staff) {
      for (let d = first; d <= last; d = addDays(d, 1)) out.push(day(s.id, s.name, d));
    }
    return out;
  }
}
