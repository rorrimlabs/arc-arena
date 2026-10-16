import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import { PAY_TYPES, PayPolicyRow, PayType, parsePayPolicy } from './pay-policy';
import {
  AdjustmentKind,
  DayCounts,
  DayFact,
  Deduction,
  DeductionCode,
  PAYROLL_MESSAGES,
  RateUsed,
  RunDetail,
  RunLine,
  RunStatus,
  SalaryAdjustment,
  SalaryRun,
} from './payroll.models';

/** The runs list and what a new draft needs. */
export interface PayrollOverview {
  readonly runs: readonly SalaryRun[];
  readonly policies: readonly PayPolicyRow[];
  /** ISO weekday weeks start on (settings `work_hours.week_start`, default Monday). */
  readonly weekStart: number;
  /** Staff names by login (finalised_by / created_by point at logins). */
  readonly people: ReadonlyMap<string, string>;
}

/**
 * Salary runs for the current arena (docs/STAFF_API.md › Salary runs): runs, lines and
 * adjustments read through RLS (`payroll` / `payroll_finalise` holders only), the pay rules
 * (`pay_policies`) and the week start, and every action written as an op through sync_push.
 * Tests provide SamplePayrollApi.
 */
@Service({ factory: () => new SupabasePayrollApi() })
export abstract class PayrollApi {
  abstract overview(arenaId: string): Promise<PayrollOverview>;
  abstract detail(arenaId: string, runId: string): Promise<RunDetail>;
  abstract send(arenaId: string, op: SyncOp): Promise<Record<string, unknown>>;
}

type Row = Record<string, unknown>;

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function numOrNull(v: unknown): number | null {
  return v === null || v === undefined || v === '' ? null : num(v);
}

function str(v: unknown): string | null {
  return v === null || v === undefined ? null : String(v);
}

function payType(v: unknown): PayType {
  return PAY_TYPES.includes(v as PayType) ? (v as PayType) : 'monthly';
}

export function toRun(r: Row): SalaryRun {
  return {
    id: String(r['id']),
    periodStart: String(r['period_start']),
    periodEnd: String(r['period_end']),
    status: (['draft', 'finalised', 'discarded'].includes(String(r['status']))
      ? r['status']
      : 'draft') as RunStatus,
    computedAt: str(r['computed_at']),
    staffCount: num(r['staff_count']),
    grossPaise: num(r['gross_paise']),
    deductionsPaise: num(r['deductions_paise']),
    adjustmentsPaise: num(r['adjustments_paise']),
    netPaise: num(r['net_paise']),
    createdBy: String(r['created_by'] ?? ''),
    createdAt: String(r['created_at'] ?? ''),
    finalisedBy: str(r['finalised_by']),
    finalisedAt: str(r['finalised_at']),
  };
}

export function toRate(r: Row): RateUsed {
  return {
    effectiveFrom: String(r['effective_from'] ?? ''),
    payType: payType(r['pay_type']),
    basePaise: num(r['base_paise']),
    extraHoursPaid: r['extra_hours_paid'] === true,
    extraHourlyPaise: numOrNull(r['extra_hourly_paise']),
  };
}

export function toDayCounts(v: unknown): DayCounts {
  const c = (v ?? {}) as Row;
  return {
    scheduled: num(c['scheduled']),
    present: num(c['present']),
    late: num(c['late']),
    halfDay: num(c['half_day']),
    absent: num(c['absent']),
    paidLeave: num(c['paid_leave']),
    lopLeave: num(c['lop_leave']),
    holiday: num(c['holiday']),
    weekOff: num(c['week_off']),
  };
}

export function toDeduction(r: Row): Deduction {
  return {
    code: String(r['code']) as DeductionCode,
    label: String(r['label'] ?? r['code']),
    units: num(r['units']),
    ratePaise: num(r['rate_paise']),
    amountPaise: num(r['amount_paise']),
    applied: r['applied'] !== false,
    note: str(r['note']),
  };
}

export function toDayFact(r: Row): DayFact {
  const h = r['holiday'];
  return {
    day: String(r['day']),
    status: String(r['status'] ?? ''),
    workedMin: num(r['worked_min']),
    extraMin: num(r['extra_min']),
    late: r['late'] === true,
    early: r['early'] === true,
    presentUnits: num(r['present_units']),
    absentUnits: num(r['absent_units']),
    leavePaid: num(r['leave_paid']),
    leaveLop: num(r['leave_lop']),
    holiday: typeof h === 'string' && h ? h : h === true ? 'Holiday' : null,
    flags: Array.isArray(r['flags']) ? (r['flags'] as unknown[]).map(String) : [],
  };
}

