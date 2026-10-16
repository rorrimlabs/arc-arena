import { AppError } from '../../../core/auth/auth-api';
import { SyncOp } from '../../../core/sync/push-ops';
import { addDays } from '../../../shared/time/ist';
import { isoWeekday } from '../../../shared/staff/staff-format';
import { SAMPLE_PEOPLE } from '../../leave/data/leave-api.sample';
import { DEFAULT_PAY_POLICY, PayPolicyRow } from './pay-policy';
import { PayrollApi, PayrollOverview } from './payroll-api';
import {
  DayCounts,
  DayFact,
  Deduction,
  PAYROLL_MESSAGES,
  RunDetail,
  RunLine,
  SalaryAdjustment,
  SalaryRun,
} from './payroll.models';

/** A day of a timesheet; everything not given is zero / false. */
function fact(day: string, status: string, over: Partial<DayFact> = {}): DayFact {
  return {
    day,
    status,
    workedMin: 0,
    extraMin: 0,
    late: false,
    early: false,
    presentUnits: 0,
    absentUnits: 0,
    leavePaid: 0,
    leaveLop: 0,
    holiday: null,
    flags: [],
    ...over,
  };
}

function daysOf(first: string, last: string): string[] {
  const out: string[] = [];
  for (let d = first; d <= last; d = addDays(d, 1)) out.push(d);
  return out;
}

const HOLIDAY = 'Gandhi Jayanti';

function counts(over: Partial<DayCounts>): DayCounts {
  return {
    scheduled: 0,
    present: 0,
    late: 0,
    halfDay: 0,
    absent: 0,
    paidLeave: 0,
    lopLeave: 0,
    holiday: 0,
    weekOff: 0,
    ...over,
  };
}

/**
 * docs/STAFF.md §4.3 Example 1. Ravi, ₹18,000/month, extra hours off, October 2026 (N = 31).
 * Mon–Sat 11:00–20:00 less a 60-min break (Sunday off); 2 Oct a paid staff holiday. Of his 26
 * scheduled days: 22 present (4 late: 6, 13, 20, 27 Oct), a half-day (15 Oct), a 2-day leave
 * approved as 1 paid (21 Oct) + 1 LOP (22 Oct), and 1 absent (29 Oct). An advance and a bonus.
 */
export function raviOctober(runId: string): RunLine {
  const late = ['2026-10-06', '2026-10-13', '2026-10-20', '2026-10-27'];
  const days = daysOf('2026-10-01', '2026-10-31').map((d) => {
    if (isoWeekday(d) === 7) return fact(d, 'week_off');
    if (d === '2026-10-02') return fact(d, 'holiday', { holiday: HOLIDAY });
    if (d === '2026-10-15')
      return fact(d, 'half_day', { workedMin: 300, presentUnits: 0.5, absentUnits: 0.5 });
    if (d === '2026-10-21') return fact(d, 'on_leave', { leavePaid: 1 });
    if (d === '2026-10-22') return fact(d, 'on_leave', { leaveLop: 1 });
    if (d === '2026-10-29') return fact(d, 'absent', { absentUnits: 1 });
    if (late.includes(d)) return fact(d, 'late', { workedMin: 465, late: true, presentUnits: 1 });
    return fact(d, 'present', { workedMin: 480, presentUnits: 1 });
  });
  const rate = 1_800_000 / 31; // 58,064.52 paise a day
  const deductions: Deduction[] = [
    {
      code: 'absent',
      label: 'Absent',
      units: 1,
      ratePaise: rate,
      amountPaise: 58_065,
      applied: true,
      note: null,
    },
    {
      code: 'lop_leave',
      label: 'LOP leave',
      units: 1,
      ratePaise: rate,
      amountPaise: 58_065,
      applied: true,
      note: null,
    },
    {
      code: 'half_day',
      label: 'Half-day',
      units: 0.5,
      ratePaise: rate,
      amountPaise: 29_032,
      applied: true,
      note: null,
    },
    {
      code: 'late',
      label: 'Late (4 lates, every 3 = ½ day)',
      units: 0.5,
      ratePaise: rate,
      amountPaise: 29_032,
      applied: true,
      note: null,
    },
  ];
  return {
    id: `${runId}-st1`,
    runId,
    staffId: 'st1',
    staffName: 'Ravi Kumar',
    payType: 'monthly',
    rates: [
      {
        effectiveFrom: '2026-04-01',
        payType: 'monthly',
        basePaise: 1_800_000,
        extraHoursPaid: false,
        extraHourlyPaise: null,
      },
    ],
    dayCounts: counts({
      scheduled: 26,
      present: 22,
      late: 4,
      halfDay: 1,
      absent: 1,
      paidLeave: 1,
      lopLeave: 1,
      holiday: 1,
      weekOff: 4,
    }),
    workedMin: 10_800,
    regularMin: 10_800,
    extraMin: 0,
    basePaise: 1_800_000,
    extraPaise: 0,
    grossPaise: 1_800_000,
    deductionsPaise: 174_194,
    adjustmentsPaise: -150_000,
    netPaise: 1_475_806,
    deductions,
    days,
    notes: [],
  };
}

