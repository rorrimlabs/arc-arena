import { AppError } from '../auth/auth-api';
import { ArenaApi, Membership } from './arena-api';

const ALL = ['start', 'bill', 'discount', 'members', 'stations', 'money', 'reports', 'settings'];

/** Deterministic in-memory ArenaApi for tests: the design's two arenas, owned by the caller. */
export class SampleArenaApi extends ArenaApi {
  memberships: Membership[];

  constructor(owned = true) {
    super();
    this.memberships = owned
      ? [
          {
            arenaId: 'a1',
            arenaName: '404 Arena Koramangala',
            name: 'Arjun Mehra',
            role: 'owner',
            perms: ALL,
            active: true,
          },
          {
            arenaId: 'a2',
            arenaName: '404 Arena Indiranagar',
            name: 'Arjun Mehra',
            role: 'owner',
            perms: ALL,
            active: true,
          },
        ]
      : [];
  }

  async myArenas(): Promise<Membership[]> {
    return [...this.memberships];
  }

  async createArena(arenaName: string, ownerName: string): Promise<string> {
    if (this.memberships.some((m) => m.role === 'owner')) {
      throw new AppError('arena_limit', 'This login already owns an arena');
    }
    const id = `a${this.memberships.length + 1}`;
    this.memberships.push({
      arenaId: id,
      arenaName,
      name: ownerName,
      role: 'owner',
      perms: ALL,
      active: true,
    });
    return id;
  }
}