function rows(v: unknown): Row[] {
  return Array.isArray(v) ? (v as Row[]) : [];
}

export function toLine(r: Row): RunLine {
  return {
    id: String(r['id']),
    runId: String(r['run_id']),
    staffId: String(r['staff_id']),
    staffName: String(r['staff_name'] ?? ''),
    payType: payType(r['pay_type']),
    rates: rows(r['rates']).map(toRate),
    dayCounts: toDayCounts(r['day_counts']),
    workedMin: num(r['worked_min']),
    regularMin: num(r['regular_min']),
    extraMin: num(r['extra_min']),
    basePaise: num(r['base_paise']),
    extraPaise: num(r['extra_paise']),
    grossPaise: num(r['gross_paise']),
    deductionsPaise: num(r['deductions_paise']),
    adjustmentsPaise: num(r['adjustments_paise']),
    netPaise: num(r['net_paise']),
    deductions: rows(r['deductions']).map(toDeduction),
    days: rows(r['days']).map(toDayFact),
    notes: Array.isArray(r['notes']) ? (r['notes'] as unknown[]).map(String) : [],
  };
}

export function toAdjustment(r: Row): SalaryAdjustment {
  return {
    id: String(r['id']),
    runId: String(r['run_id']),
    staffId: String(r['staff_id']),
    kind: String(r['kind']) as AdjustmentKind,
    amountPaise: num(r['amount_paise']),
    note: String(r['note'] ?? ''),
    reversesId: str(r['reverses_id']),
    createdBy: String(r['created_by'] ?? ''),
    createdAt: String(r['created_at'] ?? ''),
  };
}

export function toPolicyRow(r: Row): PayPolicyRow {
  return {
    id: String(r['id']),
    effectiveFrom: String(r['effective_from']),
    policy: parsePayPolicy(r['policy']),
    createdBy: String(r['created_by'] ?? ''),
    createdAt: String(r['created_at'] ?? ''),
  };
}

/** `work_hours.week_start` (1–7), default 1 (Monday). */
export function weekStartOf(json: unknown): number {
  const n = Number((json as Row | null)?.['week_start']);
  return Number.isInteger(n) && n >= 1 && n <= 7 ? n : 1;
}

class SupabasePayrollApi extends PayrollApi {
  private readonly supabase = inject(Supabase);

  async overview(arenaId: string): Promise<PayrollOverview> {
    const client = await this.supabase.client();
    const [runs, policies, hours, staff] = await Promise.all([
      client
        .from('salary_runs')
        .select('*')
        .eq('arena_id', arenaId)
        .order('period_start', { ascending: false }),
      client
        .from('pay_policies')
        .select('id, effective_from, policy, created_by, created_at')
        .eq('arena_id', arenaId)
        .order('effective_from'),
      client
        .from('settings')
        .select('json')
        .eq('arena_id', arenaId)
        .eq('key', 'work_hours')
        .maybeSingle(),
      client.from('staff_profiles').select('user_id, name').eq('arena_id', arenaId),
    ]);
    for (const r of [runs, policies, hours, staff]) if (r.error) throw dbError(r.error);
    return {
      runs: ((runs.data as Row[]) ?? []).map(toRun),
      policies: ((policies.data as Row[]) ?? []).map(toPolicyRow),
      weekStart: weekStartOf((hours.data as { json?: unknown } | null)?.json),
      people: new Map(
        ((staff.data as Row[]) ?? []).map((s) => [String(s['user_id']), String(s['name'])]),
      ),
    };
  }

  async detail(arenaId: string, runId: string): Promise<RunDetail> {
    const client = await this.supabase.client();
    const [lines, adjustments] = await Promise.all([
      client
        .from('salary_run_lines')
        .select('*')
        .eq('arena_id', arenaId)
        .eq('run_id', runId)
        .order('staff_name'),
      client
        .from('salary_adjustments')
        .select('*')
        .eq('arena_id', arenaId)
        .eq('run_id', runId)
        .order('created_at'),
    ]);
    if (lines.error) throw dbError(lines.error);
    if (adjustments.error) throw dbError(adjustments.error);
    return {
      lines: ((lines.data as Row[]) ?? []).map(toLine),
      adjustments: ((adjustments.data as Row[]) ?? []).map(toAdjustment),
    };
  }

  async send(arenaId: string, op: SyncOp): Promise<Record<string, unknown>> {
    const [result] = await pushOps(await this.supabase.client(), arenaId, [op], PAYROLL_MESSAGES);
    return result ?? {};
  }
}