/**
 * docs/STAFF.md §4.3 Example 3. Arjun, ₹20,000/month raised to ₹22,000 from 16 Oct, extra hours
 * paid (derived rate) at 1.5×. Tue–Sat 14:00–23:00 and Sun 11:00–00:00, each less 60 min; Monday
 * off. Worked 8 h on the 2 Oct holiday; 8 Oct paid leave, 22 Oct LOP. A deduction for a cracked
 * controller.
 */
export function arjunOctober(runId: string): RunLine {
  const days = daysOf('2026-10-01', '2026-10-31').map((d) => {
    const wd = isoWeekday(d);
    if (wd === 1) return fact(d, 'week_off');
    if (d === '2026-10-02')
      return fact(d, 'holiday', { holiday: HOLIDAY, workedMin: 480, extraMin: 480 });
    if (d === '2026-10-08') return fact(d, 'on_leave', { leavePaid: 1 });
    if (d === '2026-10-22') return fact(d, 'on_leave', { leaveLop: 1 });
    if (wd === 7) return fact(d, 'present', { workedMin: 720, extraMin: 240, presentUnits: 1 });
    return fact(d, 'present', { workedMin: 480, presentUnits: 1 });
  });
  return {
    id: `${runId}-st3`,
    runId,
    staffId: 'st3',
    staffName: 'Arjun Rao',
    payType: 'monthly',
    rates: [
      {
        effectiveFrom: '2026-04-01',
        payType: 'monthly',
        basePaise: 2_000_000,
        extraHoursPaid: true,
        extraHourlyPaise: null,
      },
      {
        effectiveFrom: '2026-10-16',
        payType: 'monthly',
        basePaise: 2_200_000,
        extraHoursPaid: true,
        extraHourlyPaise: null,
      },
    ],
    dayCounts: counts({
      scheduled: 26,
      present: 24,
      paidLeave: 1,
      lopLeave: 1,
      holiday: 1,
      weekOff: 4,
    }),
    workedMin: 12_960,
    regularMin: 11_520,
    extraMin: 1_440,
    basePaise: 2_103_226,
    extraPaise: 300_000,
    grossPaise: 2_403_226,
    deductionsPaise: 70_968,
    adjustmentsPaise: -30_000,
    netPaise: 2_302_258,
    deductions: [
      {
        code: 'lop_leave',
        label: 'LOP leave',
        units: 1,
        ratePaise: 2_200_000 / 31,
        amountPaise: 70_968,
        applied: true,
        note: null,
      },
    ],
    days,
    notes: [],
  };
}

/**
 * docs/STAFF.md §4.3 Example 2. Priya, ₹120/h, week Mon 5 – Sun 11 Oct 2026, 16:00–22:00 less
 * 30 min, Wednesday off; extra hours paid at 1.5×; rounding to the nearest 15 minutes. A split
 * shift on Thursday, a shift past midnight on Friday, a forgotten clock-out on Saturday.
 */
export function priyaWeek(runId: string): RunLine {
  const worked: Record<string, [number, number]> = {
    '2026-10-05': [345, 0],
    '2026-10-06': [330, 0],
    '2026-10-08': [435, 0],
    '2026-10-09': [585, 105],
    '2026-10-10': [330, 0],
    '2026-10-11': [330, 0],
  };
  const days = daysOf('2026-10-05', '2026-10-11').map((d) => {
    const w = worked[d];
    if (!w) return fact(d, 'week_off');
    return fact(d, 'present', {
      workedMin: w[0],
      extraMin: w[1],
      presentUnits: 1,
      flags: d === '2026-10-10' ? ['auto_out'] : [],
    });
  });
  return {
    id: `${runId}-st2`,
    runId,
    staffId: 'st2',
    staffName: 'Priya Nair',
    payType: 'hourly',
    rates: [
      {
        effectiveFrom: '2026-06-01',
        payType: 'hourly',
        basePaise: 12_000,
        extraHoursPaid: true,
        extraHourlyPaise: null,
      },
    ],
    dayCounts: counts({ scheduled: 6, present: 6, weekOff: 1 }),
    workedMin: 2_355,
    regularMin: 2_250,
    extraMin: 105,
    basePaise: 450_000,
    extraPaise: 31_500,
    grossPaise: 481_500,
    deductionsPaise: 0,
    adjustmentsPaise: 0,
    netPaise: 481_500,
    deductions: [],
    days,
    notes: [],
  };
}

