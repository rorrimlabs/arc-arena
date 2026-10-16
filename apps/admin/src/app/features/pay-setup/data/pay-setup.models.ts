import { formatPaise } from '../../../shared/money/rupees.pipe';
import { formatDayYear } from '../../../shared/staff/staff-format';
import { addDays, formatIsoDate } from '../../../shared/time/ist';
import { parseRupees } from '../../sales/data/sale.models';
import { PayPolicyRow, PayType, perLabel } from '../../payroll/data/pay-policy';

/**
 * Pay setup (docs/STAFF_API.md › staff_hr_profiles, staff_pay_rates, pay_policies): each
 * person's HR profile and effective-dated pay rates, and the arena's pay rules. Nothing here
 * computes pay; the derived extra-hours rate is shown as an estimate only (docs/STAFF.md S3).
 */
export interface PayStaff {
  readonly id: string;
  readonly userId: string;
  readonly name: string;
  readonly role: 'owner' | 'staff';
  readonly active: boolean;
  readonly createdAt: string;
}

/** A saved staff_hr_profiles row (null fields = arena default / not set). */
export interface HrProfile {
  readonly staffId: string;
  readonly joinedOn: string | null;
  readonly leftOn: string | null;
  readonly tracksAttendance: boolean;
  readonly employeeCode: string | null;
  readonly paidLeaveDays: number | null;
  readonly standardDayMin: number | null;
}

export interface PayRate {
  readonly id: string;
  readonly staffId: string;
  readonly effectiveFrom: string;
  readonly payType: PayType;
  /** Per month, day or hour. */
  readonly basePaise: number;
  readonly extraHoursPaid: boolean;
  /** Own extra-hours rate; null = derived from the pay. */
  readonly extraHourlyPaise: number | null;
  readonly note: string | null;
  readonly createdBy: string;
  readonly createdAt: string;
}

/** Arena defaults shown as placeholders where a person has no override. */
export interface PayDefaults {
  readonly standardDayMin: number;
  readonly paidLeaveDays: number;
}

export interface PaySetupData {
  readonly staff: readonly PayStaff[];
  readonly profiles: readonly HrProfile[];
  readonly rates: readonly PayRate[];
  readonly policies: readonly PayPolicyRow[];
  /** The end of the latest finalised salary run (rates and rules must start after it). */
  readonly finalisedEnd: string | null;
  readonly defaults: PayDefaults;
}

/** A profile as it applies: the saved row, or the server's no-row defaults. */
export function resolvedProfile(s: PayStaff, row: HrProfile | undefined): HrProfile {
  return (
    row ?? {
      staffId: s.id,
      joinedOn: s.createdAt ? formatIsoDate(s.createdAt) : null,
      leftOn: null,
      tracksAttendance: s.role !== 'owner',
      employeeCode: null,
      paidLeaveDays: null,
      standardDayMin: null,
    }
  );
}

/** The rate in force on `day` (latest effective_from on or before it), or undefined. */
export function rateOn(rates: readonly PayRate[], day: string): PayRate | undefined {
  return [...rates]
    .filter((r) => r.effectiveFrom <= day)
    .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom))[0];
}

/** The first day a new rate or rule may start: the day after the last finalised run. */
export function minEffectiveFrom(finalisedEnd: string | null): string | null {
  return finalisedEnd ? addDays(finalisedEnd, 1) : null;
}

/** Why the effective-from picker is limited, in words; "" when it isn't. */
export function finalisedLimitText(finalisedEnd: string | null): string {
  if (!finalisedEnd) return '';
  const min = minEffectiveFrom(finalisedEnd) as string;
  return `Pay up to ${formatDayYear(finalisedEnd)} is finalised, so this can start on ${formatDayYear(min)} or later.`;
}

/**
 * The derived extra-hours rate per hour, as an estimate (the server derives it per period,
 * docs/STAFF.md S3): monthly ÷ `daysInPeriod` ÷ standard hours; daily ÷ standard hours; hourly
 * as is. Paise, rounded for display.
 */
