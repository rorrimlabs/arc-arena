import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { PricingApi } from './pricing-api';
import { BusinessHours, PricingData, RateChange, TypeInput } from './pricing.models';

/**
 * The current arena's price list. Every change goes to the server first; the screen then
 * reloads what the server holds (the price list is shared with every floor device).
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
    await this.api.saveType(this.arena.current().id, type);
    await this.load(true);
  }

  async removeType(id: string): Promise<'deleted' | 'retired'> {
    const outcome = await this.api.removeType(this.arena.current().id, id);
    await this.load(true);
    return outcome;
  }

  async saveRates(changes: readonly RateChange[]): Promise<void> {
    await this.api.saveRates(this.arena.current().id, changes);
    await this.load(true);
  }

  async saveHours(hours: BusinessHours): Promise<void> {
    await this.api.saveHours(this.arena.current().id, hours);
    await this.load(true);
  }
}
