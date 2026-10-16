import { AppError } from '../../../core/auth/auth-api';
import { SyncOp } from '../../../core/sync/push-ops';
import { LeaveApi } from './leave-api';
import {
  LEAVE_MESSAGES,
  LeaveAdjustment,
  LeaveBalance,
  LeaveData,
  LeaveRequest,
  LeaveStaff,
} from './leave.models';

/**
 * The sample arena's people, shared by the leave, pay setup and payroll samples. The signed-in
 * sample login (u0, Arjun Mehra) is the owner.
 */
export const SAMPLE_PEOPLE: readonly LeaveStaff[] = [
  { id: 'st0', userId: 'u0', name: 'Arjun Mehra', role: 'owner', active: true },
  { id: 'st1', userId: 'u1', name: 'Ravi Kumar', role: 'staff', active: true },
  { id: 'st2', userId: 'u2', name: 'Priya Nair', role: 'staff', active: true },
  { id: 'st3', userId: 'u3', name: 'Arjun Rao', role: 'staff', active: true },
  { id: 'st4', userId: 'u4', name: 'Kavya Iyer', role: 'staff', active: false },
];

function request(
  id: string,
  staffId: string,
  over: Partial<LeaveRequest> & Pick<LeaveRequest, 'fromDate' | 'toDate' | 'days'>,
): LeaveRequest {
  const userId = SAMPLE_PEOPLE.find((p) => p.id === staffId)?.userId ?? '';
  return {
    id,
    staffId,
    kind: 'planned',
    halfDay: 'none',
    paidDays: null,
    lopDays: null,
    reason: '',
    status: 'pending',
    decidedBy: null,
    decidedAt: null,
    decisionNote: null,
    cancelReason: null,
    createdBy: userId,
    createdAt: '2026-10-10T05:00:00Z',
    updatedAt: '2026-10-10T05:00:00Z',
    ...over,
  };
}

/**
 * Sample requests around NOW (Tue 13 Oct 2026): Ravi's 2-day request with 1 day of balance left
 * (so the approver sees 1 paid · 1 LOP), Priya's half day, her cancellation of an approved trip,
 * the owner's own request, Arjun Rao's approved paid and LOP days (docs/STAFF.md §4.3 Example 3),
 * and older decided ones.
 */
export function sampleLeaveRequests(): LeaveRequest[] {
  return [
    request('lr1', 'st1', {
      fromDate: '2026-10-21',
      toDate: '2026-10-22',
      days: 2,
      reason: 'Sister’s wedding',
      createdAt: '2026-10-09T06:00:00Z',
      updatedAt: '2026-10-09T06:00:00Z',
    }),
    request('lr2', 'st2', {
      kind: 'unplanned',
      fromDate: '2026-10-12',
      toDate: '2026-10-12',
      halfDay: 'first_half',
      days: 0.5,
      reason: 'Fever',
      createdAt: '2026-10-12T03:00:00Z',
      updatedAt: '2026-10-12T03:00:00Z',
    }),
    request('lr3', 'st2', {
      fromDate: '2026-10-28',
      toDate: '2026-10-29',
      days: 2,
      paidDays: 2,
      lopDays: 0,
      reason: 'Trip home',
      status: 'cancel_pending',
      decidedBy: 'u0',
      decidedAt: '2026-10-05T08:00:00Z',
      cancelReason: 'Trip called off',
      createdAt: '2026-10-04T08:00:00Z',
      updatedAt: '2026-10-11T09:00:00Z',
    }),
    request('lr4', 'st0', {
      fromDate: '2026-10-23',
      toDate: '2026-10-23',
      days: 1,
      reason: 'Family function',
      createdAt: '2026-10-11T04:00:00Z',
      updatedAt: '2026-10-11T04:00:00Z',
    }),
    request('lr5', 'st3', {
      fromDate: '2026-10-08',
      toDate: '2026-10-08',
      days: 1,
      paidDays: 1,
      lopDays: 0,
      reason: 'Bank work',
      status: 'approved',
      decidedBy: 'u0',
      decidedAt: '2026-10-02T06:00:00Z',
      createdAt: '2026-10-01T06:00:00Z',
      updatedAt: '2026-10-02T06:00:00Z',
    }),
    request('lr6', 'st3', {
      kind: 'unplanned',
      fromDate: '2026-10-22',
      toDate: '2026-10-22',
      days: 1,
      paidDays: 0,
      lopDays: 1,
      reason: 'Fever',
      status: 'approved',
      decidedBy: 'u0',
      decidedAt: '2026-10-12T06:00:00Z',
      decisionNote: 'No balance left: LOP',
      createdAt: '2026-10-12T05:00:00Z',
      updatedAt: '2026-10-12T06:00:00Z',
    }),
    request('lr7', 'st1', {
      fromDate: '2026-10-01',
      toDate: '2026-10-02',
      days: 1,
      reason: 'Diwali shopping',
      status: 'rejected',
      decidedBy: 'u0',
      decidedAt: '2026-09-28T06:00:00Z',
      decisionNote: 'Short-staffed that week',
      createdAt: '2026-09-27T06:00:00Z',
      updatedAt: '2026-09-28T06:00:00Z',
    }),
    request('lr8', 'st4', {
      fromDate: '2026-09-14',
      toDate: '2026-09-15',
      days: 2,
      reason: 'Exams',
      status: 'cancelled',
      createdAt: '2026-09-01T06:00:00Z',
      updatedAt: '2026-09-03T06:00:00Z',
    }),
  ];
}

