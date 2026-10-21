/**
 * The arena's pay rules (`pay_policies.policy`; docs/STAFF_API.md › pay_policies). Append-only
 * and effective-dated: a pay run uses the row in force on its first day; with no row the
 * defaults apply. The server validates every key (refusal `invalid_pay_policy`).
 */
export type PeriodKind = 'monthly' | 'weekly' | 'custom';
export type DayDivisor = 'calendar' | '30' | '26' | 'scheduled';
export type PayType = 'monthly' | 'daily' | 'hourly';

export const PAY_TYPES: readonly PayType[] = ['monthly', 'daily', 'hourly'];

export interface PayPolicy {
  readonly periodKind: PeriodKind;
  /** Monthly periods start on this day of the month (1–28). */
  readonly cycleStartDay: number;
  readonly dayDivisor: DayDivisor;
  /** Days of pay per absent day (0–3). */
  readonly absentFactor: number;
  /** Days of pay per LOP day (0–3). */
  readonly lopFactor: number;
  /** Day of pay per half-day (0–1). */
  readonly halfDayFactor: number;
  /** Every this many lates… (0 = no late rule; 0–31). */
  readonly lateEvery: number;
  /** …costs this many days of pay (0–1). */
  readonly latePenaltyDays: number;
  readonly lateAppliesTo: readonly PayType[];
  readonly earlyLeaveCountsAsLate: boolean;
  /** Extra hours are paid at the hourly rate × this (1–5). */
  readonly extraMultiplier: number;
  /** Daily-paid staff get a day's pay on a paid staff holiday. */
  readonly dailyPaidHolidays: boolean;
}

export interface PayPolicyRow {
  readonly id: string;
  readonly effectiveFrom: string;
  readonly policy: PayPolicy;
  readonly createdBy: string;
  readonly createdAt: string;
}

export const DEFAULT_PAY_POLICY: PayPolicy = {
  periodKind: 'monthly',
  cycleStartDay: 1,
  dayDivisor: 'calendar',
  absentFactor: 1,
  lopFactor: 1,
  halfDayFactor: 0.5,
  lateEvery: 3,
  latePenaltyDays: 0.5,
  lateAppliesTo: ['monthly', 'daily'],
  earlyLeaveCountsAsLate: true,
  extraMultiplier: 1,
  dailyPaidHolidays: false,
};

export const PERIOD_KINDS: readonly { value: PeriodKind; label: string; sub: string }[] = [
  { value: 'monthly', label: 'Monthly', sub: 'One run per month, starting on the cycle day' },
  {
    value: 'weekly',
    label: 'Weekly',
    sub: 'One run per week, from the week start in Working hours',
  },
  { value: 'custom', label: 'Custom', sub: 'Pick the dates for each run (up to 62 days)' },
];

export const DAY_DIVISORS: readonly { value: DayDivisor; label: string; sub: string }[] = [
  {
    value: 'calendar',
    label: 'Calendar days',
    sub: 'A monthly salary ÷ the days in the period (31 in October)',
  },
  { value: '30', label: '30 days', sub: 'Always ÷ 30' },
  { value: '26', label: '26 days', sub: 'Always ÷ 26 (a six-day week)' },
  { value: 'scheduled', label: 'Scheduled days', sub: '÷ the person’s working days in the period' },
];

export function payTypeLabel(t: PayType): string {
  return t === 'monthly' ? 'Fixed monthly' : t === 'daily' ? 'Daily' : 'Hourly';
}

/** "/ month", "/ day", "/ h". */
export function perLabel(t: PayType): string {
  return t === 'monthly' ? '/ month' : t === 'daily' ? '/ day' : '/ h';
}

function oneOf<T extends string>(v: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(v as T) ? (v as T) : fallback;
}

function numIn(v: unknown, min: number, max: number, fallback: number, int = false): number {
  const n = Number(v);
  return Number.isFinite(n) && n >= min && n <= max && (!int || Number.isInteger(n)) ? n : fallback;
}