function adjustment(
  id: string,
  runId: string,
  staffId: string,
  kind: SalaryAdjustment['kind'],
  amountPaise: number,
  note: string,
  createdAt: string,
): SalaryAdjustment {
  return {
    id,
    runId,
    staffId,
    kind,
    amountPaise,
    note,
    reversesId: null,
    createdBy: 'u0',
    createdAt,
  };
}

function run(
  id: string,
  first: string,
  last: string,
  status: SalaryRun['status'],
  lines: readonly RunLine[],
): SalaryRun {
  return {
    id,
    periodStart: first,
    periodEnd: last,
    status,
    computedAt: '2026-10-13T13:00:00Z',
    ...totals(lines),
    createdBy: 'u0',
    createdAt: '2026-10-13T12:00:00Z',
    finalisedBy: status === 'finalised' ? 'u0' : null,
    finalisedAt: status === 'finalised' ? '2026-10-02T10:00:00Z' : null,
  };
}

function totals(lines: readonly RunLine[]) {
  const sum = (f: (l: RunLine) => number) => lines.reduce((n, l) => n + f(l), 0);
  return {
    staffCount: lines.length,
    grossPaise: sum((l) => l.grossPaise),
    deductionsPaise: sum((l) => l.deductionsPaise),
    adjustmentsPaise: sum((l) => l.adjustmentsPaise),
    netPaise: sum((l) => l.netPaise),
  };
}

/** September, finalised: both monthly staff paid in full (rates must start after 30 Sep). */
function septemberLines(runId: string): RunLine[] {
  const plain = (l: RunLine, base: number): RunLine => ({
    ...l,
    id: `${runId}-${l.staffId}`,
    runId,
    rates: l.rates.slice(0, 1),
    dayCounts: counts({ scheduled: 26, present: 26, weekOff: 4 }),
    workedMin: 26 * 480,
    regularMin: 26 * 480,
    extraMin: 0,
    basePaise: base,
    extraPaise: 0,
    grossPaise: base,
    deductionsPaise: 0,
    adjustmentsPaise: 0,
    netPaise: base,
    deductions: [],
    days: [],
  });
  return [plain(raviOctober(runId), 1_800_000), plain(arjunOctober(runId), 2_000_000)];
}

export const SAMPLE_POLICIES: PayPolicyRow[] = [
  {
    id: 'pp1',
    effectiveFrom: '2026-04-01',
    policy: { ...DEFAULT_PAY_POLICY, extraMultiplier: 1.5 },
    createdBy: 'u0',
    createdAt: '2026-03-25T06:00:00Z',
  },
];

/**
 * Deterministic in-memory PayrollApi for tests: September finalised; October a draft with
 * Examples 1 and 3. `useWeekly()` swaps October for Example 2's weekly run.
 */
export class SamplePayrollApi extends PayrollApi {
  runs: SalaryRun[] = [];
  lines: RunLine[] = [];
  adjustments: SalaryAdjustment[] = [];
  policies: PayPolicyRow[] = [...SAMPLE_POLICIES];
  weekStart = 1;
  /** Every op sent, in order. */
  readonly ops: SyncOp[] = [];
  /** The next send is refused with this code (then cleared). */
  refuse: string | null = null;

  constructor() {
    super();
    const sep = septemberLines('r-sep');
    const oct = [raviOctober('r-oct'), arjunOctober('r-oct')];
    this.lines = [...sep, ...oct];
    this.adjustments = [
      adjustment(
        'ad1',
        'r-oct',
        'st1',
        'advance',
        -200_000,
        'Oct 10 advance',
        '2026-10-10T06:00:00Z',
      ),
      adjustment('ad2', 'r-oct', 'st1', 'bonus', 50_000, 'Diwali', '2026-10-12T06:00:00Z'),
      adjustment(
        'ad3',
        'r-oct',
        'st3',
        'deduction',
        -30_000,
        'Cracked controller, 20 Oct',
        '2026-10-12T07:00:00Z',
      ),
    ];
    this.runs = [
      run('r-oct', '2026-10-01', '2026-10-31', 'draft', oct),
      run('r-sep', '2026-09-01', '2026-09-30', 'finalised', sep),
    ];
  }

  /** Example 2: a weekly arena with Priya's week of 5–11 Oct as the draft. */
  useWeekly(): void {
    const wk = [priyaWeek('r-wk')];
    this.lines = [...this.lines.filter((l) => l.runId === 'r-sep'), ...wk];
    this.adjustments = [];
    this.runs = [
      run('r-wk', '2026-10-05', '2026-10-11', 'draft', wk),
      ...this.runs.filter((r) => r.id === 'r-sep'),
    ];
    this.policies = [
      { ...SAMPLE_POLICIES[0], policy: { ...SAMPLE_POLICIES[0].policy, periodKind: 'weekly' } },
    ];
  }