export function derivedHourlyPaise(
  r: Pick<PayRate, 'payType' | 'basePaise'>,
  standardDayMin: number,
  daysInPeriod = 30,
): number {
  const hours = standardDayMin / 60;
  if (r.payType === 'hourly') return r.basePaise;
  if (r.payType === 'daily') return Math.round(r.basePaise / hours);
  return Math.round(r.basePaise / daysInPeriod / hours);
}

/** "₹18,000.00 / month · extra hours paid at ≈ ₹75.00/h (derived) × 1.5". */
export function rateSummary(r: PayRate, standardDayMin: number, multiplier: number): string {
  const base = `${formatPaise(r.basePaise)} ${perLabel(r.payType)}`;
  if (!r.extraHoursPaid) {
    return r.payType === 'hourly'
      ? `${base} · extra hours at the hourly rate, no multiplier`
      : `${base} · extra hours not paid`;
  }
  const times = multiplier === 1 ? '' : ` × ${multiplier}`;
  if (r.extraHourlyPaise !== null) {
    return `${base} · extra hours paid at ${formatPaise(r.extraHourlyPaise)}/h${times}`;
  }
  const approx = r.payType === 'monthly' ? '≈ ' : '';
  return `${base} · extra hours paid at ${approx}${formatPaise(derivedHourlyPaise(r, standardDayMin))}/h (derived)${times}`;
}

// ------------------------------------------------------------------ HR profile draft

export interface HrDraft {
  readonly joinedOn: string;
  readonly leftOn: string;
  readonly tracksAttendance: boolean;
  readonly employeeCode: string;
  /** Standard day override as hours and minutes; both empty = arena default. */
  readonly stdHours: string;
  readonly stdMinutes: string;
  /** Paid leave override; empty = arena default. */
  readonly paidLeaveDays: string;
}

export type HrField = 'dates' | 'employeeCode' | 'standardDay' | 'paidLeaveDays';

export function toHrDraft(p: HrProfile): HrDraft {
  const std = p.standardDayMin;
  return {
    joinedOn: p.joinedOn ?? '',
    leftOn: p.leftOn ?? '',
    tracksAttendance: p.tracksAttendance,
    employeeCode: p.employeeCode ?? '',
    stdHours: std === null ? '' : String(Math.floor(std / 60)),
    stdMinutes: std === null ? '' : String(std % 60),
    paidLeaveDays: p.paidLeaveDays === null ? '' : String(p.paidLeaveDays),
  };
}

function num(text: string): number {
  return text.trim() === '' ? Number.NaN : Number(text.trim());
}

/** The standard day typed, in minutes; null = default; NaN = not valid. */
export function draftStandardDay(d: HrDraft): number | null {
  if (d.stdHours.trim() === '' && d.stdMinutes.trim() === '') return null;
  const h = d.stdHours.trim() === '' ? 0 : num(d.stdHours);
  const m = d.stdMinutes.trim() === '' ? 0 : num(d.stdMinutes);
  if (!Number.isInteger(h) || !Number.isInteger(m) || h < 0 || m < 0 || m > 59) return Number.NaN;
  return h * 60 + m;
}

export function hrProblems(d: HrDraft): Partial<Record<HrField, string>> {
  const out: Partial<Record<HrField, string>> = {};
  if (d.joinedOn && d.leftOn && d.leftOn < d.joinedOn)
    out.dates = 'The leaving date is before the joining date';
  if (d.employeeCode.trim().length > 40) out.employeeCode = 'Use up to 40 characters';
  const std = draftStandardDay(d);
  if (std !== null && (!Number.isFinite(std) || std < 60 || std > 1440)) {
    out.standardDay = 'A standard day is 1 to 24 hours (minutes 0–59)';
  }
  if (d.paidLeaveDays.trim() !== '') {
    const n = num(d.paidLeaveDays);
    if (!Number.isFinite(n) || n < 0 || n > 366 || Math.round(n * 2) !== n * 2) {
      out.paidLeaveDays = 'Paid leave is 0 to 366 days, in whole or half days';
    }
  }
  return out;
}

