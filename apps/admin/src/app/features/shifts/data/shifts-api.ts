import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import {
  ArenaHoliday,
  SHIFT_MESSAGES,
  Shift,
  ShiftAssignment,
  ShiftsData,
  StaffHoliday,
  StaffName,
} from './shifts.models';

/**
 * Shifts, assignments and staff holidays: read through RLS (every member may read them; none is
 * in the sync_pull feed), written as `shift.*` / `staff_holiday.*` ops through sync_push (the
 * server needs `settings`). Tests provide SampleShiftsApi.
 */
@Service({ factory: () => new SupabaseShiftsApi() })
export abstract class ShiftsApi {
  abstract load(arenaId: string): Promise<ShiftsData>;
  /** The price list's holidays from `first` to `last` (IST days, inclusive). */
  abstract arenaHolidays(arenaId: string, first: string, last: string): Promise<ArenaHoliday[]>;
  /** Sends the ops in one sync_push call; the first refusal is thrown in plain words. */
  abstract push(arenaId: string, ops: readonly SyncOp[]): Promise<void>;
}

type Row = Record<string, unknown>;

export function toShift(r: Row): Shift {
  return {
    id: String(r['id']),
    name: String(r['name'] ?? ''),
    startMin: Number(r['start_min']),
    endMin: Number(r['end_min']),
    days: ((r['days'] as number[] | null) ?? []).map(Number).sort((a, b) => a - b),
    breakMin: Number(r['break_min'] ?? 0),
    active: r['active'] !== false,
  };
}

export function toAssignment(r: Row): ShiftAssignment {
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    shiftId: String(r['shift_id']),
    effectiveFrom: String(r['effective_from']),
    effectiveTo: r['effective_to'] === null || r['effective_to'] === undefined
      ? null
      : String(r['effective_to']),
  };
}

export function toStaffHoliday(r: Row): StaffHoliday {
  return {
    id: String(r['id']),
    day: String(r['day']),
    name: String(r['name'] ?? ''),
    paid: r['paid'] !== false,
  };
}

class SupabaseShiftsApi extends ShiftsApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<ShiftsData> {
    const client = await this.supabase.client();
    const [shifts, assignments, holidays, staff] = await Promise.all([
      client
        .from('shifts')
        .select('id, name, start_min, end_min, days, break_min, active')
        .eq('arena_id', arenaId)
        .order('start_min')
        .order('name'),
      client
        .from('staff_shifts')
        .select('id, staff_id, shift_id, effective_from, effective_to')
        .eq('arena_id', arenaId)
        .order('effective_from'),
      client
        .from('staff_holidays')
        .select('id, day, name, paid')
        .eq('arena_id', arenaId)
        .order('day'),
      client
        .from('staff_profiles')
        .select('id, name, active')
        .eq('arena_id', arenaId)
        .order('name'),
    ]);
    for (const r of [shifts, assignments, holidays, staff]) {
      if (r.error) throw dbError(r.error);
    }
    return {
      shifts: (shifts.data as Row[]).map(toShift),
      assignments: (assignments.data as Row[]).map(toAssignment),
      holidays: (holidays.data as Row[]).map(toStaffHoliday),
      staff: (staff.data as Row[]).map(
        (r): StaffName => ({
          id: String(r['id']),
          name: String(r['name']),
          active: r['active'] === true,
        }),
      ),
    };
  }

  async arenaHolidays(arenaId: string, first: string, last: string): Promise<ArenaHoliday[]> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('holidays')
      .select('day, name')
      .eq('arena_id', arenaId)
      .gte('day', first)
      .lte('day', last)
      .order('day');
    if (error) throw dbError(error);
    return (data as Row[]).map((r) => ({ day: String(r['day']), name: String(r['name'] ?? '') }));
  }

  async push(arenaId: string, ops: readonly SyncOp[]): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, ops, SHIFT_MESSAGES);
  }
}
