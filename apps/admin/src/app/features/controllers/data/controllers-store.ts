import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { AppError, toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { writeThenReload } from '../../../core/sync/push-ops';
import { CONTROLLER_MESSAGES, ControllersApi } from './controllers-api';
import { Controller, ControllerChange, ControllerStatus, applyChange } from './controller.models';

/**
 * The current arena's pads. Every change goes to the server first, then the list reloads to
 * show what it holds (floor devices move and lend pads all day, so an edit is built on a fresh
 * read of the pad, never on what the screen loaded earlier).
 */
@Service()
export class ControllersStore {
  private readonly api = inject(ControllersApi);
  private readonly arena = inject(ArenaContext);

  readonly controllers = signal<readonly Controller[]>([]);
  readonly byId = computed(() => new Map(this.controllers().map((c) => [c.id, c])));
  /** The list holds the current arena's pads (false until its first read lands). */
  readonly ready = signal(false);
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;
  /** Each load's number; only the newest one's answer lands (a switch of arena mid-load). */
  private latest = 0;

  constructor() {
    // Sign-out or another login: the list leaves memory; a read in flight does not land.
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.controllers.set([]);
      this.ready.set(false);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) {
      this.controllers.set([]);
      this.ready.set(false);
    }
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const list = await this.api.controllers(arenaId);
      if (call !== this.latest) return;
      this.controllers.set(list);
      this.ready.set(true);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Reads again if a screen has loaded the list (live updates). */
  async refresh(): Promise<void> {
    if (this.loadedArena && this.loadedArena === this.arena.current().id) await this.load(true);
  }

  /** A new pad standing at (and belonging to) `stationId`; resolves with its id. */
  async add(label: string, stationId: string): Promise<string> {
    const arenaId = this.arena.current().id;
    const id = crypto.randomUUID();
    await writeThenReload(
      () =>
        this.api.save(arenaId, {
          id,
          label,
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
   * Renames or re-homes a pad (controller.upsert sends the whole row): the row is read fresh just
   * before, so where the pad is, its loan and anything not changed here stay as the server has
   * them.
   */
  async edit(id: string, change: ControllerChange): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      async () => {
        const fresh = await this.api.controller(arenaId, id);
        if (!fresh) throw new AppError('not_found', CONTROLLER_MESSAGES['not_found']);
        await this.api.save(arenaId, applyChange(fresh, change));
      },
      () => this.load(true),
    );
  }

  /** controller.set_status: status and note, nothing else. */
  async setStatus(id: string, status: ControllerStatus, notes: string | null): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.setStatus(arenaId, id, status, notes),
      () => this.load(true),
    );
  }
}
