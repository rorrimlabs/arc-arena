import {
  DEFAULT_WORK_HOURS,
  WorkHoursDraft,
  draftStandardDay,
  fromWorkHoursDraft,
  parseWorkHours,
  sameWorkHoursDraft,
  toWorkHoursDraft,
  workHoursJson,
  workHoursProblems,
  workHoursSummary,
} from './work-hours';

const draft: WorkHoursDraft = toWorkHoursDraft(DEFAULT_WORK_HOURS);

describe('working hours', () => {
  it('reads the server defaults when nothing is saved, and a saved row as saved', () => {
    expect(parseWorkHours(null)).toEqual(DEFAULT_WORK_HOURS);
    expect(
      parseWorkHours({
        late_grace_min: 5,
        early_leave_min: 30,
        break_after_min: 240,
        rounding: 'nearest_15',
        full_day_pct: 80,
        half_day_pct: 50,
        standard_day_min: 510,
        extra_basis: 'week',
        week_start: 7,
        auto_out_after_min: 60,
      }),
    ).toEqual({
      lateGraceMin: 5,
      earlyLeaveMin: 30,
      breakAfterMin: 240,
      rounding: 'nearest_15',
      fullDayPct: 80,
      halfDayPct: 50,
      standardDayMin: 510,
      extraBasis: 'week',
      weekStart: 7,
      autoOutAfterMin: 60,
    });
    // Out of range or a half day not below the full day reads as the default.
    const odd = parseWorkHours({ late_grace_min: 500, full_day_pct: 40, half_day_pct: 60 });
    expect(odd.lateGraceMin).toBe(10);
    expect([odd.fullDayPct, odd.halfDayPct]).toEqual([75, 40]);
  });

  it('the draft shows the standard day as hours and minutes', () => {
    expect(draft.standardHours).toBe('8');
    expect(draft.standardMinutes).toBe('0');
    expect(draftStandardDay({ ...draft, standardHours: '8', standardMinutes: '30' })).toBe(510);
    expect(draftStandardDay({ ...draft, standardHours: '9', standardMinutes: '' })).toBe(540);
    expect(draftStandardDay({ ...draft, standardMinutes: '60' })).toBeNaN();
  });

  it('saves the whole object: exactly the ten keys the server requires', () => {
    const w = fromWorkHoursDraft({
      ...draft,
      lateGrace: '5',
      rounding: 'down_15',
      standardHours: '8',
      standardMinutes: '30',
      extraBasis: 'week',
      weekStart: 7,
    })!;
    expect(workHoursJson(w)).toEqual({
      late_grace_min: 5,
      early_leave_min: 15,
      break_after_min: 300,
      rounding: 'down_15',
      full_day_pct: 75,
      half_day_pct: 40,
      standard_day_min: 510,
      extra_basis: 'week',
      week_start: 7,
      auto_out_after_min: 120,
    });
    expect(parseWorkHours(workHoursJson(w))).toEqual(w);
  });

  it('mirrors the server ranges', () => {
    expect(workHoursProblems(draft)).toEqual({});
    expect(workHoursProblems({ ...draft, lateGrace: '121' }).lateGrace).toBe(
      'Late grace must be a whole number of minutes from 0 to 120',
    );
    expect(workHoursProblems({ ...draft, lateGrace: '120' }).lateGrace).toBeUndefined();
    expect(workHoursProblems({ ...draft, earlyLeave: '241' }).earlyLeave).toBeDefined();
    expect(workHoursProblems({ ...draft, breakAfter: '1441' }).breakAfter).toBeDefined();
    expect(workHoursProblems({ ...draft, breakAfter: '0' }).breakAfter).toBeUndefined();
    expect(workHoursProblems({ ...draft, autoOutAfter: '721' }).autoOutAfter).toBe(
      'Auto clock-out grace must be a whole number of minutes from 0 to 720',
    );
    expect(workHoursProblems({ ...draft, fullDayPct: '101' }).fullDayPct).toBe(
      'Full day must be a whole percentage from 1 to 100',
    );
    expect(workHoursProblems({ ...draft, halfDayPct: '0' }).halfDayPct).toBe(
      'Half day must be a whole percentage from 1 to 99',
    );
    expect(workHoursProblems({ ...draft, halfDayPct: '75' }).halfDayPct).toBe(
      'Half day must be less than full day',
    );
    expect(
      workHoursProblems({ ...draft, standardHours: '0', standardMinutes: '59' }).standardDay,
    ).toBe('The standard day must be from 1 hour to 24 hours (minutes 0–59)');
    expect(
      workHoursProblems({ ...draft, standardHours: '24', standardMinutes: '1' }).standardDay,
    ).toBeDefined();
    expect(
      workHoursProblems({ ...draft, standardHours: '24', standardMinutes: '0' }).standardDay,
    ).toBeUndefined();
    expect(workHoursProblems({ ...draft, lateGrace: '2.5' }).lateGrace).toBeDefined();
    expect(fromWorkHoursDraft({ ...draft, halfDayPct: '90' })).toBeNull();
  });

  it('compares drafts by value', () => {
    expect(sameWorkHoursDraft(draft, { ...draft, lateGrace: '10.0' })).toBe(true);
    expect(sameWorkHoursDraft(draft, { ...draft, standardMinutes: '' })).toBe(true);
    expect(sameWorkHoursDraft(draft, { ...draft, weekStart: 2 })).toBe(false);
    expect(sameWorkHoursDraft(draft, { ...draft, standardHours: '9' })).toBe(false);
  });

  it('sums itself up in a line', () => {
    expect(workHoursSummary(DEFAULT_WORK_HOURS)).toBe('8h standard day · 10 min late grace');
  });
});
