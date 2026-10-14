import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { partlyApplied, writeThenReload } from '../../../core/sync/push-ops';
import { BillingPolicy } from './billing-policy';
import { PricingApi } from './pricing-api';
import { BusinessHours, Holiday, PricingData, RateChange, TypeInput } from './pricing.models';

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
  readonly byId = computed(() => new Map(this.types().map((t) => [t.id, t])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;
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
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.data.set(null);
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

  async savePolicy(policy: BillingPolicy): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.savePolicy(arenaId, policy),
      () => this.load(true),
    );
  }
}