/** hr_profile.save payload: every key (an empty field is sent as null = cleared / default). */
export function hrPayload(staffId: string, d: HrDraft): Record<string, unknown> {
  const code = d.employeeCode.trim();
  return {
    staff_id: staffId,
    joined_on: d.joinedOn || null,
    left_on: d.leftOn || null,
    tracks_attendance: d.tracksAttendance,
    employee_code: code || null,
    paid_leave_days: d.paidLeaveDays.trim() === '' ? null : num(d.paidLeaveDays),
    standard_day_min: draftStandardDay(d),
  };
}

export function sameHrDraft(a: HrDraft, b: HrDraft): boolean {
  return (
    a.joinedOn === b.joinedOn &&
    a.leftOn === b.leftOn &&
    a.tracksAttendance === b.tracksAttendance &&
    a.employeeCode.trim() === b.employeeCode.trim() &&
    draftStandardDay(a) === draftStandardDay(b) &&
    (a.paidLeaveDays.trim() === b.paidLeaveDays.trim() ||
      num(a.paidLeaveDays) === num(b.paidLeaveDays))
  );
}

// ------------------------------------------------------------------ new rate draft

export interface RateDraft {
  readonly effectiveFrom: string;
  readonly payType: PayType;
  /** Rupees as typed. */
  readonly amount: string;
  readonly extraHoursPaid: boolean;
  /** Own extra-hours rate in rupees per hour; empty = derived. */
  readonly extraRate: string;
  readonly note: string;
}

export type RateField = 'effectiveFrom' | 'amount' | 'extraRate';

export function rateProblems(
  d: RateDraft,
  existing: readonly PayRate[],
  finalisedEnd: string | null,
): Partial<Record<RateField, string>> {
  const out: Partial<Record<RateField, string>> = {};
  const min = minEffectiveFrom(finalisedEnd);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d.effectiveFrom))
    out.effectiveFrom = 'Pick the first day of the new rate';
  else if (min && d.effectiveFrom < min) out.effectiveFrom = finalisedLimitText(finalisedEnd);
  else if (existing.some((r) => r.effectiveFrom === d.effectiveFrom)) {
    out.effectiveFrom = 'A rate already starts on that day: pick another day';
  }
  if (parseRupees(d.amount) === null) out.amount = 'Enter the amount in rupees, more than zero';
  if (d.extraHoursPaid && d.extraRate.trim() !== '' && parseRupees(d.extraRate) === null) {
    out.extraRate = 'Enter the hourly rate in rupees, or leave it empty to derive it';
  }
  return out;
}

/** pay_rate.add payload: integer paise only (never floats). */
export function ratePayload(id: string, staffId: string, d: RateDraft): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    id,
    staff_id: staffId,
    effective_from: d.effectiveFrom,
    pay_type: d.payType,
    base_paise: parseRupees(d.amount),
    extra_hours_paid: d.extraHoursPaid,
  };
  const extra = d.extraHoursPaid && d.extraRate.trim() !== '' ? parseRupees(d.extraRate) : null;
  if (extra !== null) payload['extra_hourly_paise'] = extra;
  const note = d.note.trim();
  if (note) payload['note'] = note;
  return payload;
}

/** Refusals of the pay setup ops, in plain words. */
export const PAY_SETUP_MESSAGES: Readonly<Record<string, string>> = {
  forbidden: 'You need the Payroll permission for that',
  not_found: 'That person is no longer there. Refresh',
  invalid_payload: 'Check the values and try again',
  invalid_rate: 'The server refused this rate: check the amount and the extra-hours rate',
  duplicate: 'Something already starts on that day: pick another day',
  rate_in_finalised_period:
    'That day is inside a finalised pay run: pick a day after the last finalised period',
  invalid_pay_policy: 'The server refused these pay rules: check the values marked',
};
