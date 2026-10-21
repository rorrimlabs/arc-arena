import { SampleCalendarApi } from './calendar-api.sample';
import {
  AttendanceDay,
  calendarRows,
  cellLabel,
  entriesLabel,
  extraShort,
  hoursLong,
  monthDays,
  shiftMonth,
  staffTotals,
  statusChip,
  toAttendanceDay,
  units,
} from './calendar.models';

describe('calendar', () => {
  it('reads an attendance_days row', () => {
    const d = toAttendanceDay({
      staff_id: 's1',
      staff_name: 'Ravi',
      work_date: '2026-10-15',
      status: 'late',
      sched_min: 480,
      worked_min: 485,
      regular_min: 480,
      extra_min: 5,
      late: true,
      early: false,
      present_units: 1,
      absent_units: 0,
      half_day: false,
      leave_paid: '0.5',
      leave_lop: 0,
      holiday_name: null,
      flags: ['outside_in'],
      open: false,
      entries: 2,
    });
    expect(d).toMatchObject({
      staffId: 's1',
      status: 'late',
      workedMin: 485,
      extraMin: 5,
      late: true,
      leavePaid: 0.5,
      halfDay: false,
      flags: ['outside_in'],
      entries: 2,
    });
    expect(toAttendanceDay({ status: 'half_day', half_day: true }).halfDay).toBe(true);
    expect(toAttendanceDay({ status: 'absent' }).entries).toBe(0);
    expect(toAttendanceDay({ status: 'something_new' }).status).toBe('upcoming');
  });

  it('maps each status to a compact chip', () => {
    expect(
      (
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
          'not_employed',
        ] as const
      ).map((s) => statusChip(s).mark),
    ).toEqual(['✓', 'L', '½', 'A', 'Lv', '½Lv', 'H', '–', '·', '']);
    expect(statusChip('absent').tone).toBe('danger');
  });

  it('words a cell for screen readers', () => {
    const d = { status: 'present', workedMin: 485, extraMin: 0, open: false } as AttendanceDay;
    expect(cellLabel('Ravi', '2026-10-15', d)).toBe('Ravi, Thu 15 Oct: present, 8 h 05 m');
    expect(cellLabel('Ravi', '2026-10-15', { ...d, extraMin: 60 })).toBe(
      'Ravi, Thu 15 Oct: present, 8 h 05 m, 1 h 00 m extra',
    );
    expect(
      cellLabel('Ravi', '2026-10-02', {
        ...d,
        status: 'holiday',
        workedMin: 0,
        holidayName: 'Gandhi Jayanti',
      }),
    ).toBe('Ravi, Fri 2 Oct: holiday (Gandhi Jayanti)');
    expect(cellLabel('Ravi', '2026-10-04', { ...d, status: 'week_off', workedMin: 0 })).toBe(
      'Ravi, Sun 4 Oct: week off',
    );
    expect(cellLabel('Ravi', '2026-10-15', null)).toBe('Ravi, Thu 15 Oct: no figures');
    expect(cellLabel('Ravi', '2026-10-01', { ...d, status: 'not_employed', workedMin: 0 })).toBe(
      'Ravi, Thu 1 Oct: not employed',
    );
    expect(entriesLabel(0)).toBe('No entries');
    expect(entriesLabel(1)).toBe('1 entry');
    expect(entriesLabel(2)).toBe('2 entries');
  });

  it('formats hours, extra hours and half units', () => {
    expect(hoursLong(485)).toBe('8 h 05 m');
    expect(hoursLong(45)).toBe('0 h 45 m');
    expect(extraShort(20)).toBe('20m');
    expect(extraShort(60)).toBe('1h');
    expect(extraShort(65)).toBe('1.1h');
    expect(units(12.5)).toBe('12½');
    expect(units(0.5)).toBe('½');
    expect(units(3)).toBe('3');
  });

  it('a month is its IST days; months step across years', () => {
    expect(monthDays('2026-10')).toHaveLength(31);
    expect(monthDays('2026-02')?.at(-1)).toBe('2026-02-28');
    expect(monthDays('2028-02')?.at(-1)).toBe('2028-02-29');
    expect(monthDays('2026-13')).toBeNull();
    expect(shiftMonth('2026-12', 1)).toBe('2027-01');
    expect(shiftMonth('2026-01', -1)).toBe('2025-12');
  });

  it('one row per person by name, with the month’s totals from the server’s units', async () => {
    const days = monthDays('2026-10')!;
    const rows = calendarRows(await new SampleCalendarApi().days('a1', days[0], days[30]), days);
    expect(rows.map((r) => r.staffName)).toEqual(['Priya Nair', 'Rohan Das']);
    expect(rows[0].cells).toHaveLength(31);
    // Priya, 1–13 Oct: 11 working days (two Sundays off): 6 plain, then late, half, absent,
    // a long day and today (on the clock).
    expect(rows[0].totals).toEqual({
      present: 9.5,
      late: 1,
      halfDay: 1,
      absent: 1.5,
      leave: 0,
      workedMin: 6 * 480 + 470 + 240 + 545 + 600,
      extraMin: 65 + 120,
    });
    // Rohan joined on the 2nd (the 1st is not employed: no units, no hours), then a holiday,
    // a day of leave and a half day of leave.
    expect(rows[1].cells[0]?.status).toBe('not_employed');
    expect(rows[1].totals).toMatchObject({ present: 7.5, absent: 0, leave: 1.5 });
  });

  it('totals add every day passed', () => {
    const d = (over: Partial<AttendanceDay>) =>
      ({
        presentUnits: 0,
        absentUnits: 0,
        leavePaid: 0,
        leaveLop: 0,
        workedMin: 0,
        extraMin: 0,
        late: false,
        halfDay: false,
        status: 'present',
        ...over,
      }) as AttendanceDay;
    expect(
      staffTotals([
        d({ presentUnits: 1, workedMin: 500, extraMin: 20, late: true }),
        d({ status: 'half_day', presentUnits: 0.5, absentUnits: 0.5, workedMin: 240 }),
        d({ status: 'on_leave', leaveLop: 1 }),
        // Not employed that day: counts for nothing, whatever it carries.
        d({ status: 'not_employed', presentUnits: 1, absentUnits: 1, workedMin: 60, late: true }),
        // The half_day flag counts even when the day's status is something else.
        d({ status: 'late', halfDay: true, late: true }),
      ]),
    ).toEqual({
      present: 1.5,
      late: 2,
      halfDay: 2,
      absent: 0.5,
      leave: 1,
      workedMin: 740,
      extraMin: 20,
    });
  });
});
