import { Service, Signal, computed, inject, signal } from '@angular/core';
import { istDayStart } from '../../shared/time/ist';
import { ArenaContext } from '../arena/arena-context';
import { toAppError } from '../auth/auth-api';
import { LoginScope } from '../auth/login-scope';
import { writeThenReload } from '../sync/push-ops';
import { Clock } from '../time/clock';
import { FloorApi } from './floor-api';
import {
  Charge,
  CompatStatus,
  Customer,
  Game,
  GameCompat,
  GameInput,
  GameUsage,
  Play,
  Station,
  StationInput,
  StationStatus,
  Visit,
} from './floor.models';

/** History windows the screens read, in IST days (today included). */
export const PLAY_DAYS = 90;
export const CHARGE_DAYS = 30;

/** One server read, cached per key (arena + window start); a newer call wins. */
class Cached<T> {
  readonly value;
  readonly loading = signal(false);
  readonly error = signal('');
  /** The value is the current arena's (false until its first read lands). */
  readonly ready = signal(false);
  private readonly empty: T;
  private key: string | null = null;
  private latest = 0;

  /** Read at least once (and the last read did not fail). */
  get loaded(): boolean {
    return this.key !== null;
  }

  constructor(empty: T) {
    this.empty = empty;
    this.value = signal<T>(empty);
  }

