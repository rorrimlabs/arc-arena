import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { BillEdit, MethodCorrection, PaymentEntry, RefundEntry, SalesApi } from './sales-api';
import { Bill, SalesPeriod, periodBounds } from './sale.models';

/**
 * The current arena's closed bills for one period (IST days). Every write goes to the server
 * first; the list and any open bill then reload to show what the server recorded.
 */
@Service()
export class SalesStore {
  private readonly api = inject(SalesApi);
  private readonly arena = inject(ArenaContext);

  readonly bills = signal<readonly Bill[]>([]);
  readonly byId = computed(() => new Map(this.bills().map((b) => [b.id, b])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  /** When the list last came from the server (null before the first load). */
  readonly loadedAt = signal<Date | null>(null);
  /** Bumped after a change so an open bill's detail reloads. */
  readonly revision = signal(0);
  /** Arena + period: another day (or arena, or period) loads again. */
  private loadedKey: string | null = null;
  private outOfDate = false;
  private current: SalesPeriod | null = null;
  private latest = 0;

  constructor() {
    // Sign-out or another login: the bills leave memory; a read in flight does not land.
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedKey = null;
      this.current = null;
      this.bills.set([]);
      this.loading.set(false);
      this.loadError.set('');
      this.loadedAt.set(null);
    });
  }

  async load(period: SalesPeriod, force = false): Promise<void> {
    this.current = period;
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    const { from, to } = periodBounds(period);
    const key = `${arenaId}|${period.first}|${period.last}`;
    if (!force && !this.outOfDate && key === this.loadedKey) return;
    const call = ++this.latest;
    if (this.loadedKey !== key) this.bills.set([]);
    this.outOfDate = false;
    this.loadedKey = key;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const bills = await this.api.list(arenaId, from, to);
      if (call === this.latest) {
        this.bills.set(bills);
        this.loadedAt.set(new Date());
      }
    } catch (e) {
      if (call === this.latest) {
        this.loadError.set(toAppError(e).message);
        this.loadedKey = null;
      }
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  get(id: string) {
    return this.api.get(this.arena.current().id, id);
  }

  void(bill: Bill, reason: string): Promise<void> {
    return this.write(() => this.api.void(this.arena.current().id, bill, reason));
  }

  recordPayment(bill: Bill, entry: PaymentEntry): Promise<void> {
    return this.write(() => this.api.recordPayment(this.arena.current().id, bill, entry));
  }

  refund(bill: Bill, entry: RefundEntry): Promise<void> {
    return this.write(() => this.api.refund(this.arena.current().id, bill, entry));
  }

  correct(bill: Bill, correction: MethodCorrection): Promise<void> {
    return this.write(() => this.api.correct(this.arena.current().id, bill, correction));
  }

  edit(bill: Bill, change: BillEdit): Promise<void> {
    return this.write(() => this.api.edit(this.arena.current().id, bill, change));
  }

  /**
   * A live update (another device voided or took payment on a bill), the Refresh button or a
   * reconnect: reloads the list and bumps `revision`, so an open bill's detail reads it again
   * instead of showing the old state.
   */
  /**
   * Marks the data out of date without reading it (a live update while no screen shows it): the
   * next screen that loads it reads it again, instead of a download nobody looks at.
   */
  stale(): void {
    if (!this.loadedKey) return;
    this.outOfDate = true;
    this.revision.update((n) => n + 1);
  }

  async refresh(): Promise<void> {
    if (this.current && (this.loadedKey || this.loadError())) {
      this.revision.update((n) => n + 1);
      await this.load(this.current, true);
    }
  }

  private async write(change: () => Promise<void>): Promise<void> {
    await change();
    this.revision.update((n) => n + 1);
    if (this.current) await this.load(this.current, true);
  }
}
