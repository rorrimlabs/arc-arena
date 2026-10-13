import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { UsersApi } from './users-api';
import { ArenaUser, NewUser, UserChange } from './user.models';

/**
 * The current arena's users. Every change goes to the server first; the list then shows what
 * the server accepted (a refusal leaves it unchanged and is reported to the caller).
 */
@Service()
export class UsersStore {
  private readonly api = inject(UsersApi);
  private readonly arena = inject(ArenaContext);

  readonly users = signal<readonly ArenaUser[]>([]);
  readonly owners = computed(() => this.users().filter((u) => u.role === 'owner'));
  readonly staff = computed(() => this.users().filter((u) => u.role === 'staff'));
  readonly byId = computed(() => new Map(this.users().map((u) => [u.userId, u])));
  readonly loading = signal(false);
  readonly loadError = signal('');
  /** userId of a user with a change in flight (their controls are disabled). */
  readonly saving = signal<string | null>(null);
  private loadedArena: string | null = null;

  /** Loads the current arena's users (again when the arena changed, or when forced). */
  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.users.set([]);
    this.loading.set(true);
    this.loadError.set('');
    try {
      this.users.set(await this.api.list(arenaId));
      this.loadedArena = arenaId;
    } catch (e) {
      this.loadError.set(toAppError(e).message);
    } finally {
      this.loading.set(false);
    }
  }

  async add(user: NewUser): Promise<{ userId: string; created: boolean }> {
    const result = await this.api.create(this.arena.current().id, user);
    await this.load(true);
    return result;
  }

  async change(user: ArenaUser, change: Partial<UserChange>): Promise<void> {
    const next: UserChange = {
      name: change.name ?? user.name,
      perms: change.perms ?? user.perms,
      active: change.active ?? user.active,
    };
    this.saving.set(user.userId);
    try {
      await this.api.update(this.arena.current().id, user.userId, next);
      this.users.update((list) =>
        list.map((u) => (u.userId === user.userId ? { ...u, ...next } : u)),
      );
    } finally {
      this.saving.set(null);
    }
  }
}
