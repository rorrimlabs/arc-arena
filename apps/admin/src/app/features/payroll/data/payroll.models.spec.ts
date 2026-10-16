import { formatPaise } from '../../../shared/money/rupees.pipe';
import { formatHMin, formatRange, isoWeekday } from '../../../shared/staff/staff-format';
import { DEFAULT_PAY_POLICY } from './pay-policy';
import { arjunOctober } from './payroll-api.sample';
import {
  SalaryRun,
  adjustmentPayload,
  createRunPayload,
  lastFinalisedEnd,
  monthlyCycleOf,
  newRunProblem,
  rateSpans,
  reversePayload,
  setDeductionPayload,
  suggestNextPeriod,
  weekOf,
} from './payroll.models';

function run(first: string, last: string, status: SalaryRun['status']): SalaryRun {
  return {
    id: `${first}-${status}`,
    periodStart: first,
    periodEnd: last,
    status,
    computedAt: null,
    staffCount: 0,
    grossPaise: 0,
    deductionsPaise: 0,
    adjustmentsPaise: 0,
    netPaise: 0,
    createdBy: 'u0',
    createdAt: '',
    finalisedBy: null,
    finalisedAt: null,
  };
}

describe('payroll models', () => {
  it('formats paise to the paisa and minutes as hours and minutes', () => {
    expect(formatPaise(1_475_806)).toBe('₹14,758.06');
    expect(formatPaise(-30_000)).toBe('−₹300.00');
    expect(formatPaise(5)).toBe('₹0.05');
    expect(formatHMin(485)).toBe('8h 05m');
    expect(formatHMin(1440)).toBe('24h 00m');
    expect(formatRange('2026-10-01', '2026-10-31')).toBe('1–31 Oct 2026');
    expect(formatRange('2026-09-28', '2026-10-04')).toMatch(/^28 Sept? – 4 Oct 2026$/);
    expect(isoWeekday('2026-10-05')).toBe(1);
    expect(isoWeekday('2026-10-11')).toBe(7);
  });

  it('monthly cycles start on the cycle day', () => {
    expect(monthlyCycleOf('2026-10-13', 1)).toEqual({ first: '2026-10-01', last: '2026-10-31' });
    expect(monthlyCycleOf('2026-10-13', 26)).toEqual({ first: '2026-09-26', last: '2026-10-25' });
    expect(monthlyCycleOf('2026-12-28', 26)).toEqual({ first: '2026-12-26', last: '2027-01-25' });
    expect(monthlyCycleOf('2026-02-10', 1)).toEqual({ first: '2026-02-01', last: '2026-02-28' });
  });

  it('weeks start on the week start of Working hours', () => {
    expect(weekOf('2026-10-13', 1)).toEqual({ first: '2026-10-12', last: '2026-10-18' });
    expect(weekOf('2026-10-13', 7)).toEqual({ first: '2026-10-11', last: '2026-10-17' });
  });

  it('suggests the period after the latest run that was not discarded', () => {
    const monthly = DEFAULT_PAY_POLICY;
    const runs = [
      run('2026-09-01', '2026-09-30', 'finalised'),
      run('2026-10-01', '2026-10-31', 'discarded'),
    ];
    expect(suggestNextPeriod(monthly, runs, 1, '2026-11-02')).toEqual({
      first: '2026-10-01',
      last: '2026-10-31',
    });
    // Cycle day 26: 26 Oct – 25 Nov after a run ending 25 Oct.
    expect(
      suggestNextPeriod(
        { ...monthly, cycleStartDay: 26 },
        [run('2026-09-26', '2026-10-25', 'draft')],
        1,
        '2026-10-30',
      ),
    ).toEqual({ first: '2026-10-26', last: '2026-11-25' });
    // No run yet: the last complete month before today.
    expect(suggestNextPeriod(monthly, [], 1, '2026-10-13')).toEqual({
      first: '2026-09-01',
      last: '2026-09-30',
    });
  });

  it('weekly suggestions follow the week start; custom ones the last run', () => {
    const weekly = { ...DEFAULT_PAY_POLICY, periodKind: 'weekly' as const };
    expect(
      suggestNextPeriod(weekly, [run('2026-10-05', '2026-10-11', 'finalised')], 1, '2026-10-15'),
    ).toEqual({
      first: '2026-10-12',
      last: '2026-10-18',
    });
    // No run, week starting Sunday: the last complete week before Tue 13 Oct.
    expect(suggestNextPeriod(weekly, [], 7, '2026-10-13')).toEqual({
      first: '2026-10-04',
      last: '2026-10-10',
    });
    const custom = { ...DEFAULT_PAY_POLICY, periodKind: 'custom' as const };
    expect(
      suggestNextPeriod(custom, [run('2026-10-01', '2026-10-15', 'draft')], 1, '2026-10-20'),
    ).toEqual({
      first: '2026-10-16',
      last: '2026-11-14',
    });
  });

  it('refuses overlaps and periods over 62 days before the server does', () => {
    const runs = [
      run('2026-10-01', '2026-10-31', 'draft'),
      run('2026-08-01', '2026-08-31', 'discarded'),
    ];
    expect(newRunProblem({ first: '2026-10-25', last: '2026-11-24' }, runs)).toBe(
      'Overlaps the draft run for 1–31 Oct 2026',
    );
    expect(newRunProblem({ first: '2026-08-01', last: '2026-08-31' }, runs)).toBeNull();
    expect(newRunProblem({ first: '2026-11-01', last: '2027-01-02' }, runs)).toBe(
      'A run covers at most 62 days',
    );
    expect(newRunProblem({ first: '2026-11-10', last: '2026-11-01' }, runs)).toBe(
      'The first day is after the last',
    );
    expect(newRunProblem({ first: '', last: '2026-11-01' }, runs)).toBe('Pick both dates');
  });

  it('knows the last finalised period end', () => {
    expect(
      lastFinalisedEnd([
        run('2026-09-01', '2026-09-30', 'finalised'),
        run('2026-10-01', '2026-10-31', 'draft'),
      ]),
    ).toBe('2026-09-30');
    expect(lastFinalisedEnd([])).toBeNull();
  });

  it('builds the op payloads (adjustments always positive; the server signs them)', () => {
    expect(createRunPayload('r1', { first: '2026-11-01', last: '2026-11-30' })).toEqual({
      id: 'r1',
      period_start: '2026-11-01',
      period_end: '2026-11-30',
    });
    expect(setDeductionPayload('r1', 'st1', 'late', false, ' First month ')).toEqual({
      run_id: 'r1',
      staff_id: 'st1',
      code: 'late',
      applied: false,
      note: 'First month',
    });
    expect(setDeductionPayload('r1', 'st1', 'absent', true, '')).toEqual({
      run_id: 'r1',
      staff_id: 'st1',
      code: 'absent',
      applied: true,
    });
    expect(adjustmentPayload('a1', 'r1', 'st1', 'advance', -200_000, 'Oct 10 advance')).toEqual({
      id: 'a1',
      run_id: 'r1',
      staff_id: 'st1',
      kind: 'advance',
      amount_paise: 200_000,
      note: 'Oct 10 advance',
    });
    expect(reversePayload('a2', 'a1', ' Typo ')).toEqual({
      id: 'a2',
      reverses_id: 'a1',
      note: 'Typo',
    });
  });

  it('splits a mid-period raise into the days each rate covered', () => {
    const spans = rateSpans(arjunOctober('r').rates, '2026-10-01', '2026-10-31');
    expect(spans.map((s) => [s.rate.basePaise, s.first, s.last])).toEqual([
      [2_000_000, '2026-10-01', '2026-10-15'],
      [2_200_000, '2026-10-16', '2026-10-31'],
    ]);
  });
});
