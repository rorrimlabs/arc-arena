import {
  DEFAULT_PAY_POLICY,
  fromPolicyDraft,
  parsePayPolicy,
  payPolicyJson,
  payPolicyPayload,
  policyLines,
  policyOn,
  policyProblems,
  toPolicyDraft,
} from './pay-policy';

describe('pay policy', () => {
  it('sends every key the server requires, in its names', () => {
    expect(payPolicyJson(DEFAULT_PAY_POLICY)).toEqual({
      period_kind: 'monthly',
      cycle_start_day: 1,
      day_divisor: 'calendar',
      absent_factor: 1,
      lop_factor: 1,
      half_day_factor: 0.5,
      late_every: 3,
      late_penalty_days: 0.5,
      late_applies_to: ['monthly', 'daily'],
      early_leave_counts_as_late: true,
      extra_multiplier: 1,
      daily_paid_holidays: false,
    });
    expect(parsePayPolicy(payPolicyJson(DEFAULT_PAY_POLICY))).toEqual(DEFAULT_PAY_POLICY);
  });

  it('reads anything missing or out of range as the default', () => {
    const p = parsePayPolicy({
      cycle_start_day: 31,
      extra_multiplier: 1.5,
      day_divisor: '26',
      late_applies_to: ['hourly', 'x'],
    });
    expect(p.cycleStartDay).toBe(1);
    expect(p.extraMultiplier).toBe(1.5);
    expect(p.dayDivisor).toBe('26');
    expect(p.lateAppliesTo).toEqual(['hourly']);
  });

  it('validates the draft field by field', () => {
    const d = toPolicyDraft(DEFAULT_PAY_POLICY);
    expect(policyProblems(d)).toEqual({});
    const bad = {
      ...d,
      cycleStartDay: '29',
      extraMultiplier: '0.5',
      lateEvery: '2.5',
      halfDayFactor: '2',
    };
    expect(policyProblems(bad)).toEqual({
      cycleStartDay: 'The cycle start day must be a whole number from 1 to 28',
      extraMultiplier: 'The extra-hours multiplier must be from 1 to 5',
      lateEvery: '“Every N lates” must be a whole number from 0 to 31',
      halfDayFactor: 'A half-day costs from 0 to 1 day of pay',
    });
    expect(fromPolicyDraft(bad)).toBeNull();
  });

  it('turns a valid draft into the pay_policy.add payload', () => {
    const policy = fromPolicyDraft({
      ...toPolicyDraft(DEFAULT_PAY_POLICY),
      periodKind: 'weekly',
      extraMultiplier: '1.5',
      lateAppliesTo: ['daily', 'monthly'],
      dailyPaidHolidays: true,
    })!;
    const payload = payPolicyPayload('p1', '2026-11-01', policy);
    expect(payload['id']).toBe('p1');
    expect(payload['effective_from']).toBe('2026-11-01');
    expect(payload['policy']).toMatchObject({
      period_kind: 'weekly',
      extra_multiplier: 1.5,
      late_applies_to: ['monthly', 'daily'],
      daily_paid_holidays: true,
    });
  });

  it('picks the rules in force on a day and says them in words', () => {
    const rows = [
      {
        id: 'a',
        effectiveFrom: '2026-04-01',
        policy: { ...DEFAULT_PAY_POLICY, extraMultiplier: 1.5 },
        createdBy: '',
        createdAt: '',
      },
      {
        id: 'b',
        effectiveFrom: '2026-11-01',
        policy: { ...DEFAULT_PAY_POLICY, extraMultiplier: 2 },
        createdBy: '',
        createdAt: '',
      },
    ];
    expect(policyOn(rows, '2026-10-31').extraMultiplier).toBe(1.5);
    expect(policyOn(rows, '2026-11-01').extraMultiplier).toBe(2);
    expect(policyOn(rows, '2026-01-01')).toEqual(DEFAULT_PAY_POLICY);
    const lines = policyLines(DEFAULT_PAY_POLICY);
    expect(lines.find((l) => l.label === 'Late rule')?.value).toBe(
      'Every 3 lates = 0.5 day of pay · fixed monthly, daily',
    );
  });
});
