import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { AppError, toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { writeThenReload } from '../../../core/sync/push-ops';
import { ACCESSORY_MESSAGES, AccessoriesApi } from './accessories-api';
import {
  Accessory,
  AccessoryChange,
  AccessoryKind,
  AccessoryMove,
  AccessoryStatus,
  applyChange,
} from './accessory.models';

/**
 * The current arena's station accessories and their kinds. Every change goes to the server
 * first, then the list reloads to show what it holds (floor devices move and lend pads all day,
 * so an edit is built on a fresh read, never on what the screen loaded earlier).
 */
@Service()
export class AccessoriesStore {
  private readonly api = inject(AccessoriesApi);
  private readonly arena = inject(ArenaContext);

  readonly accessories = signal<readonly Accessory[]>([]);
  readonly kinds = signal<readonly AccessoryKind[]>([]);
  readonly byId = computed(() => new Map(this.accessories().map((c) => [c.id, c])));
  readonly kindById = computed(() => new Map(this.kinds().map((k) => [k.id, k])));
  /** The lists hold the current arena's rows (false until the first read lands). */
  readonly ready = signal(false);
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;
  private outOfDate = false;
  /** Each load's number; only the newest one's answer lands (a switch of arena mid-load). */
  private latest = 0;

  constructor() {
    // Sign-out or another login: the lists leave memory; a read in flight does not land.
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.accessories.set([]);
      this.kinds.set([]);
      this.ready.set(false);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  /** Loaded at least once for the current arena (a live update then reloads it). */
  get loaded(): boolean {
    return !!this.loadedArena && this.loadedArena === this.arena.current().id;
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && !this.outOfDate && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) {
      this.accessories.set([]);
      this.kinds.set([]);
      this.ready.set(false);
    }
    this.outOfDate = false;
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const [list, kinds] = await Promise.all([
        this.api.accessories(arenaId),
        this.api.kinds(arenaId),
      ]);
      if (call !== this.latest) return;
      this.accessories.set(list);
      this.kinds.set(kinds);
      this.ready.set(true);
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

  /** Reads again if a screen has loaded the lists (live updates). */
  async refresh(): Promise<void> {
    if (this.loaded) await this.load(true);
  }

  /** A new accessory standing at (and belonging to) `stationId`; resolves with its id. */
  async add(label: string, kindId: string | null, stationId: string): Promise<string> {
    const arenaId = this.arena.current().id;
    const id = crypto.randomUUID();
    await writeThenReload(
      () =>
        this.api.save(arenaId, {
          id,
          label,
          kindId,
          homeId: stationId,
          currentId: stationId,
          status: 'usable',
          notes: null,
          loanReturnTo: null,
          loanSessionRef: null,
        }),
      () => this.load(true),
    );
    return id;
  }

  /**
   * Renames, re-kinds or re-homes an accessory (controller.upsert sends the whole row): the row is
   * read fresh just before, so where it is, its loan and anything not changed here stay as the
   * server has them.
   */
  async edit(id: string, change: AccessoryChange): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      async () => {
        const fresh = await this.api.accessory(arenaId, id);
        if (!fresh) throw new AppError('not_found', ACCESSORY_MESSAGES['not_found']);
        await this.api.save(arenaId, applyChange(fresh, change));
      },
      () => this.load(true),
    );
  }

  /** controller.set_status: status and note, nothing else. */
  async setStatus(id: string, status: AccessoryStatus, notes: string | null): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.setStatus(arenaId, id, status, notes),
      () => this.load(true),
    );
  }

  /** Brings a lent accessory back home, or makes `toId` its new home (moving it there). */
  async move(id: string, kind: 'returnHome' | 'permanent', toId?: string): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.move(arenaId, id, kind, toId),
      () => this.load(true),
    );
  }

  /** The newest moves of one accessory (read on demand, not kept). */
  moves(id: string, limit = 20): Promise<AccessoryMove[]> {
    return this.api.moves(this.arena.current().id, id, limit);
  }

  async saveKind(kind: AccessoryKind): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.saveKind(arenaId, kind),
      () => this.load(true),
    );
  }

  async removeKind(id: string): Promise<'deleted' | 'retired'> {
    let outcome: 'deleted' | 'retired' = 'deleted';
    await writeThenReload(
      async () => {
        outcome = await this.api.removeKind(this.arena.current().id, id);
      },
      () => this.load(true),
    );
    return outcome;
  }
}
