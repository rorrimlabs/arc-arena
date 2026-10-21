import { Service, inject } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import {
  HalfDay,
  LEAVE_MESSAGES,
  LeaveAdjustment,
  LeaveBalance,
  LeaveData,
  LeaveKind,
  LeaveRequest,
  LeaveStaff,
  LeaveStatus,
} from './leave.models';

/**
 * Leave for the current arena (docs/STAFF_API.md › Leave): staff names, every request and
 * balance adjustment read through RLS (`leave_approve` holders see the arena's rows), the
 * balances from the `leave_balances` RPC, and the decisions written as ops through sync_push.
 * None of it is in the sync_pull feed; live updates come from the writers' broadcast nudge.
 * Tests provide SampleLeaveApi.
 */
@Service({ factory: () => new SupabaseLeaveApi() })
export abstract class LeaveApi {
  abstract load(arenaId: string): Promise<LeaveData>;
  /** leave_balances(p_arena, p_staff): everyone's current leave year, or one person's. */
  abstract balances(arenaId: string, staffId: string | null): Promise<LeaveBalance[]>;
  /** One op (`leave.decide`, `leave.adjust`, `leave.record`); refusals throw with plain words. */
  abstract send(arenaId: string, op: SyncOp): Promise<Record<string, unknown>>;
}

type Row = Record<string, unknown>;
const PAGE = 1000;

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

export function toLeaveRequest(r: Row): LeaveRequest {
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    kind: (r['kind'] === 'unplanned' ? 'unplanned' : 'planned') as LeaveKind,
    fromDate: String(r['from_date']),
    toDate: String(r['to_date']),
    halfDay: (str(r['half_day']) ?? 'none') as HalfDay,
    days: num(r['days']),
    paidDays: numOrNull(r['paid_days']),
    lopDays: numOrNull(r['lop_days']),
    reason: String(r['reason'] ?? ''),
    status: String(r['status']) as LeaveStatus,
    decidedBy: str(r['decided_by']),
    decidedAt: str(r['decided_at']),
    decisionNote: str(r['decision_note']),
    cancelReason: str(r['cancel_reason']),
    createdBy: String(r['created_by'] ?? ''),
    createdAt: String(r['created_at'] ?? ''),
    updatedAt: String(r['updated_at'] ?? r['created_at'] ?? ''),
  };
}

export function toLeaveAdjustment(r: Row): LeaveAdjustment {
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    yearStart: String(r['year_start']),
    days: num(r['days']),
    reason: String(r['reason'] ?? ''),
    createdBy: String(r['created_by'] ?? ''),
    createdAt: String(r['created_at'] ?? ''),
  };
}

export function toLeaveBalance(r: Row): LeaveBalance {
  return {
    staffId: String(r['staff_id']),
    staffName: String(r['staff_name'] ?? ''),
    joinedOn: String(r['joined_on'] ?? ''),
    yearStart: String(r['year_start'] ?? ''),
    yearEnd: String(r['year_end'] ?? ''),
    allowance: num(r['allowance']),
    adjustments: num(r['adjustments']),
    used: num(r['used']),
    pending: num(r['pending']),
    balance: num(r['balance']),
  };
}

export function toLeaveStaff(r: Row): LeaveStaff {
  return {
    id: String(r['id']),
    userId: String(r['user_id'] ?? ''),
    name: String(r['name'] ?? ''),
    role: r['role'] === 'owner' ? 'owner' : 'staff',
    active: r['active'] === true,
  };
}

class SupabaseLeaveApi extends LeaveApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<LeaveData> {
    const client = await this.supabase.client();
    const [staff, requests, adjustments] = await Promise.all([
      this.rows(client, 'staff_profiles', 'id, user_id, name, role, active', arenaId, 'name'),
      this.rows(client, 'leave_requests', '*', arenaId, 'from_date'),
      this.rows(client, 'leave_adjustments', '*', arenaId, 'created_at'),
    ]);
    return {
      staff: staff.map(toLeaveStaff),
      requests: requests.map(toLeaveRequest),
      adjustments: adjustments.map(toLeaveAdjustment),
    };
  }

  async balances(arenaId: string, staffId: string | null): Promise<LeaveBalance[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('leave_balances', {
      p_arena: arenaId,
      p_staff: staffId,
    });
    if (error) throw dbError(error);
    return ((data as Row[] | null) ?? []).map(toLeaveBalance);
  }

  async send(arenaId: string, op: SyncOp): Promise<Record<string, unknown>> {
    const [result] = await pushOps(await this.supabase.client(), arenaId, [op], LEAVE_MESSAGES);
    return result ?? {};
  }

  private async rows(
    client: SupabaseClient,
    table: string,
    columns: string,
    arenaId: string,
    order: string,
  ): Promise<Row[]> {
    const out: Row[] = [];
    for (let from = 0; ; from += PAGE) {
      const { data, error } = await client
        .from(table)
        .select(columns)
        .eq('arena_id', arenaId)
        .order(order)
        .order('id')
        .range(from, from + PAGE - 1);
      if (error) throw dbError(error);
      const rows = (data as unknown as Row[]) ?? [];
      out.push(...rows);
      if (rows.length < PAGE) return out;
    }
  }
}
