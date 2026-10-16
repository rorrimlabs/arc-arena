import { samplePayRates } from './pay-setup-api.sample';
import {
  HrDraft,
  RateDraft,
  derivedHourlyPaise,
  finalisedLimitText,
  hrPayload,
  hrProblems,
  minEffectiveFrom,
  rateOn,
  ratePayload,
  rateProblems,
  rateSummary,
  resolvedProfile,
  toHrDraft,
} from './pay-setup.models';

describe('pay setup models', () => {
  const rates = samplePayRates();
  const draft: RateDraft = {
    effectiveFrom: '2026-11-01',
    payType: 'monthly',
    amount: '18,500.50',
    extraHoursPaid: true,
    extraRate: '95.25',
    note: ' Review ',
  };

  it('sends rupees as integer paise, never floats', () => {
    const payload = ratePayload('id1', 'st1', draft);
    expect(payload).toEqual({
      id: 'id1',
      staff_id: 'st1',
      effective_from: '2026-11-01',
      pay_type: 'monthly',
      base_paise: 1_850_050,
      extra_hours_paid: true,
      extra_hourly_paise: 9_525,
      note: 'Review',
    });
    expect(Number.isInteger(payload['base_paise'])).toBe(true);
    // No own rate (derived), extra hours off: no extra_hourly_paise at all.
    expect(
      ratePayload('id2', 'st1', { ...draft, extraRate: '' })['extra_hourly_paise'],
    ).toBeUndefined();
    expect(
      ratePayload('id3', 'st1', { ...draft, extraHoursPaid: false })['extra_hourly_paise'],
    ).toBeUndefined();
    // ₹0.10 is ten paise, exactly.
    expect(ratePayload('id4', 'st1', { ...draft, amount: '120.1' })['base_paise']).toBe(12_010);
  });

  it('limits the effective date to after the last finalised period, and says why', () => {
    expect(minEffectiveFrom('2026-09-30')).toBe('2026-10-01');
    expect(minEffectiveFrom(null)).toBeNull();
    expect(finalisedLimitText('2026-09-30')).toMatch(
      /^Pay up to 30 Sept? 2026 is finalised, so this can start on 1 Oct 2026 or later\.$/,
    );
    const own = rates.filter((r) => r.staffId === 'st3');
    expect(
      rateProblems({ ...draft, effectiveFrom: '2026-09-15' }, own, '2026-09-30').effectiveFrom,
    ).toContain('is finalised');
    expect(
      rateProblems({ ...draft, effectiveFrom: '2026-10-16' }, own, '2026-09-30').effectiveFrom,
    ).toBe('A rate already starts on that day: pick another day');
    expect(rateProblems(draft, own, '2026-09-30')).toEqual({});
    expect(rateProblems({ ...draft, amount: '0' }, own, null).amount).toBe(
      'Enter the amount in rupees, more than zero',
    );
    expect(rateProblems({ ...draft, extraRate: 'x' }, own, null).extraRate).toBeDefined();
  });

  it('picks the rate in force and explains the derived extra-hours rate', () => {
    const arjun = rates.filter((r) => r.staffId === 'st3');
    expect(rateOn(arjun, '2026-10-15')?.basePaise).toBe(2_000_000);
    expect(rateOn(arjun, '2026-10-16')?.basePaise).toBe(2_200_000);
    expect(rateOn(arjun, '2026-01-01')).toBeUndefined();
    const ravi = rates.find((r) => r.staffId === 'st1')!;
    expect(rateSummary(ravi, 480, 1.5)).toBe('₹18,000.00 / month · extra hours not paid');
    const raised = rateOn(arjun, '2026-10-20')!;
    // ₹22,000 ÷ 30 days ÷ 8 h ≈ ₹91.67/h.
    expect(rateSummary(raised, 480, 1.5)).toBe(
      '₹22,000.00 / month · extra hours paid at ≈ ₹91.67/h (derived) × 1.5',
    );
    const priya = rates.find((r) => r.staffId === 'st2')!;
    expect(rateSummary(priya, 480, 1.5)).toBe(
      '₹120.00 / h · extra hours paid at ₹120.00/h (derived) × 1.5',
    );
    expect(derivedHourlyPaise({ payType: 'daily', basePaise: 80_000 }, 480)).toBe(10_000);
  });

  it('an HR profile with no row reads as the server’s defaults', () => {
    const owner = {
      id: 'st0',
      userId: 'u0',
      name: 'A',
      role: 'owner' as const,
      active: true,
      createdAt: '2026-01-05T20:00:00Z',
    };
    const p = resolvedProfile(owner, undefined);
    // 20:00 UTC on 5 Jan is 6 Jan in IST.
    expect(p.joinedOn).toBe('2026-01-06');
    expect(p.tracksAttendance).toBe(false);
    expect(resolvedProfile({ ...owner, role: 'staff' }, undefined).tracksAttendance).toBe(true);
  });

  it('saves the HR profile with nulls for empty overrides', () => {
    const d: HrDraft = {
      ...toHrDraft(
        resolvedProfile(
          { id: 'st1', userId: 'u1', name: 'R', role: 'staff', active: true, createdAt: '' },
          undefined,
        ),
      ),
      joinedOn: '2024-11-20',
      employeeCode: ' E-014 ',
      stdHours: '9',
      stdMinutes: '30',
    };
    expect(hrPayload('st1', d)).toEqual({
      staff_id: 'st1',
      joined_on: '2024-11-20',
      left_on: null,
      tracks_attendance: true,
      employee_code: 'E-014',
      paid_leave_days: null,
      standard_day_min: 570,
    });
    expect(hrProblems({ ...d, leftOn: '2024-01-01' }).dates).toBe(
      'The leaving date is before the joining date',
    );
    expect(hrProblems({ ...d, stdHours: '0', stdMinutes: '30' }).standardDay).toBeDefined();
    expect(hrProblems({ ...d, paidLeaveDays: '1.3' }).paidLeaveDays).toBeDefined();
    expect(
      hrPayload('st1', { ...d, paidLeaveDays: '10.5', stdHours: '', stdMinutes: '' }),
    ).toMatchObject({
      paid_leave_days: 10.5,
      standard_day_min: null,
    });
  });
});
