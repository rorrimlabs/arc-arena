import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { SyncOp, writeThenReload } from '../../../core/sync/push-ops';
import { ShiftsApi } from './shifts-api';
import {
  ArenaHoliday,
  Shift,
  ShiftAssignment,
  ShiftsData,
  StaffHoliday,
  assignPayload,
  shiftPayload,
} from './shifts.models';

/**
 * The current arena's shifts, assignments and staff holidays. Every write goes to the server
 * first (sync_push), then the lists are read again. A broadcast of an applied `shift.*` or
 * `staff_holiday.*` op reloads them (RealtimeSync).
 */
@Service()
export class ShiftsStore {
  private readonly api = inject(ShiftsApi);
  private readonly arena = inject(ArenaContext);

  readonly data = signal<ShiftsData | null>(null);
  readonly shifts = computed(() =>
    [...(this.data()?.shifts ?? [])].sort(
      (a, b) => Number(b.active) - Number(a.active) || a.startMin - b.startMin ||
        a.name.localeCompare(b.name),
    ),
  );
  readonly assignments = computed(() => this.data()?.assignments ?? []);
  readonly holidays = computed(() =>
    [...(this.data()?.holidays ?? [])].sort((a, b) => a.day.localeCompare(b.day)),
  );
  readonly staff = computed(() => this.data()?.staff ?? []);
  readonly staffNames = computed(() => new Map(this.staff().map((s) => [s.id, s.name])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;
  private outOfDate = false;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.data.set(null);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && !this.outOfDate && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.data.set(null);
    this.outOfDate = false;
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const data = await this.api.load(arenaId);
      if (call !== this.latest) return;
      this.data.set(data);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Marks the lists out of date without reading them (a live update nobody is looking at). */
  stale(): void {
    this.outOfDate = true;
  }

  /** Reads again if a screen has loaded the lists (live updates). */
  async refresh(): Promise<void> {
    if (this.loadedArena) await this.load(true);
  }

  /** shift.upsert (add or edit). */
  saveShift(shift: Shift): Promise<void> {
    return this.push([{ kind: 'shift.upsert', payload: shiftPayload(shift) }]);
  }

  /** shift.assign (add, or change the dates of the same id). */
  assign(a: ShiftAssignment): Promise<void> {
    return this.push([{ kind: 'shift.assign', payload: assignPayload(a) }]);
  }

  unassign(id: string): Promise<void> {
    return this.push([{ kind: 'shift.unassign', payload: { id } }]);
  }

  /**
   * staff_holiday.upsert, keyed by day; a holiday moved to another day also clears the old day
   * (staff_holiday.delete), in the same call.
   */
  saveHoliday(h: Pick<StaffHoliday, 'day' | 'name' | 'paid'>, replacing?: string): Promise<void> {
    const ops: SyncOp[] = [
      { kind: 'staff_holiday.upsert', payload: { day: h.day, name: h.name.trim(), paid: h.paid } },
    ];
    if (replacing && replacing !== h.day) {
      ops.push({ kind: 'staff_holiday.delete', payload: { day: replacing } });
    }
    return this.push(ops);
  }

  deleteHoliday(day: string): Promise<void> {
    return this.push([{ kind: 'staff_holiday.delete', payload: { day } }]);
  }

  /** The price list's holidays in a window (for "Copy from arena holidays"). */
  arenaHolidays(first: string, last: string): Promise<ArenaHoliday[]> {
    return this.api.arenaHolidays(this.arena.current().id, first, last);
  }

  /** Adds each arena holiday as a paid staff holiday: one upsert op per day, one push. */
  copyHolidays(days: readonly ArenaHoliday[]): Promise<void> {
    return this.push(
      days.map((h) => ({
        kind: 'staff_holiday.upsert',
        payload: { day: h.day, name: h.name.trim() || 'Holiday', paid: true },
      })),
    );
  }

  private push(ops: SyncOp[]): Promise<void> {
    const arenaId = this.arena.current().id;
    return writeThenReload(
      () => this.api.push(arenaId, ops),
      () => this.load(true),
    );
  }
}
