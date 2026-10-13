import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { FloorApi } from '../../../core/floor/floor-api';
import { Charge } from '../../../core/floor/floor.models';
import { Clock } from '../../../core/time/clock';
import { SalesApi } from '../../sales/data/sales-api';
import { Bill } from '../../sales/data/sale.models';
import { Period, PeriodRange, chunks, periodRange } from './overview.models';

/**
 * The Overview's figures for one period: closed bills of the period and the one before it
 * (arena_sales, fetched in spans the API accepts) and the period's billed lines by type.
 */
@Service()
export class OverviewStore {
  private readonly sales = inject(SalesApi);
  private readonly floor = inject(FloorApi);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);

  readonly range = signal<PeriodRange | null>(null);
  /** Bills of the period, newest first. */
  readonly bills = signal<readonly Bill[]>([]);
  /** Bills of the period before, for the comparisons. */
  readonly previous = signal<readonly Bill[]>([]);
  readonly charges = signal<readonly Charge[]>([]);
  readonly loading = signal(false);
  readonly loadError = signal('');
  readonly empty = computed(() => !this.bills().length);
  private loadedKey: string | null = null;
  private currentPeriod: Period = 'today';
  private latest = 0;

  async load(period: Period, force = false): Promise<void> {
    this.currentPeriod = period;
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    const range = periodRange(period, this.clock.now());
    const key = `${arenaId}|${period}|${range.from.toISOString()}`;
    if (!force && key === this.loadedKey) return;
    const call = ++this.latest;
    if (!this.loadedKey?.startsWith(`${arenaId}|${period}|`)) {
      this.bills.set([]);
      this.previous.set([]);
      this.charges.set([]);
    }
    this.loadedKey = key;
    this.range.set(range);
    this.loading.set(true);
    this.loadError.set('');
    try {
      const span = (from: Date, to: Date) =>
        Promise.all(chunks(from, to).map((c) => this.sales.list(arenaId, c.from, c.to))).then(
          (parts) => parts.flat().sort((a, b) => Date.parse(b.at) - Date.parse(a.at)),
        );
      const [bills, previous, charges] = await Promise.all([
        span(range.from, range.to),
        span(range.prevFrom, range.prevTo),
        this.floor.charges(arenaId, range.from, range.to),
      ]);
      if (call !== this.latest) return;
      this.bills.set(bills);
      this.previous.set(previous);
      this.charges.set(charges);
    } catch (e) {
      if (call === this.latest) {
        this.loadError.set(toAppError(e).message);
        this.loadedKey = null;
      }
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  async refresh(): Promise<void> {
    if (this.loadedKey) {
      await this.load(this.currentPeriod, true);
    }
  }
}
