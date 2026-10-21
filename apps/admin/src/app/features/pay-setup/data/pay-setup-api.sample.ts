import { AppError } from '../../../core/auth/auth-api';
import { SyncOp } from '../../../core/sync/push-ops';
import { SAMPLE_PEOPLE } from '../../leave/data/leave-api.sample';
import { PayPolicyRow, parsePayPolicy } from '../../payroll/data/pay-policy';
import { SAMPLE_POLICIES } from '../../payroll/data/payroll-api.sample';
import { PaySetupApi } from './pay-setup-api';
import { toHrProfile, toPayRate } from './pay-setup-api';
import { HrProfile, PAY_SETUP_MESSAGES, PaySetupData, PayRate, PayStaff } from './pay-setup.models';

function rate(
  id: string,
  staffId: string,
  effectiveFrom: string,
  payType: PayRate['payType'],
  basePaise: number,
  extraHoursPaid: boolean,
  note: string | null = null,
): PayRate {
  return {
    id,
    staffId,
    effectiveFrom,
    payType,
    basePaise,
    extraHoursPaid,
    extraHourlyPaise: null,
    note,
    createdBy: 'u0',
    createdAt: `${effectiveFrom}T00:00:00Z`,
  };
}

/** The pay rates of docs/STAFF.md §4.3 (Ravi, Priya, Arjun with his raise from 16 Oct). */
export function samplePayRates(): PayRate[] {
  return [
    rate('pr1', 'st1', '2026-04-01', 'monthly', 1_800_000, false),
    rate('pr2', 'st2', '2026-06-01', 'hourly', 12_000, true),
    rate('pr3', 'st3', '2026-04-01', 'monthly', 2_000_000, true),
    rate('pr4', 'st3', '2026-10-16', 'monthly', 2_200_000, true, 'Raise after review'),
  ];
}

export function sampleHrProfiles(): HrProfile[] {
  return [
    {
      staffId: 'st1',
      joinedOn: '2024-11-20',
      leftOn: null,
      tracksAttendance: true,
      employeeCode: 'E-014',
      paidLeaveDays: null,
      standardDayMin: null,
    },
    {
      staffId: 'st3',
      joinedOn: '2025-10-01',
      leftOn: null,
      tracksAttendance: true,
      employeeCode: 'E-021',
      paidLeaveDays: 1,
      standardDayMin: 480,
    },
  ];
}

/** Deterministic in-memory PaySetupApi for tests; applies the ops as the server would (roughly). */
export class SamplePaySetupApi extends PaySetupApi {
  staff: PayStaff[] = SAMPLE_PEOPLE.map((p) => ({ ...p, createdAt: '2026-01-05T06:00:00Z' }));
  profiles = sampleHrProfiles();
  rates = samplePayRates();
  policies: PayPolicyRow[] = [...SAMPLE_POLICIES];
  /** September is finalised (sample payroll). */
  finalisedEnd: string | null = '2026-09-30';
  readonly ops: SyncOp[] = [];
  refuse: string | null = null;

  async load(): Promise<PaySetupData> {
    return {
      staff: this.staff,
      profiles: this.profiles,
      rates: this.rates,
      policies: this.policies,
      finalisedEnd: this.finalisedEnd,
      defaults: { standardDayMin: 480, paidLeaveDays: 12 },
    };
  }

  async send(_arenaId: string, op: SyncOp): Promise<Record<string, unknown>> {
    if (this.refuse) {
      const code = this.refuse;
      this.refuse = null;
      throw new AppError(code, PAY_SETUP_MESSAGES[code] ?? code);
    }
    this.ops.push(op);
    const p = op.payload;
    const finalised = (day: unknown) => !!this.finalisedEnd && String(day) <= this.finalisedEnd;
    if (op.kind === 'hr_profile.save') {
      const row = toHrProfile(p);
      this.profiles = [...this.profiles.filter((x) => x.staffId !== row.staffId), row];
    } else if (op.kind === 'pay_rate.add') {
      if (finalised(p['effective_from'])) {
        throw new AppError(
          'rate_in_finalised_period',
          PAY_SETUP_MESSAGES['rate_in_finalised_period'],
        );
      }
      const r = toPayRate({ ...p, created_by: 'u0', created_at: '2026-10-13T14:00:00Z' });
      if (this.rates.some((x) => x.staffId === r.staffId && x.effectiveFrom === r.effectiveFrom)) {
        throw new AppError('duplicate', PAY_SETUP_MESSAGES['duplicate']);
      }
      this.rates = [...this.rates, r];
    } else if (op.kind === 'pay_policy.add') {
      if (finalised(p['effective_from'])) {
        throw new AppError(
          'rate_in_finalised_period',
          PAY_SETUP_MESSAGES['rate_in_finalised_period'],
        );
      }
      this.policies = [
        ...this.policies,
        {
          id: String(p['id']),
          effectiveFrom: String(p['effective_from']),
          policy: parsePayPolicy(p['policy']),
          createdBy: 'u0',
          createdAt: '2026-10-13T14:00:00Z',
        },
      ];
    }
    return {};
  }
}