  async load(key: string, force: boolean, read: () => Promise<T>): Promise<void> {
    if (!force && key === this.key) return;
    const call = ++this.latest;
    if (this.key?.split('|')[0] !== key.split('|')[0]) {
      this.value.set(this.empty);
      this.ready.set(false);
    }
    this.key = key;
    this.loading.set(true);
    this.error.set('');
    try {
      const value = await read();
      if (call === this.latest) {
        this.value.set(value);
        this.ready.set(true);
      }
    } catch (e) {
      if (call === this.latest) {
        this.error.set(toAppError(e).message);
        this.key = null;
      }
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Forgets the value (another login): a read still in flight does not land. */
  clear(): void {
    this.latest++;
    this.key = null;
    this.value.set(this.empty);
    this.ready.set(false);
    this.loading.set(false);
    this.error.set('');
  }
}

/**
 * The current arena's stations, games, members and recent play, shared by the dashboard's
 * screens (each loads what it shows; a second screen reuses the first one's read). Changes go
 * to the server first, then the affected list reloads to show what the server holds.
 */
@Service()
export class FloorStore {
  private readonly api = inject(FloorApi);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);

  private readonly stationsC = new Cached<Station[]>([]);
  private readonly gamesC = new Cached<Game[]>([]);
  private readonly gameResourcesC = new Cached<GameCompat[]>([]);
  private readonly customersC = new Cached<Customer[]>([]);
  private readonly playsC = new Cached<Play[]>([]);
  private readonly visitsC = new Cached<Visit[]>([]);
  private readonly chargesC = new Cached<Charge[]>([]);

  readonly stations: Signal<readonly Station[]> = this.stationsC.value;
  readonly stationsReady: Signal<boolean> = this.stationsC.ready;
  readonly games: Signal<readonly Game[]> = this.gamesC.value;
  /** Where each game can be played (a pair without a row is not installed). */
  readonly gameResources: Signal<readonly GameCompat[]> = this.gameResourcesC.value;
  /** gameResources holds the current arena's rows (warnings wait for it). */
  readonly gameResourcesReady: Signal<boolean> = this.gameResourcesC.ready;
  readonly customers: Signal<readonly Customer[]> = this.customersC.value;
  /** Plays of the last PLAY_DAYS days plus every open one. */
  readonly plays: Signal<readonly Play[]> = this.playsC.value;
  /** Bills of the last PLAY_DAYS days plus every running one. */
  readonly visits: Signal<readonly Visit[]> = this.visitsC.value;
  /** Billed lines of the last CHARGE_DAYS days. */
  readonly charges: Signal<readonly Charge[]> = this.chargesC.value;

  readonly gameById = computed(() => new Map(this.games().map((g) => [g.id, g])));
  readonly customerById = computed(() => new Map(this.customers().map((c) => [c.id, c])));
  readonly stationById = computed(() => new Map(this.stations().map((s) => [s.id, s])));
  /** game id → station id → status. */
  readonly compatByGame = computed(() => {
    const out = new Map<string, Map<string, CompatStatus>>();
    for (const c of this.gameResources()) {
      const byStation = out.get(c.gameId) ?? new Map<string, CompatStatus>();
      byStation.set(c.resourceId, c.status);
      out.set(c.gameId, byStation);
    }
    return out;
  });

  private readonly all = [
    this.stationsC,
    this.gamesC,
    this.gameResourcesC,
    this.customersC,
    this.playsC,
    this.visitsC,
    this.chargesC,
  ];
  readonly loading = computed(() => this.all.some((c) => c.loading()));
  /** The first read that failed, worded for the screen. */
  readonly loadError = computed(() => this.all.map((c) => c.error()).find(Boolean) ?? '');

  constructor() {
    // Sign-out or another login: nothing of this login's arena stays in memory.
    inject(LoginScope).onEnd(() => this.all.forEach((c) => c.clear()));
  }

  /**
   * The first of `what` that failed, worded for the screen (reactive). A screen asks only about
   * the reads it shows, so another screen's failed read never hides it, and its "Try again"
   * (load(what, true)) clears exactly what it reports.
   */
  errorOf(what: readonly FloorRead[]): string {
    return what.map((w) => this.cache(w).error()).find(Boolean) ?? '';
  }

  /** Loads the named reads for the current arena (each once, unless forced). */
  async load(what: readonly FloorRead[], force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    const now = this.clock.now();
    const since = (days: number) => istDayStart(now, days - 1);
    const tomorrow = istDayStart(now, -1);
    const key = (from?: Date) => `${arenaId}|${from?.toISOString() ?? ''}`;
    const jobs = what.map((w) => {
      switch (w) {
        case 'stations':
          return this.stationsC.load(key(), force, () => this.api.stations(arenaId));
        case 'games':
          return this.gamesC.load(key(), force, () => this.api.games(arenaId));
        case 'gameResources':
          return this.gameResourcesC.load(key(), force, () => this.api.gameResources(arenaId));
        case 'customers':
          return this.customersC.load(key(), force, () => this.api.customers(arenaId));
        case 'plays': {
          const from = since(PLAY_DAYS);
          return this.playsC.load(key(from), force, () => this.api.plays(arenaId, from));
        }
        case 'visits': {
          const from = since(PLAY_DAYS);
          return this.visitsC.load(key(from), force, () => this.api.visits(arenaId, from));
        }
        case 'charges': {
          const from = since(CHARGE_DAYS);
          return this.chargesC.load(key(from), force, () =>
            this.api.charges(arenaId, from, tomorrow),
          );
        }
      }
    });
    await Promise.all(jobs);
  }

  /** Reads again those of `what` a screen has already loaded (live updates). */
  async refresh(what: readonly FloorRead[]): Promise<void> {
    const loaded = what.filter((w) => this.cache(w).loaded);
    if (loaded.length) await this.load(loaded, true);
  }

  private cache(what: FloorRead): Cached<unknown> {
    const caches: Record<FloorRead, Cached<unknown>> = {
      stations: this.stationsC,
      games: this.gamesC,
      gameResources: this.gameResourcesC,
      customers: this.customersC,
      plays: this.playsC,
      visits: this.visitsC,
      charges: this.chargesC,
    };
    return caches[what];
  }

  async saveStation(station: StationInput): Promise<void> {
    await this.api.saveStation(this.arena.current().id, station);
    await this.load(['stations'], true);
  }

  async setStationStatus(id: string, status: StationStatus): Promise<void> {
    await this.api.setStationStatus(this.arena.current().id, id, status);
    await this.load(['stations'], true);
  }

  /**
   * Saves the game (and marks it playable on `playableOn`), then reloads both lists. An edit
   * passes `baseActive` (the active flag it showed); a stale one is refused and the list reloads
   * to show what the server holds.
   */
  async saveGame(
    game: GameInput,
    playableOn: readonly string[] = [],
    baseActive?: boolean,
  ): Promise<void> {
    const arenaId = this.arena.current().id;
    const reload = () =>
      this.load(playableOn.length ? ['games', 'gameResources'] : ['games'], true);
    try {
      await writeThenReload(() => this.api.saveGame(arenaId, game, playableOn, baseActive), reload);
    } catch (e) {
      if (toAppError(e).code === 'stale') await reload();
      throw e;
    }
  }

  /** Archives (false) or restores (true) a game, then reloads the list. */
  async setGameActive(id: string, active: boolean): Promise<void> {
    await this.api.setGameActive(this.arena.current().id, id, active);
    await this.load(['games'], true);
  }

  /** What still refers to a game (whether it can be deleted or must be archived). */
  gameUsage(id: string): Promise<GameUsage> {
    return this.api.gameUsage(this.arena.current().id, id);
  }

  /**
   * Deletes a game nothing ever used, then reloads the games and their station statuses. A
   * refusal (in play, history) also reloads, so the screen shows what the server holds.
   */
  async deleteGame(id: string): Promise<void> {
    const reload = () => this.load(['games', 'gameResources'], true);
    try {
      await this.api.deleteGame(this.arena.current().id, id);
    } catch (e) {
      await reload();
      throw e;
    }
    await reload();
  }

  async setGameCompat(gameId: string, resourceId: string, status: CompatStatus): Promise<void> {
    await this.api.setGameCompat(this.arena.current().id, gameId, resourceId, status);
    await this.load(['gameResources'], true);
  }
}

export type FloorRead =
  'stations' | 'games' | 'gameResources' | 'customers' | 'plays' | 'visits' | 'charges';
