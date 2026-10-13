import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Clock } from '../../../core/time/clock';
import { SalesApi } from './sales-api';
import { Bill, SalesRange, rangeBounds } from './sale.models';

/**
 * The current arena's closed bills for one date range. A void goes to the server first; the list
 * and any open bill then reload to show what the server recorded.
 */
@Service()
export class SalesStore {
  private readonly api = inject(SalesApi);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);

  readonly bills = signal<readonly Bill[]>([]);
  readonly byId = computed(() => new Map(this.bills().map((b) => [b.id, b])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  /** Bumped after a change so an open bill's detail reloads. */
  readonly revision = signal(0);
  /** Arena + range + its start: a new day (or arena, or range) loads again. */
  private loadedKey: string | null = null;
  private latest = 0;

  async load(range: SalesRange, force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    const { from, to } = rangeBounds(range, this.clock.now());
    const key = `${arenaId}|${range}|${from.toISOString()}`;
    if (!force && key === this.loadedKey) return;
    const call = ++this.latest;
    if (!this.loadedKey?.startsWith(`${arenaId}|${range}|`)) this.bills.set([]);
    this.loadedKey = key;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const bills = await this.api.list(arenaId, from, to);
      if (call === this.latest) this.bills.set(bills);
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

  async void(bill: Bill, reason: string, range: SalesRange): Promise<void> {
    await this.api.void(this.arena.current().id, bill, reason);
    this.revision.update((n) => n + 1);
    await this.load(range, true);
  }
}
