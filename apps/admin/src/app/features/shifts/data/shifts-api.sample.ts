import { PushRefusal, SyncOp } from '../../../core/sync/push-ops';
import { ShiftsApi, toAssignment, toShift } from './shifts-api';
import {
  ArenaHoliday,
  SHIFT_MESSAGES,
  Shift,
  ShiftAssignment,
  ShiftsData,
  StaffHoliday,
  StaffName,
  overlappingAssignment,
} from './shifts.models';

export const SAMPLE_SHIFT_STAFF: StaffName[] = [
  { id: 's1', name: 'Priya Nair', active: true },
  { id: 's2', name: 'Rohan Das', active: true },
  { id: 's3', name: 'Kavya Iyer', active: true },
];

/** Morning 9 am – 6 pm Mon–Sat (1 h break); Night 6 pm → 2 am Fri–Sun (30 min); Old split, off. */
export function sampleShifts(): Shift[] {
  return [
    {
      id: 'sh1',
      name: 'Morning',
      startMin: 540,
      endMin: 1080,
      days: [1, 2, 3, 4, 5, 6],
      breakMin: 60,
      active: true,
    },
    {
      id: 'sh2',
      name: 'Night',
      startMin: 1080,
      endMin: 120,
      days: [5, 6, 7],
      breakMin: 30,
      active: true,
    },
    {
      id: 'sh3',
      name: 'Old split',
      startMin: 600,
      endMin: 840,
      days: [1, 2],
      breakMin: 0,
      active: false,
    },
  ];
}

export function sampleAssignments(): ShiftAssignment[] {
  return [
    { id: 'as1', staffId: 's1', shiftId: 'sh1', effectiveFrom: '2026-10-01', effectiveTo: null },
    {
      id: 'as2',
      staffId: 's2',
      shiftId: 'sh2',
      effectiveFrom: '2026-09-01',
      effectiveTo: '2026-12-31',
    },
    { id: 'as3', staffId: 's3', shiftId: 'sh1', effectiveFrom: '2026-10-14', effectiveTo: null },
  ];
}

export function sampleStaffHolidays(): StaffHoliday[] {
  return [{ id: 'h1', day: '2026-10-20', name: 'Diwali', paid: true }];
}

/** The price list's holidays: Diwali is already a staff holiday; 2028 is outside any window. */
export function sampleArenaHolidays(): ArenaHoliday[] {
  return [
    { day: '2026-10-20', name: 'Diwali' },
    { day: '2026-11-05', name: 'Guru Nanak Jayanti' },
    { day: '2026-12-25', name: 'Christmas' },
    { day: '2028-01-01', name: 'New Year' },
  ];
}

/** Deterministic in-memory ShiftsApi for tests; applies ops as the server would. */
export class SampleShiftsApi extends ShiftsApi {
  shifts = sampleShifts();
  assignments = sampleAssignments();
  holidays = sampleStaffHolidays();
  staff = [...SAMPLE_SHIFT_STAFF];
  arena = sampleArenaHolidays();
  /** Every op sent, in order. */
  readonly ops: SyncOp[] = [];
  /** Each push call's ops (one sync_push call each). */
  readonly pushes: SyncOp[][] = [];
  /** Asked arena-holiday windows, as [first, last]. */
  readonly holidayReads: [string, string][] = [];
  private nextId = 1;

  async load(): Promise<ShiftsData> {
    return {
      shifts: [...this.shifts],
      assignments: [...this.assignments],
      holidays: [...this.holidays].sort((a, b) => a.day.localeCompare(b.day)),
      staff: [...this.staff],
    };
  }

  async arenaHolidays(_arenaId: string, first: string, last: string): Promise<ArenaHoliday[]> {
    this.holidayReads.push([first, last]);
    return this.arena.filter((h) => h.day >= first && h.day <= last);
  }

  async push(_arenaId: string, ops: readonly SyncOp[]): Promise<void> {
    this.pushes.push([...ops]);
    const applied: string[] = [];
    for (const op of ops) {
      const refusal = this.apply(op);
      if (refusal) throw new PushRefusal(refusal, SHIFT_MESSAGES[refusal] ?? refusal, applied);
      this.ops.push(op);
      applied.push(op.kind);
    }
  }

  /** Applies one op; returns the refusal code, if any. */
  private apply(op: SyncOp): string | null {
    const p = op.payload;
    switch (op.kind) {
      case 'shift.upsert': {
        const shift = toShift(p);
        const name = shift.name.trim().toLowerCase();
        if (this.shifts.some((s) => s.id !== shift.id && s.name.toLowerCase() === name)) {
          return 'duplicate';
        }
        this.shifts = [...this.shifts.filter((s) => s.id !== shift.id), shift];
        return null;
      }
      case 'shift.assign': {
        const a = toAssignment(p);
        if (!this.shifts.some((s) => s.id === a.shiftId)) return 'not_found';
        if (overlappingAssignment(a, this.assignments)) return 'assignment_overlap';
        this.assignments = [...this.assignments.filter((x) => x.id !== a.id), a];
        return null;
      }
      case 'shift.unassign':
        this.assignments = this.assignments.filter((x) => x.id !== p['id']);
        return null;
      case 'staff_holiday.upsert': {
        const day = String(p['day']);
        const old = this.holidays.find((h) => h.day === day);
        this.holidays = [
          ...this.holidays.filter((h) => h.day !== day),
          {
            id: old?.id ?? `hn${this.nextId++}`,
            day,
            name: String(p['name']),
            paid: p['paid'] !== false,
          },
        ];
        return null;
      }
      case 'staff_holiday.delete':
        this.holidays = this.holidays.filter((h) => h.day !== p['day']);
        return null;
      default:
        return 'invalid_payload';
    }
  }
}
