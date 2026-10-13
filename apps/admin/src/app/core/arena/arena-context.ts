import { Service, computed, effect, inject, signal } from '@angular/core';
import { CanMatchFn, Router } from '@angular/router';
import { Session } from '../auth/session';
import { ArenaApi, Membership, isOwnerLevel } from './arena-api';

export interface Arena {
  readonly id: string;
  readonly name: string;
}

const LAST_ARENA_KEY = 'arenaos.arena';

/**
 * The arenas the signed-in owner manages (owner-level memberships) and the one being viewed;
 * every screen's data is scoped to `current()`. Loaded once per signed-in login.
 */
@Service()
export class ArenaContext {
  private readonly api = inject(ArenaApi);
  private readonly session = inject(Session);

  readonly memberships = signal<readonly Membership[]>([]);
  readonly arenas = computed<readonly Arena[]>(() =>
    this.memberships()
      .filter(isOwnerLevel)
      .map((m) => ({ id: m.arenaId, name: m.arenaName })),
  );
  /** The login owns an arena (create_my_arena allows one per login). */
  readonly ownsArena = computed(() => this.memberships().some((m) => m.role === 'owner'));

  private readonly currentId = signal<string | null>(readLastArena());
  private loadedFor: string | null = null;

  readonly current = computed<Arena>(
    () =>
      this.arenas().find((arena) => arena.id === this.currentId()) ??
      this.arenas()[0] ?? { id: '', name: '' },
  );

  /** The signed-in login's own profile in the current arena. */
  readonly currentMembership = computed(() =>
    this.memberships().find((m) => m.arenaId === this.current().id),
  );
  /** The signed-in login's role in the current arena (only an owner can add owners). */
  readonly currentRole = computed(() => this.currentMembership()?.role ?? null);

  constructor() {
    // A different login (or sign-out) must not see the previous login's arenas.
    effect(() => {
      if (this.session.user()?.id !== this.loadedFor) {
        this.loadedFor = null;
        this.memberships.set([]);
      }
    });
  }

  /** Loads the signed-in login's memberships (once per login unless forced). */
  async load(force = false): Promise<void> {
    // canMatch guards run together: never decide before the stored session is read.
    await this.session.ready;
    const userId = this.session.user()?.id ?? null;
    if (!userId) return;
    if (!force && this.loadedFor === userId) return;
    this.memberships.set(await this.api.myArenas());
    this.loadedFor = userId;
  }

  select(id: string): void {
    this.currentId.set(id);
    try {
      localStorage.setItem(LAST_ARENA_KEY, id);
    } catch {
      // Storage blocked: the choice lasts for this visit only.
    }
  }
}

function readLastArena(): string | null {
  try {
    return localStorage.getItem(LAST_ARENA_KEY);
  } catch {
    return null;
  }
}

/**
 * The dashboard needs an arena to manage; a login without one goes to create it. If the list
 * cannot be loaded, the create-arena screen shows why and retries.
 */
export const arenaGuard: CanMatchFn = async () => {
  const context = inject(ArenaContext);
  const router = inject(Router);
  try {
    await context.load();
  } catch {
    return router.createUrlTree(['/create-arena']);
  }
  return context.arenas().length > 0 || router.createUrlTree(['/create-arena']);
};
