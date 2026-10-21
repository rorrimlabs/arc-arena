import { SampleShiftsApi, sampleShifts } from './shifts-api.sample';
import {
  ShiftAssignment,
  clockLabel,
  copyWindow,
  crossesMidnight,
  daysLabel,
  fromTimeValue,
  missingHolidays,
  overlappingAssignment,
  rosterRows,
  shiftLength,
  shiftPayload,
  shiftProblem,
  shiftSpan,
  shiftTimes,
  toTimeValue,
  weekOf,
} from './shifts.models';

const [morning, night] = sampleShifts();

describe('shifts', () => {
  it('words times of day and converts the time inputs', () => {
    expect(clockLabel(0)).toBe('12:00 AM');
    expect(clockLabel(540)).toBe('9:00 AM');
    expect(clockLabel(720)).toBe('12:00 PM');
    expect(clockLabel(1230)).toBe('8:30 PM');
    expect(toTimeValue(545)).toBe('09:05');
    expect(fromTimeValue('09:05')).toBe(545);
    expect(fromTimeValue('24:00')).toBeNull();
    expect(fromTimeValue('')).toBeNull();
  });

  it('a shift ending at or before its start crosses midnight', () => {
    expect(crossesMidnight(morning)).toBe(false);
    expect(shiftTimes(morning)).toBe('9:00 AM – 6:00 PM');
    expect(shiftSpan(morning)).toBe(540);
    expect(shiftLength(morning)).toBe(480);
    expect(crossesMidnight(night)).toBe(true);
    expect(shiftTimes(night)).toBe('6:00 PM → 2:00 AM next day');
    expect(shiftSpan(night)).toBe(480);
    expect(shiftLength(night)).toBe(450);
    // Same start and end: a 24-hour shift.
    expect(shiftSpan({ startMin: 600, endMin: 600 })).toBe(1440);
  });

  it('the upsert payload uses the contract keys, days sorted and unique', () => {
    expect(shiftPayload({ ...night, name: ' Night ', days: [7, 5, 6, 5] })).toEqual({
      id: 'sh2',
      name: 'Night',
      start_min: 1080,
      end_min: 120,
      days: [5, 6, 7],
      break_min: 30,
      active: true,
    });
  });

  it('checks a shift as the server would', () => {
    const others = sampleShifts();
    expect(shiftProblem(night, others)).toBeNull();
    expect(shiftProblem({ ...night, id: 'new', name: 'morning' }, others)).toBe(
      'Another shift already has that name',
    );
    expect(shiftProblem({ ...night, name: '  ' }, others)).toBe(
      'Enter a name of up to 60 characters',
    );
    expect(shiftProblem({ ...night, days: [] }, others)).toBe('Pick at least one day of the week');
    expect(shiftProblem({ ...night, breakMin: 480 }, others)).toBe(
      'The break must be shorter than the shift',
    );
    expect(shiftProblem({ ...night, breakMin: 720 }, others)).toBe(
      'The break must be a whole number of minutes from 0 to 719',
    );
    expect(shiftProblem({ ...night, startMin: Number.NaN }, others)).toBe(
      'Pick a start and an end time',
    );
  });

  it('words days of the week', () => {
    expect(daysLabel([1, 2, 3, 4, 5, 6, 7])).toBe('Every day');
    expect(daysLabel([1, 2, 3, 4, 5])).toBe('Mon–Fri');
    expect(daysLabel([5, 6, 7])).toBe('Fri–Sun');
    expect(daysLabel([1, 3, 5])).toBe('Mon, Wed, Fri');
    expect(daysLabel([6, 7])).toBe('Sat, Sun');
  });

  it('the same person and shift may not overlap; other shifts may (a split shift)', () => {
    const all: ShiftAssignment[] = [
      { id: 'a', staffId: 's1', shiftId: 'sh1', effectiveFrom: '2026-10-01', effectiveTo: null },
      {
        id: 'b',
        staffId: 's2',
        shiftId: 'sh1',
        effectiveFrom: '2026-01-01',
        effectiveTo: '2026-03-31',
      },
    ];
    const next = (over: Partial<ShiftAssignment>): ShiftAssignment => ({
      id: 'n',
      staffId: 's1',
      shiftId: 'sh1',
      effectiveFrom: '2026-09-01',
      effectiveTo: '2026-09-30',
      ...over,
    });
    expect(overlappingAssignment(next({}), all)).toBeUndefined();
    expect(overlappingAssignment(next({ effectiveTo: '2026-10-01' }), all)?.id).toBe('a');
    expect(overlappingAssignment(next({ effectiveTo: null }), all)?.id).toBe('a');
    expect(overlappingAssignment(next({ shiftId: 'sh2', effectiveTo: null }), all)).toBeUndefined();
    // Editing an assignment's own dates never clashes with itself.
    expect(overlappingAssignment({ ...all[0], effectiveFrom: '2026-09-01' }, all)).toBeUndefined();
    expect(
      overlappingAssignment(next({ staffId: 's2', effectiveFrom: '2026-03-31' }), all)?.id,
    ).toBe('b');
  });

  it('the roster lists the shifts worked each day of the Monday–Sunday week', async () => {
    const data = await new SampleShiftsApi().load();
    const days = weekOf('2026-10-15');
    expect(days).toEqual([
      '2026-10-12',
      '2026-10-13',
      '2026-10-14',
      '2026-10-15',
      '2026-10-16',
      '2026-10-17',
      '2026-10-18',
    ]);
    const rows = rosterRows(data, days);
    expect(rows.map((r) => r.staff.name)).toEqual(['Kavya Iyer', 'Priya Nair', 'Rohan Das']);
    // Kavya starts on the 14th; Morning is Mon–Sat.
    expect(rows[0].cells).toEqual([[], [], ['Morning'], ['Morning'], ['Morning'], ['Morning'], []]);
    // Night is Fri–Sun.
    expect(rows[2].cells).toEqual([[], [], [], [], ['Night'], ['Night'], ['Night']]);
  });

  it('copy from arena holidays offers only the days missing, within this month + 12', () => {
    expect(copyWindow('2026-10-15')).toEqual({ first: '2026-10-01', last: '2027-10-31' });
    expect(copyWindow('2026-12-03')).toEqual({ first: '2026-12-01', last: '2027-12-31' });
    expect(
      missingHolidays(
        [
          { day: '2026-12-25', name: 'Christmas' },
          { day: '2026-10-20', name: 'Diwali' },
          { day: '2026-11-05', name: 'Guru Nanak Jayanti' },
        ],
        [{ id: 'h1', day: '2026-10-20', name: 'Deepavali', paid: false }],
      ).map((h) => h.day),
    ).toEqual(['2026-11-05', '2026-12-25']);
  });
});
