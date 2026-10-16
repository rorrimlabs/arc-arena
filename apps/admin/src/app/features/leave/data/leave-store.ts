import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { Session } from '../../../core/auth/session';
import { LeaveApi } from './leave-api';
import {
  LeaveBalance,
  LeaveData,
  LeaveRecord,
  LeaveRequest,
  adjustPayload,
  decidePayload,
  isOpen,
  recordPayload,
} from './leave.models';

/**
 * The current arena's leave: requests, balance adjustments and everyone's balance. A decision or
 * an adjustment goes to the server first, then everything is read again (the server recounts
 * the balances). A broadcast of an applied `leave.*` op reloads it (RealtimeSync).
 */
@Service()
export class LeaveStore {
  private readonly api = inject(LeaveApi);
  private readonly arena = inject(ArenaContext);
  private readonly session = inject(Session);

  readonly data = signal<LeaveData | null>(null);
  readonly balances = signal<readonly LeaveBalance[]>([]);
  readonly loading = signal(false);
  readonly loadError = signal('');

  readonly staff = computed(() => this.data()?.staff ?? []);
  readonly requests = computed(() => this.data()?.requests ?? []);
  readonly adjustments = computed(() => this.data()?.adjustments ?? []);
  readonly byId = computed(() => new Map(this.requests().map((r) => [r.id, r])));
  readonly balanceOf = computed(() => new Map(this.balances().map((b) => [b.staffId, b])));
  readonly nameOfStaff = computed(() => new Map(this.staff().map((s) => [s.id, s.name])));
  readonly nameOfUser = computed(() => new Map(this.staff().map((s) => [s.userId, s.name])));
  /** Requests waiting for a decision (new ones and cancellations). */
  readonly openCount = computed(() => this.requests().filter(isOpen).length);
  /** The signed-in login's own staff profile here (for the own-record rule). */
  readonly myStaffId = computed(() => {
    const me = this.session.user()?.id;
    return this.staff().find((s) => s.userId === me)?.id ?? null;
  });

  private loadedArena: string | null = null;
  private outOfDate = false;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.data.set(null);
      this.balances.set([]);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && !this.outOfDate && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) {
      this.data.set(null);
      this.balances.set([]);
    }
    this.outOfDate = false;
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const [data, balances] = await Promise.all([
        this.api.load(arenaId),
        this.api.balances(arenaId, null),
      ]);
      if (call !== this.latest) return;
      this.data.set(data);
      this.balances.set(balances);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  stale(): void {
    this.outOfDate = true;
  }

  async refresh(): Promise<void> {
    if (this.loadedArena || this.loadError()) await this.load(true);
  }

  /** A user's name in this arena ("Arjun Mehra"), or "someone" when no longer a member. */
  userName(userId: string | null): string {
    return (userId && this.nameOfUser().get(userId)) || 'someone';
  }

  /** The own-record rule: only the owner role decides its own requests. */
  canDecide(r: LeaveRequest): boolean {
    return r.staffId !== this.myStaffId() || this.arena.currentRole() === 'owner';
  }

  async decide(
    r: LeaveRequest,
    approve: boolean,
    paidDays: number | null,
    note: string,
  ): Promise<void> {
    await this.api.send(this.arena.current().id, {
      kind: 'leave.decide',
      payload: decidePayload(r, approve, paidDays, note),
    });
    await this.load(true);
  }

  /** leave.record: leave a manager enters directly (approved, all paid or all LOP). */
  async record(r: LeaveRecord): Promise<void> {
    await this.api.send(this.arena.current().id, { kind: 'leave.record', payload: recordPayload(r) });
    await this.load(true);
  }

  async adjust(staffId: string, days: number, reason: string): Promise<void> {
    await this.api.send(this.arena.current().id, {
      kind: 'leave.adjust',
      payload: adjustPayload(staffId, days, reason),
    });
    await this.load(true);
  }
}
