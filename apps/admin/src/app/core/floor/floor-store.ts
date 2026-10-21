import { Service, Signal, computed, inject, signal } from '@angular/core';
import { istDayStart } from '../../shared/time/ist';
import { ArenaContext } from '../arena/arena-context';
import { toAppError } from '../auth/auth-api';
import { LoginScope } from '../auth/login-scope';
import { writeThenReload } from '../sync/push-ops';
import { Clock } from '../time/clock';
import { FloorApi } from './floor-api';
import {
  Activity,
  CompatStatus,
  Game,
  GameCompat,
  GameFan,
  GameFigures,
  GameInput,
  GameUsage,
  MemberPage,
  Play,
  Station,
  StationFigures,
  StationInput,
  StationStatus,
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
  private outOfDate = false;

  /** Read at least once (and the last read did not fail). */
  get loaded(): boolean {
    return this.key !== null;
  }

  constructor(empty: T) {
    this.empty = empty;
    this.value = signal<T>(empty);
  }

  async load(key: string, force: boolean, read: () => Promise<T>): Promise<void> {
    if (!force && !this.outOfDate && key === this.key) return;
    this.outOfDate = false;
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

  /** Keeps the value but reads it again on the next load (a live update nobody is looking at). */
  stale(): void {
    if (this.key !== null) this.outOfDate = true;
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
  private readonly liveC = new Cached<Play[]>([]);
  private readonly stationFiguresC = new Cached<ReadonlyMap<string, StationFigures>>(new Map());
  private readonly gameFiguresC = new Cached<ReadonlyMap<string, GameFigures>>(new Map());

  readonly stations: Signal<readonly Station[]> = this.stationsC.value;
  readonly stationsReady: Signal<boolean> = this.stationsC.ready;
  readonly games: Signal<readonly Game[]> = this.gamesC.value;
  /** Where each game can be played (a pair without a row is not installed). */
  readonly gameResources: Signal<readonly GameCompat[]> = this.gameResourcesC.value;
  /** gameResources holds the current arena's rows (warnings wait for it). */
  readonly gameResourcesReady: Signal<boolean> = this.gameResourcesC.ready;
  /** Play open right now (what the floor shows as playing): a small read, unlike `plays`. */
  readonly live: Signal<readonly Play[]> = this.liveC.value;
  /** Station id → figures for today and the last CHARGE_DAYS days, aggregated on the server. */
  readonly stationFigures: Signal<ReadonlyMap<string, StationFigures>> = this.stationFiguresC.value;
  /** Game id → figures for the last CHARGE_DAYS days, aggregated on the server. */
  readonly gameFigures: Signal<ReadonlyMap<string, GameFigures>> = this.gameFiguresC.value;

  readonly gameById = computed(() => new Map(this.games().map((g) => [g.id, g])));
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
    this.liveC,
    this.stationFiguresC,
    this.gameFiguresC,
  ];
  readonly loading = computed(() => this.all.some((c) => c.loading()));
  /**
   * Bumped by every live refresh of play or members: reads made on demand (a station's or
   * member's recent bills, the members list) depend on it to read again.
   */
  readonly revision = signal(0);
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
        case 'live':
          // Open play only: nothing started after now, so `since = now` keeps just the open rows.
          return this.liveC.load(key(), force, () => this.api.plays(arenaId, now));
        case 'stationFigures': {
          const from = since(CHARGE_DAYS);
          return this.stationFiguresC.load(key(from), force, () =>
            this.api.stationFigures(arenaId, since(1), from, tomorrow),
          );
        }
        case 'gameFigures': {
          const from = since(CHARGE_DAYS);
          return this.gameFiguresC.load(key(from), force, () => this.api.gameFigures(arenaId, from));
        }
      }
    });
    await Promise.all(jobs);
  }

  /** Reads again those of `what` a screen has already loaded (live updates). */
  async refresh(what: readonly FloorRead[]): Promise<void> {
    if (what.includes('live')) {
      this.revision.update((n) => n + 1);
    }
    const loaded = what.filter((w) => this.cache(w).loaded);
    if (loaded.length) await this.load(loaded, true);
  }

  /** Marks `what` out of date: the next screen that loads it reads it again. */
  stale(what: readonly FloorRead[]): void {
    for (const w of what) this.cache(w).stale();
  }

  private cache(what: FloorRead): Cached<unknown> {
    const caches: Record<FloorRead, Cached<unknown>> = {
      stations: this.stationsC,
      games: this.gamesC,
      gameResources: this.gameResourcesC,
      live: this.liveC,
      stationFigures: this.stationFiguresC,
      gameFigures: this.gameFiguresC,
    };
    return caches[what];
  }

  /**
   * A station's or member's newest bills over the PLAY_DAYS window, and a member's minutes per
   * game: read when one is opened, never kept (each opening reads it fresh).
   */
  activity(of: { stationId?: string; customerId?: string }, limit = 6): Promise<Activity> {
    const now = this.clock.now();
    return this.api.activity(this.arena.current().id, of, istDayStart(now, PLAY_DAYS - 1), limit);
  }

  /** The members who played a game most over the last CHARGE_DAYS days (read when it is opened). */
  gameFans(gameId: string, limit = 4): Promise<GameFan[]> {
    const now = this.clock.now();
    return this.api.gameFans(
      this.arena.current().id,
      gameId,
      istDayStart(now, CHARGE_DAYS - 1),
      limit,
    );
  }

  /** One page of members (visits over PLAY_DAYS, spend over CHARGE_DAYS), searched on the server. */
  members(search: string, limit: number, offset: number): Promise<MemberPage> {
    const now = this.clock.now();
    return this.api.members(this.arena.current().id, {
      since: istDayStart(now, PLAY_DAYS - 1),
      since30: istDayStart(now, CHARGE_DAYS - 1),
      search,
      limit,
      offset,
    });
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
  | 'stations'
  | 'games'
  | 'gameResources'
  | 'live'
  | 'stationFigures'
  | 'gameFigures';
