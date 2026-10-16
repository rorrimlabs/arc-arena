import { sampleLeaveRequests } from './leave-api.sample';
import {
  adjustPayload,
  alsoOff,
  decidePayload,
  defaultPaidDays,
  filterRequests,
  openRequests,
  paidDaysProblem,
  parseAdjustDays,
  requestHistory,
  splitSentence,
} from './leave.models';

describe('leave models', () => {
  const all = sampleLeaveRequests();
  const byId = (id: string) => all.find((r) => r.id === id)!;

  it('pre-fills paid days with min(days, balance), never below 0, in half days', () => {
    expect(defaultPaidDays(2, 1)).toBe(1);
    expect(defaultPaidDays(2, 5)).toBe(2);
    expect(defaultPaidDays(3, -1)).toBe(0);
    expect(defaultPaidDays(2, 1.75)).toBe(1.5);
    expect(defaultPaidDays(0.5, 4)).toBe(0.5);
    expect(defaultPaidDays(2, null)).toBe(0);
  });

  it('says the split and that LOP is deducted from salary', () => {
    expect(splitSentence(2, 3)).toBe('2 paid · 1 LOP — LOP is deducted from salary');
    expect(splitSentence(1.5, 2)).toBe('1.5 paid · 0.5 LOP — LOP is deducted from salary');
    expect(splitSentence(3, 3)).toBe('3 paid · 0 LOP');
  });

  it('checks paid days: 0…days in steps of 0.5', () => {
    expect(paidDaysProblem(1, 2)).toBeNull();
    expect(paidDaysProblem(0, 2)).toBeNull();
    expect(paidDaysProblem(2.5, 2)).toBe('Paid days must be from 0 to 2');
    expect(paidDaysProblem(-1, 2)).toBe('Paid days must be from 0 to 2');
    expect(paidDaysProblem(0.3, 2)).toBe('Use whole or half days (e.g. 1.5)');
    expect(paidDaysProblem(Number.NaN, 2)).toBe('Enter the paid days');
  });

  it('builds leave.decide payloads: paid_days only when approving a new request', () => {
    expect(decidePayload(byId('lr1'), true, 1, ' Enjoy ')).toEqual({
      id: 'lr1',
      approve: true,
      paid_days: 1,
      note: 'Enjoy',
    });
    expect(decidePayload(byId('lr1'), false, null, '')).toEqual({ id: 'lr1', approve: false });
    // A cancellation: approve = cancel it; reject = keep the leave.
    expect(decidePayload(byId('lr3'), true, 2, '')).toEqual({ id: 'lr3', approve: true });
    expect(decidePayload(byId('lr3'), false, null, 'Busy week')).toEqual({
      id: 'lr3',
      approve: false,
      note: 'Busy week',
    });
  });

  it('reads an adjustment as signed whole or half days, never 0', () => {
    expect(parseAdjustDays('+1')).toBe(1);
    expect(parseAdjustDays('-0.5')).toBe(-0.5);
    expect(parseAdjustDays('2')).toBe(2);
    expect(parseAdjustDays('0')).toBeNull();
    expect(parseAdjustDays('0.3')).toBeNull();
    expect(parseAdjustDays('abc')).toBeNull();
    expect(adjustPayload('st1', -0.5, ' Correction ')).toEqual({
      staff_id: 'st1',
      days: -0.5,
      reason: 'Correction',
    });
  });

  it('lists who else is off on overlapping days (approved or waiting), not the person', () => {
    expect(alsoOff(byId('lr1'), all).map((r) => r.id)).toEqual(['lr6']);
    expect(alsoOff(byId('lr5'), all)).toEqual([]);
  });

  it('Requests: waiting ones only, cancellation requests first', () => {
    expect(openRequests(all).map((r) => r.id)).toEqual(['lr3', 'lr2', 'lr1', 'lr4']);
  });

  it('All requests: by staff, status and dates, newest first', () => {
    const f = { staffId: null, status: null, first: null, last: null };
    expect(filterRequests(all, f)).toHaveLength(8);
    expect(filterRequests(all, { ...f, staffId: 'st3' }).map((r) => r.id)).toEqual(['lr6', 'lr5']);
    expect(filterRequests(all, { ...f, status: 'rejected' }).map((r) => r.id)).toEqual(['lr7']);
    expect(
      filterRequests(all, { ...f, first: '2026-10-20', last: '2026-10-23' }).map((r) => r.id),
    ).toEqual(['lr4', 'lr6', 'lr1']);
  });

  it('tells the story of a request from its row', () => {
    const names = (id: string | null) => (id === 'u0' ? 'Arjun Mehra' : 'Priya Nair');
    expect(requestHistory(byId('lr3'), names).map((h) => h.text)).toEqual([
      'Asked by Priya Nair',
      'Approved · 2 paid · 0 LOP by Arjun Mehra',
      'Cancellation requested',
    ]);
    expect(requestHistory(byId('lr7'), names).map((h) => [h.text, h.note])).toEqual([
      ['Asked by Priya Nair', 'Diwali shopping'],
      ['Rejected by Arjun Mehra', 'Short-staffed that week'],
    ]);
  });
});
