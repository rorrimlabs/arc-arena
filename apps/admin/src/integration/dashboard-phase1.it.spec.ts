import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { ArenaApi } from '../app/core/arena/arena-api';
import { AuthApi } from '../app/core/auth/auth-api';
import { FloorApi } from '../app/core/floor/floor-api';
import { DEFAULT_FLOOR_OPTIONS, FloorOptionsApi } from '../app/features/settings/data/floor-options';
import { UsersApi } from '../app/features/users/data/users-api';
import { IT_RUN, handoff, latestAuthLink, need } from './it-env';

/**
 * Dashboard phase 1 (tool/sync_it.sh): the owner configures the arena on the dashboard's real
 * data layer — a new game playable on exactly one station, the floor options — and invites a new
 * person by e-mail through the staff-admin Edge Function; that person accepts from the e-mailed
 * link (local Mailpit) the way the /accept-invite page does. The Flutter phases then check the
 * staff device sees the configuration (dashboard.json).
 */
describe.skipIf(!IT_RUN)('integration · dashboard phase 1 (owner on the local backend)', () => {
  it('builds a playable game, saves floor options, and an e-mailed invitation is accepted', async () => {
    const run = need('AO_IT_RUN');
    const arenaId = need('AO_IT_ARENA');
    const password = need('AO_IT_PASSWORD');
    const owner = need('AO_IT_OWNER_EMAIL');
    const invitee = need('AO_IT_INVITEE_EMAIL');
    const auth = TestBed.inject(AuthApi);
    const floor = TestBed.inject(FloorApi);
    const users = TestBed.inject(UsersApi);
    const options = TestBed.inject(FloorOptionsApi);

    await auth.signIn(owner, password);
    const mine = await TestBed.inject(ArenaApi).myArenas();
    expect(mine.find((m) => m.arenaId === arenaId)?.role).toBe('owner');

    // A game on one station only — the dashboard's new availability control.
    const ps5 = (await floor.stations(arenaId)).filter((s) => s.activityCodes.includes('PS5'));
    expect(ps5.length).toBeGreaterThanOrEqual(2);
    const [playable, other] = ps5;
    const gameId = crypto.randomUUID();
    const name = `IT Game ${run}`;
    await floor.saveGame(
      arenaId,
      {
        id: gameId,
        name,
        aliases: [],
        categoryId: null,
        platforms: ['PS5'],
        playerMode: 'local',
        maxLocalPlayers: 2,
        active: true,
        ageRating: null,
        media: null,
      },
      [playable.id],
    );
    expect((await floor.games(arenaId)).find((g) => g.id === gameId)?.name).toBe(name);
    const compat = (await floor.gameResources(arenaId)).filter((c) => c.gameId === gameId);
    expect(compat).toEqual([{ gameId, resourceId: playable.id, status: 'playable' }]);

    // Floor options the staff app reads.
    const before = (await options.load(arenaId)) ?? DEFAULT_FLOOR_OPTIONS;
    const warnMinutes = before.warnMinutes === 7 ? 8 : 7;
    await options.save(arenaId, { ...before, warnMinutes });
    expect((await options.load(arenaId))?.warnMinutes).toBe(warnMinutes);

    // Invite a new person by e-mail; nobody joins until they accept.
    const sent = await users.invite(arenaId, {
      role: 'staff',
      name: 'IT Invitee',
      email: invitee,
      perms: ['start'],
    });
    expect(sent.inviteId).toMatch(/^[0-9a-f-]{36}$/);
    expect((await users.listInvites(arenaId)).map((i) => i.email)).toContain(invitee);
    expect((await users.list(arenaId)).map((u) => u.email)).not.toContain(invitee);

    // In their inbox: Supabase Auth's link, which lands on /accept-invite with the one-time
    // token in the query and their new session in the fragment.
    const link = await latestAuthLink(invitee);
    const landed = await fetch(link, { redirect: 'manual' });
    const landing = new URL(landed.headers.get('location') ?? '');
    expect(`${landing.origin}${landing.pathname}`).toBe('http://127.0.0.1:4200/accept-invite');
    const inviteId = landing.searchParams.get('invite')!;
    const token = landing.searchParams.get('token')!;
    expect(inviteId).toBe(sent.inviteId);
    expect(token).toMatch(/^[0-9a-f]{64}$/);
    const fragment = new URLSearchParams(landing.hash.slice(1));
    expect(fragment.get('type')).toBe('invite');

    // What the page does for a new login: session from the link, a password they choose, accept.
    const account = await auth.signInFromLink(
      fragment.get('access_token')!,
      fragment.get('refresh_token')!,
    );
    expect(account.email).toBe(invitee);
    await auth.setPassword(password);
    await expect(auth.acceptInvite(inviteId, token)).resolves.toEqual({
      arenaId,
      arenaName: `IT ${run}`,
      role: 'staff',
    });
    await expect(auth.acceptInvite(inviteId, token)).rejects.toMatchObject({ code: 'invite_used' });
    await auth.signOut();

    // Back as the owner: they are on the list now, and no longer pending.
    await auth.signIn(owner, password);
    const joined = (await users.list(arenaId)).find((u) => u.email === invitee);
    expect(joined).toMatchObject({ role: 'staff', active: true, perms: ['start'] });
    expect((await users.listInvites(arenaId)).map((i) => i.email)).not.toContain(invitee);
    await auth.signOut();

    handoff.write('dashboard.json', {
      arena_id: arenaId,
      game_id: gameId,
      game_name: name,
      playable_station_id: playable.id,
      other_station_id: other.id,
      activity_code: 'PS5',
      warn_minutes: warnMinutes,
    });
  }, 180_000);
});