  async overview(): Promise<PayrollOverview> {
    return {
      runs: [...this.runs],
      policies: this.policies,
      weekStart: this.weekStart,
      people: new Map(SAMPLE_PEOPLE.map((p) => [p.userId, p.name])),
    };
  }

  async detail(_arenaId: string, runId: string): Promise<RunDetail> {
    return {
      lines: this.lines.filter((l) => l.runId === runId),
      adjustments: this.adjustments.filter((a) => a.runId === runId),
    };
  }

  private fail(code: string): never {
    throw new AppError(code, PAYROLL_MESSAGES[code] ?? code);
  }

  private draft(id: unknown): SalaryRun {
    const r = this.runs.find((x) => x.id === id);
    if (!r) this.fail('not_found');
    if (r.status !== 'draft') this.fail('run_not_draft');
    return r;
  }

  /** Rebuilds a line's totals and its run's, as the server would after a decision. */
  private rebuild(runId: string, staffId: string): void {
    this.lines = this.lines.map((l) => {
      if (l.runId !== runId || l.staffId !== staffId) return l;
      const ded = Math.min(
        l.deductions.filter((d) => d.applied).reduce((n, d) => n + d.amountPaise, 0),
        l.grossPaise,
      );
      const adj = this.adjustments
        .filter((a) => a.runId === runId && a.staffId === staffId)
        .reduce((n, a) => n + a.amountPaise, 0);
      return {
        ...l,
        deductionsPaise: ded,
        adjustmentsPaise: adj,
        netPaise: l.grossPaise - ded + adj,
      };
    });
    this.runs = this.runs.map((r) =>
      r.id === runId ? { ...r, ...totals(this.lines.filter((l) => l.runId === runId)) } : r,
    );
  }

  async send(_arenaId: string, op: SyncOp): Promise<Record<string, unknown>> {
    if (this.refuse) {
      const code = this.refuse;
      this.refuse = null;
      this.fail(code);
    }
    this.ops.push(op);
    const p = op.payload;
    const now = '2026-10-13T14:00:00Z';
    switch (op.kind) {
      case 'salary_run.create': {
        const id = String(p['id']);
        this.runs = [
          run(id, String(p['period_start']), String(p['period_end']), 'draft', []),
          ...this.runs,
        ];
        return { staff_count: 0 };
      }
      case 'salary_run.recalculate':
        this.draft(p['id']);
        return {};
      case 'salary_run.set_deduction': {
        const r = this.draft(p['run_id']);
        this.lines = this.lines.map((l) =>
          l.runId === r.id && l.staffId === p['staff_id']
            ? {
                ...l,
                deductions: l.deductions.map((d) =>
                  d.code === p['code']
                    ? { ...d, applied: p['applied'] === true, note: (p['note'] as string) ?? null }
                    : d,
                ),
              }
            : l,
        );
        this.rebuild(r.id, String(p['staff_id']));
        return {};
      }
      case 'salary_adjustment.add': {
        const r = this.draft(p['run_id']);
        if (!String(p['note'] ?? '').trim()) this.fail('note_required');
        const amount = Number(p['amount_paise']);
        if (!(amount > 0)) this.fail('invalid_payload');
        const kind = p['kind'] as SalaryAdjustment['kind'];
        this.adjustments = [
          ...this.adjustments,
          adjustment(
            String(p['id']),
            r.id,
            String(p['staff_id']),
            kind,
            kind === 'bonus' ? amount : -amount,
            String(p['note']),
            now,
          ),
        ];
        this.rebuild(r.id, String(p['staff_id']));
        return {};
      }
      case 'salary_adjustment.reverse': {
        const orig = this.adjustments.find((a) => a.id === p['reverses_id']);
        if (!orig) this.fail('not_found');
        this.draft(orig.runId);
        if (this.adjustments.some((a) => a.reversesId === orig.id)) this.fail('already_reversed');
        this.adjustments = [
          ...this.adjustments,
          {
            ...adjustment(
              String(p['id']),
              orig.runId,
              orig.staffId,
              'reversal',
              -orig.amountPaise,
              String(p['note']),
              now,
            ),
            reversesId: orig.id,
          },
        ];
        this.rebuild(orig.runId, orig.staffId);
        return {};
      }
      case 'salary_run.finalise': {
        const r = this.draft(p['id']);
        const negative = this.lines.find((l) => l.runId === r.id && l.netPaise < 0);
        if (negative) this.fail('net_negative');
        this.runs = this.runs.map((x) =>
          x.id === r.id ? { ...x, status: 'finalised', finalisedBy: 'u0', finalisedAt: now } : x,
        );
        return {};
      }
      case 'salary_run.discard': {
        const r = this.draft(p['id']);
        this.runs = this.runs.map((x) => (x.id === r.id ? { ...x, status: 'discarded' } : x));
        return {};
      }
      default:
        return {};
    }
  }
}
