import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import { PAY_TYPES, PayType } from '../../payroll/data/pay-policy';
import { toPolicyRow } from '../../payroll/data/payroll-api';
import { lastFinalisedEnd } from '../../payroll/data/payroll.models';
import { HrProfile, PAY_SETUP_MESSAGES, PaySetupData, PayRate, PayStaff } from './pay-setup.models';

/**
 * Pay setup for the current arena: every staff profile (inactive ones too), their HR profiles
 * and pay rates, the arena's pay rules, the end of the last finalised run, and the arena
 * defaults (`work_hours.standard_day_min`, `leave_rules.paid_leave_days`), read through RLS
 * (`payroll` holders only); writes are `hr_profile.save`, `pay_rate.add` and `pay_policy.add`
 * through sync_push. Tests provide SamplePaySetupApi.
 */
@Service({ factory: () => new SupabasePaySetupApi() })
export abstract class PaySetupApi {
  abstract load(arenaId: string): Promise<PaySetupData>;
  abstract send(arenaId: string, op: SyncOp): Promise<Record<string, unknown>>;
}

type Row = Record<string, unknown>;

function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function str(v: unknown): string | null {
  return v === null || v === undefined || v === '' ? null : String(v);
}

export function toPayStaff(r: Row): PayStaff {
  return {
    id: String(r['id']),
    userId: String(r['user_id'] ?? ''),
    name: String(r['name'] ?? ''),
    role: r['role'] === 'owner' ? 'owner' : 'staff',
    active: r['active'] === true,
    createdAt: String(r['created_at'] ?? ''),
  };
}

export function toHrProfile(r: Row): HrProfile {
  return {
    staffId: String(r['staff_id']),
    joinedOn: str(r['joined_on']),
    leftOn: str(r['left_on']),
    tracksAttendance: r['tracks_attendance'] !== false,
    employeeCode: str(r['employee_code']),
    paidLeaveDays: numOrNull(r['paid_leave_days']),
    standardDayMin: numOrNull(r['standard_day_min']),
  };
}

export function toPayRate(r: Row): PayRate {
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    effectiveFrom: String(r['effective_from']),
    payType: (PAY_TYPES.includes(r['pay_type'] as PayType) ? r['pay_type'] : 'monthly') as PayType,
    basePaise: Number(r['base_paise'] ?? 0),
    extraHoursPaid: r['extra_hours_paid'] === true,
    extraHourlyPaise: numOrNull(r['extra_hourly_paise']),
    note: str(r['note']),
    createdBy: String(r['created_by'] ?? ''),
    createdAt: String(r['created_at'] ?? ''),
  };
}

class SupabasePaySetupApi extends PaySetupApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<PaySetupData> {
    const client = await this.supabase.client();
    const [staff, profiles, rates, policies, runs, settings] = await Promise.all([
      client
        .from('staff_profiles')
        .select('id, user_id, name, role, active, created_at')
        .eq('arena_id', arenaId)
        .order('name'),
      client.from('staff_hr_profiles').select('*').eq('arena_id', arenaId),
      client.from('staff_pay_rates').select('*').eq('arena_id', arenaId).order('effective_from'),
      client
        .from('pay_policies')
        .select('id, effective_from, policy, created_by, created_at')
        .eq('arena_id', arenaId)
        .order('effective_from'),
      client
        .from('salary_runs')
        .select('status, period_end')
        .eq('arena_id', arenaId)
        .eq('status', 'finalised'),
      client
        .from('settings')
        .select('key, json')
        .eq('arena_id', arenaId)
        .in('key', ['work_hours', 'leave_rules']),
    ]);
    for (const r of [staff, profiles, rates, policies, runs, settings]) {
      if (r.error) throw dbError(r.error);
    }
    const json = (key: string) =>
      (((settings.data as Row[]) ?? []).find((s) => s['key'] === key)?.['json'] ?? {}) as Row;
    const std = Number(json('work_hours')['standard_day_min']);
    const paid = Number(json('leave_rules')['paid_leave_days']);
    return {
      staff: ((staff.data as Row[]) ?? []).map(toPayStaff),
      profiles: ((profiles.data as Row[]) ?? []).map(toHrProfile),
      rates: ((rates.data as Row[]) ?? []).map(toPayRate),
      policies: ((policies.data as Row[]) ?? []).map(toPolicyRow),
      finalisedEnd: lastFinalisedEnd(
        ((runs.data as Row[]) ?? []).map((r) => ({
          status: 'finalised' as const,
          periodEnd: String(r['period_end']),
        })),
      ),
      defaults: {
        standardDayMin: Number.isInteger(std) && std >= 60 && std <= 1440 ? std : 480,
        paidLeaveDays: Number.isFinite(paid) && paid >= 0 && paid <= 366 ? paid : 12,
      },
    };
  }

  async send(arenaId: string, op: SyncOp): Promise<Record<string, unknown>> {
    const [result] = await pushOps(await this.supabase.client(), arenaId, [op], PAY_SETUP_MESSAGES);
    return result ?? {};
  }
}
