import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { partlyApplied, writeThenReload } from '../../../core/sync/push-ops';
import { PricingApi } from './pricing-api';
import { BusinessHours, PricingData, RateChange, TypeInput } from './pricing.models';

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
  readonly byId = computed(() => new Map(this.types().map((t) => [t.id, t])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.data.set(null);
    this.loading.set(true);
    this.loadError.set('');
    try {
      this.data.set(await this.api.load(arenaId));
      this.loadedArena = arenaId;
    } catch (e) {
      this.loadError.set(toAppError(e).message);
    } finally {
      this.loading.set(false);
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
}
