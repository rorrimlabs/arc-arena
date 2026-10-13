import { AppError } from '../../../core/auth/auth-api';
import { UsersApi } from './users-api';
import { ArenaUser, NewUser, UserChange } from './user.models';

const ALL_PERMS = [
  'start',
  'bill',
  'discount',
  'members',
  'stations',
  'money',
  'reports',
  'settings',
];

function user(
  userId: string,
  name: string,
  role: ArenaUser['role'],
  perms: readonly string[],
  stats: [number, number, number] = [0, 0, 0],
): ArenaUser {
  const email = name.split(' ')[0].toLowerCase() + '@404arena.in';
  return {
    userId,
    name,
    email,
    role,
    perms,
    active: true,
    invited: false,
    bills30d: stats[0],
    takings30dPaise: stats[1],
    refunds30dPaise: stats[2],
  };
}

/** The design's sample people (`mkArena(0)`), with fixed 30-day figures. */
export function sampleUsers(): ArenaUser[] {
  return [
    user('u0', 'Arjun Mehra', 'owner', ALL_PERMS),
    user(
      'u1',
      'Priya Nair',
      'staff',
      ['start', 'bill', 'discount', 'members'],
      [312, 4_812_000, 24_000],
    ),
    user('u2', 'Rohan Das', 'staff', ['start', 'bill'], [287, 4_390_000, 0]),
    user('u3', 'Kavya Iyer', 'staff', ['start', 'bill', 'discount'], [265, 3_975_000, 12_000]),
  ];
}

/** Deterministic in-memory UsersApi for tests and offline previews. */
export class SampleUsersApi extends UsersApi {
  users: ArenaUser[] = sampleUsers();
  private next = 100;

  async list(): Promise<ArenaUser[]> {
    return this.users.map((u) => ({ ...u }));
  }

  async create(_arenaId: string, u: NewUser): Promise<{ userId: string; created: boolean }> {
    if (this.users.some((x) => x.email === u.email)) {
      throw new AppError('email_exists', 'Someone already uses that email');
    }
    const userId = `u${this.next++}`;
    this.users = [
      ...this.users,
      {
        userId,
        name: u.name,
        email: u.email,
        role: u.role,
        perms: u.role === 'owner' ? ALL_PERMS : [...u.perms],
        active: true,
        invited: true,
        bills30d: 0,
        takings30dPaise: 0,
        refunds30dPaise: 0,
      },
    ];
    return { userId, created: true };
  }

  async update(_arenaId: string, userId: string, change: UserChange): Promise<void> {
    if (!this.users.some((u) => u.userId === userId)) {
      throw new AppError('not_found', 'That person is no longer on the list. Refresh');
    }
    this.users = this.users.map((u) =>
      u.userId === userId
        ? { ...u, name: change.name, perms: [...change.perms], active: change.active }
        : u,
    );
  }
}
