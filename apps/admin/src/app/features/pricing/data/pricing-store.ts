import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { partlyApplied, writeThenReload } from '../../../core/sync/push-ops';
import { BillingPolicy } from './billing-policy';
import { PricingApi } from './pricing-api';
import {
  BusinessHours,
  DEFAULT_DISCOUNT_OPTIONS,
  Discount,
  DiscountOptions,
  DiscountUsage,
  Holiday,
  PricingData,
  PricingRule,
  RateChange,
  TypeInput,
} from './pricing.models';

/**
 * The current arena's price list. Every change goes to the server first; the screen then
 * reloads what the server holds (the price list is shared with every floor device). A save of
 * several ops that is refused part-way reloads too, so applied prices show as saved and the rest
 * do not.
 */
@Service()
export class PricingStore {
  private readonly api = inject(PricingApi);
  private readonly arena = inject(ArenaContext);

  readonly data = signal<PricingData | null>(null);
  readonly types = computed(() => this.data()?.types ?? []);
  readonly rates = computed(() => this.data()?.rates ?? []);
  readonly hours = computed(() => this.data()?.hours ?? null);
  readonly holidays = computed(() => this.data()?.holidays ?? []);
  readonly policy = computed(() => this.data()?.policy ?? null);
  readonly rules = computed(() => this.data()?.rules ?? []);
  readonly discounts = computed(() => this.data()?.discounts ?? []);
  readonly discountOptions = computed(() => this.data()?.discountOptions ?? DEFAULT_DISCOUNT_OPTIONS);
  readonly byId = computed(() => new Map(this.types().map((t) => [t.id, t])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;
  private outOfDate = false;
  /** Each load's number; only the newest one's answer lands (a switch of arena mid-load). */
  private latest = 0;

  constructor() {
    // Sign-out or another login: the price list leaves memory; a read in flight does not land.
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

  /**
   * Marks the data out of date without reading it (a live update while no screen shows it): the
   * next screen that loads it reads it again, instead of a download nobody looks at.
   */
  stale(): void {
    this.outOfDate = true;
  }

  /** Reads again if a screen has loaded the price list (live updates). */
  async refresh(): Promise<void> {
    if (this.loadedArena) await this.load(true);
  }

  async saveType(type: TypeInput): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveType(arenaId, type),
      () => this.load(true),
    );
  }

  async removeType(id: string): Promise<'deleted' | 'retired'> {
    let outcome: 'deleted' | 'retired';
    try {
      outcome = await this.api.removeType(this.arena.current().id, id);
    } catch (e) {
      if (partlyApplied(e)) await this.load(true);
      throw e;
    }
    await this.load(true);
    return outcome;
  }

  async saveRates(changes: readonly RateChange[]): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveRates(arenaId, changes),
      () => this.load(true),
    );
  }

  async saveHours(hours: BusinessHours): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveHours(arenaId, hours),
      () => this.load(true),
    );
  }

  /** Holidays are part of the price list: the whole list reloads after a change. */
  async saveHoliday(holiday: Holiday, replacing?: string): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveHoliday(arenaId, holiday, replacing),
      () => this.load(true),
    );
  }

  async deleteHoliday(day: string): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.deleteHoliday(arenaId, day),
      () => this.load(true),
    );
  }

  /** Rules are part of the price list: the whole list reloads after a change. */
  async saveRule(rule: PricingRule): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveRule(arenaId, rule),
      () => this.load(true),
    );
  }

  async deleteRule(id: string): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.deleteRule(arenaId, id),
      () => this.load(true),
    );
  }

  /** Every rule id, first-tried first. A refusal (stale) reloads so the screen shows the truth. */
  async reorderRules(ids: readonly string[]): Promise<void> {
    const arenaId = this.arena.current().id;
    try {
      await this.api.reorderRules(arenaId, ids);
    } finally {
      await this.load(true);
    }
  }

  async saveDiscount(discount: Discount): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveDiscount(arenaId, discount),
      () => this.load(true),
    );
  }

  async setDiscountActive(id: string, active: boolean): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.setDiscountActive(arenaId, id, active),
      () => this.load(true),
    );
  }

  async deleteDiscount(id: string): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.deleteDiscount(arenaId, id),
      () => this.load(true),
    );
  }

  async saveDiscountOptions(options: DiscountOptions): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveDiscountOptions(arenaId, options),
      () => this.load(true),
    );
  }

  /** One page of the bills a preset or coupon was used on (read when it is opened). */
  discountUsage(id: string, limit = 20, cursor: string | null = null): Promise<DiscountUsage> {
    return this.api.discountUsage(this.arena.current().id, id, limit, cursor);
  }

  async savePolicy(policy: BillingPolicy): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.savePolicy(arenaId, policy),
      () => this.load(true),
    );
  }
}