/** Saved json → policy; anything missing or out of range reads as the default. */
export function parsePayPolicy(json: unknown): PayPolicy {
  const j = (json ?? {}) as Record<string, unknown>;
  const d = DEFAULT_PAY_POLICY;
  const applies = Array.isArray(j['late_applies_to'])
    ? (j['late_applies_to'] as unknown[]).filter((t): t is PayType =>
        PAY_TYPES.includes(t as PayType),
      )
    : d.lateAppliesTo;
  const divisor = String(j['day_divisor'] ?? '');
  return {
    periodKind: oneOf(j['period_kind'], ['monthly', 'weekly', 'custom'], d.periodKind),
    cycleStartDay: numIn(j['cycle_start_day'], 1, 28, d.cycleStartDay, true),
    dayDivisor: oneOf(divisor, ['calendar', '30', '26', 'scheduled'], d.dayDivisor),
    absentFactor: numIn(j['absent_factor'], 0, 3, d.absentFactor),
    lopFactor: numIn(j['lop_factor'], 0, 3, d.lopFactor),
    halfDayFactor: numIn(j['half_day_factor'], 0, 1, d.halfDayFactor),
    lateEvery: numIn(j['late_every'], 0, 31, d.lateEvery, true),
    latePenaltyDays: numIn(j['late_penalty_days'], 0, 1, d.latePenaltyDays),
    lateAppliesTo: applies,
    earlyLeaveCountsAsLate:
      typeof j['early_leave_counts_as_late'] === 'boolean'
        ? (j['early_leave_counts_as_late'] as boolean)
        : d.earlyLeaveCountsAsLate,
    extraMultiplier: numIn(j['extra_multiplier'], 1, 5, d.extraMultiplier),
    dailyPaidHolidays:
      typeof j['daily_paid_holidays'] === 'boolean'
        ? (j['daily_paid_holidays'] as boolean)
        : d.dailyPaidHolidays,
  };
}

/** Policy → the `policy` json the server requires (every key). */
export function payPolicyJson(p: PayPolicy): Record<string, unknown> {
  return {
    period_kind: p.periodKind,
    cycle_start_day: p.cycleStartDay,
    day_divisor: p.dayDivisor,
    absent_factor: p.absentFactor,
    lop_factor: p.lopFactor,
    half_day_factor: p.halfDayFactor,
    late_every: p.lateEvery,
    late_penalty_days: p.latePenaltyDays,
    late_applies_to: PAY_TYPES.filter((t) => p.lateAppliesTo.includes(t)),
    early_leave_counts_as_late: p.earlyLeaveCountsAsLate,
    extra_multiplier: p.extraMultiplier,
    daily_paid_holidays: p.dailyPaidHolidays,
  };
}

/** The rules in force on `day` (latest effective_from on or before it); the defaults if none. */
export function policyOn(rows: readonly PayPolicyRow[], day: string): PayPolicy {
  return rowOn(rows, day)?.policy ?? DEFAULT_PAY_POLICY;
}

export function rowOn(rows: readonly PayPolicyRow[], day: string): PayPolicyRow | undefined {
  return [...rows]
    .filter((r) => r.effectiveFrom <= day)
    .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom))[0];
}

/** The dialog's draft: numbers as typed. */
export interface PolicyDraft {
  readonly periodKind: PeriodKind;
  readonly cycleStartDay: string;
  readonly dayDivisor: DayDivisor;
  readonly absentFactor: string;
  readonly lopFactor: string;
  readonly halfDayFactor: string;
  readonly lateEvery: string;
  readonly latePenaltyDays: string;
  readonly lateAppliesTo: readonly PayType[];
  readonly earlyLeaveCountsAsLate: boolean;
  readonly extraMultiplier: string;
  readonly dailyPaidHolidays: boolean;
}

export type PolicyField =
  | 'cycleStartDay'
  | 'absentFactor'
  | 'lopFactor'
  | 'halfDayFactor'
  | 'lateEvery'
  | 'latePenaltyDays'
  | 'extraMultiplier';

export function toPolicyDraft(p: PayPolicy): PolicyDraft {
  return {
    periodKind: p.periodKind,
    cycleStartDay: String(p.cycleStartDay),
    dayDivisor: p.dayDivisor,
    absentFactor: String(p.absentFactor),
    lopFactor: String(p.lopFactor),
    halfDayFactor: String(p.halfDayFactor),
    lateEvery: String(p.lateEvery),
    latePenaltyDays: String(p.latePenaltyDays),
    lateAppliesTo: [...p.lateAppliesTo],
    earlyLeaveCountsAsLate: p.earlyLeaveCountsAsLate,
    extraMultiplier: String(p.extraMultiplier),
    dailyPaidHolidays: p.dailyPaidHolidays,
  };
}