export function sampleLeaveBalances(): LeaveBalance[] {
  const b = (
    staffId: string,
    joinedOn: string,
    yearStart: string,
    yearEnd: string,
    allowance: number,
    adjustments: number,
    used: number,
    pending: number,
  ): LeaveBalance => ({
    staffId,
    staffName: SAMPLE_PEOPLE.find((p) => p.id === staffId)?.name ?? '',
    joinedOn,
    yearStart,
    yearEnd,
    allowance,
    adjustments,
    used,
    pending,
    balance: allowance + adjustments - used,
  });
  return [
    b('st0', '2025-04-01', '2026-04-01', '2027-03-31', 12, 0, 0, 1),
    b('st1', '2024-11-20', '2025-11-20', '2026-11-19', 12, 0, 11, 2),
    b('st2', '2026-02-01', '2026-02-01', '2027-01-31', 12, 1, 3, 2.5),
    b('st3', '2025-10-01', '2026-10-01', '2027-09-30', 1, 0, 1, 0),
    b('st4', '2025-06-15', '2026-06-15', '2027-06-14', 12, 0, 0, 0),
  ];
}

export function sampleLeaveAdjustments(): LeaveAdjustment[] {
  return [
    {
      id: 'la1',
      staffId: 'st2',
      yearStart: '2026-02-01',
      days: 1,
      reason: 'Worked on Holi',
      createdBy: 'u0',
      createdAt: '2026-03-15T06:00:00Z',
    },
  ];
}

/** Deterministic in-memory LeaveApi for tests; applies decisions as the server would (roughly). */
export class SampleLeaveApi extends LeaveApi {
  staff: LeaveStaff[] = [...SAMPLE_PEOPLE];
  requests = sampleLeaveRequests();
  adjustments = sampleLeaveAdjustments();
  balanceRows = sampleLeaveBalances();
  /** Every op sent, in order. */
  readonly ops: SyncOp[] = [];
  /** Every balances call's staff argument. */
  readonly balanceCalls: (string | null)[] = [];
  /** The next send is refused with this code (then cleared). */
  refuse: string | null = null;

  async load(): Promise<LeaveData> {
    return { staff: this.staff, requests: this.requests, adjustments: this.adjustments };
  }

  async balances(_arenaId: string, staffId: string | null): Promise<LeaveBalance[]> {
    this.balanceCalls.push(staffId);
    return this.balanceRows.filter((b) => !staffId || b.staffId === staffId);
  }

  async send(_arenaId: string, op: SyncOp): Promise<Record<string, unknown>> {
    if (this.refuse) {
      const code = this.refuse;
      this.refuse = null;
      throw new AppError(code, LEAVE_MESSAGES[code] ?? code);
    }
    this.ops.push(op);
    const p = op.payload;
    if (op.kind === 'leave.decide') {
      const r = this.requests.find((x) => x.id === p['id']);
      if (!r) throw new AppError('not_found', LEAVE_MESSAGES['not_found']);
      const approve = p['approve'] === true;
      const at = '2026-10-13T14:00:00Z';
      const decided = {
        decidedBy: 'u0',
        decidedAt: at,
        decisionNote: (p['note'] as string) ?? null,
        updatedAt: at,
      };
      let next: LeaveRequest;
      if (r.status === 'pending') {
        const paid = Number(p['paid_days'] ?? r.days);
        next = approve
          ? { ...r, ...decided, status: 'approved', paidDays: paid, lopDays: r.days - paid }
          : { ...r, ...decided, status: 'rejected' };
      } else if (r.status === 'cancel_pending') {
        next = approve
          ? { ...r, ...decided, status: 'cancelled', paidDays: null, lopDays: null }
          : { ...r, ...decided, status: 'approved' };
      } else {
        throw new AppError('invalid_state', LEAVE_MESSAGES['invalid_state']);
      }
      this.requests = this.requests.map((x) => (x.id === r.id ? next : x));
    } else if (op.kind === 'leave.adjust') {
      const staffId = String(p['staff_id']);
      const days = Number(p['days']);
      const row = this.balanceRows.find((b) => b.staffId === staffId);
      this.adjustments = [
        ...this.adjustments,
        {
          id: `la${this.adjustments.length + 1}`,
          staffId,
          yearStart: row?.yearStart ?? '',
          days,
          reason: String(p['reason']),
          createdBy: 'u0',
          createdAt: '2026-10-13T14:00:00Z',
        },
      ];
      this.balanceRows = this.balanceRows.map((b) =>
        b.staffId === staffId
          ? { ...b, adjustments: b.adjustments + days, balance: b.balance + days }
          : b,
      );
    }
    return {};
  }
}
