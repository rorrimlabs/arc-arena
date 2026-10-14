import { Service, computed, inject, signal } from '@angular/core';
import { CanMatchFn, Router } from '@angular/router';
import { LoginScope } from '../auth/login-scope';
import { Session } from '../auth/session';
import { ArenaApi, DashboardAccess, Membership, accessOf, isOwnerLevel } from './arena-api';

export interface Arena {
  readonly id: string;
  readonly name: string;
}

const LAST_ARENA_KEY = 'arenaos.arena';

/**
 * The arenas the signed-in owner manages (owner-level memberships) and the one being viewed;
 * every screen's data is scoped to `current()`. Loaded once per signed-in login, again on live
 * staff changes (RealtimeSync), and cleared when the login changes.
 */
@Service()
export class ArenaContext {
  private readonly api = inject(ArenaApi);
  private readonly session = inject(Session);

  /** Reloaded on live staff changes: an unchanged list keeps its identity (nothing re-renders). */
  readonly memberships = signal<readonly Membership[]>([], {
    equal: (a, b) => JSON.stringify(a) === JSON.stringify(b),
  });
  readonly arenas = computed<readonly Arena[]>(() =>
    this.memberships()
      .filter(isOwnerLevel)
      .map((m) => ({ id: m.arenaId, name: m.arenaName })),
  );
  /** The login owns an arena (create_my_arena allows one per login). */
  readonly ownsArena = computed(() => this.memberships().some((m) => m.role === 'owner'));
  /**
   * What the dashboard is for this login (owner / staff / off / none — see accessOf), from its
   * server-side memberships. Meaningful once `loaded()`; the guards route on it.
   */
  readonly access = computed<DashboardAccess>(() => accessOf(this.memberships()));

  private readonly currentId = signal<string | null>(readLastArena());
  /** The login whose memberships are held; null until read (and again after a login change). */
  private readonly loadedFor = signal<string | null>(null);
  /** Bumped by every login change: a read for the previous login does not land. */
  private generation = 0;
  /** The read in flight (the guards of one navigation share it instead of each asking). */
  private reading: Promise<void> | null = null;
  /** The signed-in login's memberships have been read. */
  readonly loaded = computed(() => {
    const id = this.loadedFor();
    return id !== null && id === this.session.user()?.id;
  });

  /** Stays the same object while the arena and its name do (screens keyed on it keep state). */
  readonly current = computed<Arena>(
    () =>
      this.arenas().find((arena) => arena.id === this.currentId()) ??
      this.arenas()[0] ?? { id: '', name: '' },
    { equal: (a, b) => a.id === b.id && a.name === b.name },
  );

  /** The signed-in login's own profile in the current arena. */
  readonly currentMembership = computed(() =>
    this.memberships().find((m) => m.arenaId === this.current().id),
  );
  /** The signed-in login's role in the current arena (only an owner can add owners). */
  readonly currentRole = computed(() => this.currentMembership()?.role ?? null);
  /**
   * May change the arena here: the catalog, prices, stations, staff and settings. The server
   * requires the settings permission (or the owner role) for every one of those writes; an
   * owner-level member without it (money or reports only) sees the dashboard read-only.
   */
  readonly canEdit = computed(() => {
    const m = this.currentMembership();
    return !!m && m.active && (m.role === 'owner' || m.perms.includes('settings'));
  });

  constructor() {
    // A different login (or sign-out) must not see the previous login's arenas.
    inject(LoginScope).onEnd(() => {
      this.generation++;
      this.reading = null;
      this.loadedFor.set(null);
      this.memberships.set([]);
    });
  }

  /**
   * Loads the signed-in login's memberships (once per login unless forced). Forced again by live
   * staff changes, so access turned off or narrowed elsewhere applies without a page reload.
   */
  async load(force = false): Promise<void> {
    // canMatch guards run together: never decide before the stored session is read.
    await this.session.ready;
    const userId = this.session.user()?.id ?? null;
    if (!userId) return;
    if (!force && this.loadedFor() === userId) return;
    // Concurrent callers (guards, the shell, live updates) share one read; a forced one waits for
    // it and then reads again, so it always sees a change made after it was asked for.
    if (this.reading) {
      const pending = this.reading;
      await pending.catch(() => undefined);
      if (!force && this.loadedFor() === userId) return;
      if (this.reading && this.reading !== pending) return this.reading;
    }
    const generation = this.generation;
    const read = (async () => {
      const memberships = await this.api.myArenas();
      if (generation !== this.generation) return;
      this.memberships.set(memberships);
      this.loadedFor.set(userId);
    })();
    this.reading = read;
    try {
      await read;
    } finally {
      if (this.reading === read) this.reading = null;
    }
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

/** Where each access state belongs (accessOf); the dashboard itself is ''. */
export const ACCESS_HOME: Readonly<Record<DashboardAccess, string>> = {
  owner: '/',
  none: '/create-arena',
  staff: '/account',
  off: '/account',
};

/**
 * The dashboard (every owner screen, by direct URL too) is for owner-level logins only. A new
 * owner with no arena goes to create one; floor staff and logins whose access is off go to the
 * account page, which says so — never to Create Arena. When the memberships cannot be read the
 * account page shows why and retries: a failed read is never taken for "no arena".
 */
export const arenaGuard: CanMatchFn = async () => {
  const context = inject(ArenaContext);
  const router = inject(Router);
  try {
    await context.load();
  } catch {
    return router.createUrlTree(['/account']);
  }
  const access = context.access();
  return access === 'owner' || router.createUrlTree([ACCESS_HOME[access]]);
};

/** Create Arena is only for a login with no membership at all (a new owner). */
export const noArenaGuard: CanMatchFn = async () => {
  const context = inject(ArenaContext);
  const router = inject(Router);
  try {
    await context.load();
  } catch {
    return router.createUrlTree(['/account']);
  }
  const access = context.access();
  return access === 'none' || router.createUrlTree([ACCESS_HOME[access]]);
};