function num(text: string): number {
  return text.trim() === '' ? Number.NaN : Number(text.trim());
}

const RANGES: Readonly<Record<PolicyField, [number, number, boolean, string]>> = {
  cycleStartDay: [1, 28, true, 'The cycle start day must be a whole number from 1 to 28'],
  absentFactor: [0, 3, false, 'Days of pay per absent day must be from 0 to 3'],
  lopFactor: [0, 3, false, 'Days of pay per LOP day must be from 0 to 3'],
  halfDayFactor: [0, 1, false, 'A half-day costs from 0 to 1 day of pay'],
  lateEvery: [0, 31, true, '“Every N lates” must be a whole number from 0 to 31'],
  latePenaltyDays: [0, 1, false, 'The late penalty must be from 0 to 1 day'],
  extraMultiplier: [1, 5, false, 'The extra-hours multiplier must be from 1 to 5'],
};

/** What the server would refuse, per field, in plain words. */
export function policyProblems(d: PolicyDraft): Partial<Record<PolicyField, string>> {
  const out: Partial<Record<PolicyField, string>> = {};
  for (const key of Object.keys(RANGES) as PolicyField[]) {
    const [min, max, int, message] = RANGES[key];
    const n = num(d[key]);
    if (!Number.isFinite(n) || n < min || n > max || (int && !Number.isInteger(n))) {
      out[key] = message;
    }
  }
  return out;
}

export function fromPolicyDraft(d: PolicyDraft): PayPolicy | null {
  if (Object.keys(policyProblems(d)).length) return null;
  return {
    periodKind: d.periodKind,
    cycleStartDay: num(d.cycleStartDay),
    dayDivisor: d.dayDivisor,
    absentFactor: num(d.absentFactor),
    lopFactor: num(d.lopFactor),
    halfDayFactor: num(d.halfDayFactor),
    lateEvery: num(d.lateEvery),
    latePenaltyDays: num(d.latePenaltyDays),
    lateAppliesTo: PAY_TYPES.filter((t) => d.lateAppliesTo.includes(t)),
    earlyLeaveCountsAsLate: d.earlyLeaveCountsAsLate,
    extraMultiplier: num(d.extraMultiplier),
    dailyPaidHolidays: d.dailyPaidHolidays,
  };
}

/** pay_policy.add payload. */
export function payPolicyPayload(
  id: string,
  effectiveFrom: string,
  p: PayPolicy,
): Record<string, unknown> {
  return { id, effective_from: effectiveFrom, policy: payPolicyJson(p) };
}

/** The rules in plain words, one line each (Pay setup › Pay rules, the print view). */
export function policyLines(p: PayPolicy): { label: string; value: string }[] {
  const n = (x: number) => String(x);
  const days = (x: number) => `${n(x)} day${x <= 1 ? '' : 's'}`;
  return [
    {
      label: 'Pay period',
      value:
        p.periodKind === 'monthly'
          ? `Monthly, starting on day ${p.cycleStartDay}`
          : p.periodKind === 'weekly'
            ? 'Weekly'
            : 'Custom dates per run',
    },
    {
      label: 'Day rate of a monthly salary',
      value: DAY_DIVISORS.find((d) => d.value === p.dayDivisor)?.sub ?? p.dayDivisor,
    },
    { label: 'Absent day costs', value: `${days(p.absentFactor)} of pay` },
    { label: 'LOP day costs', value: `${days(p.lopFactor)} of pay` },
    { label: 'Half-day costs', value: `${days(p.halfDayFactor)} of pay` },
    {
      label: 'Late rule',
      value:
        p.lateEvery === 0
          ? 'Off'
          : `Every ${p.lateEvery} late${p.lateEvery === 1 ? '' : 's'} = ${days(p.latePenaltyDays)} of pay · ${
              p.lateAppliesTo.length
                ? p.lateAppliesTo.map((t) => payTypeLabel(t).toLowerCase()).join(', ')
                : 'no pay type'
            }`,
    },
    { label: 'Early leave counts as late', value: p.earlyLeaveCountsAsLate ? 'Yes' : 'No' },
    { label: 'Extra hours paid at', value: `${n(p.extraMultiplier)}× the hourly rate` },
    { label: 'Daily staff paid on holidays', value: p.dailyPaidHolidays ? 'Yes' : 'No' },
  ];
}
