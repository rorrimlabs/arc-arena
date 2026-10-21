import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { ArenaApi, accessOf } from '../app/core/arena/arena-api';
import { AuthApi } from '../app/core/auth/auth-api';
import { InviteeAuth } from '../app/core/auth/invitee-auth';
import { FloorApi } from '../app/core/floor/floor-api';
import {
  DEFAULT_FLOOR_OPTIONS,
  FloorOptionsApi,
} from '../app/features/settings/data/floor-options';
import { INVITE_LINK_BASE, UsersApi } from '../app/features/users/data/users-api';
import { DASHBOARD_ORIGIN, IT_RUN, handoff, latestAuthLink, need } from './it-env';

/**
 * Dashboard phase 1 (tool/sync_it.sh): the owner configures the arena on the dashboard's real
 * data layer — a new game playable on exactly one station, the floor options — and invites a new
 * person by e-mail (invite_member, then Supabase Auth's e-mail); that person accepts from the
 * e-mailed link (local Mailpit) the way the /accept-invite page does. The Flutter phases then
 * check the staff device sees the configuration (dashboard.json).
 */
describe.skipIf(!IT_RUN)('integration · dashboard phase 1 (owner on the local backend)', () => {
  it('builds a playable game, saves floor options, and an e-mailed invitation is accepted', async () => {
    TestBed.configureTestingModule({
      providers: [{ provide: INVITE_LINK_BASE, useValue: DASHBOARD_ORIGIN }],
    });
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
        playModes: ['local'],
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

    // The game lifecycle: one game archived (hidden from new sessions, kept), one deleted (never
    // used, so it goes with its station status). The floor phase checks what its device sees.
    const extra = (id: string, title: string) => ({
      id,
      name: title,
      aliases: [],
      categoryId: null,
      platforms: ['PS5'],
      playModes: ['single' as const],
      maxLocalPlayers: 1,
      active: true,
      ageRating: null,
      media: null,
    });
    const archivedId = crypto.randomUUID();
    const deletedId = crypto.randomUUID();
    await floor.saveGame(arenaId, extra(archivedId, `IT Archived ${run}`), [playable.id]);
    await floor.saveGame(arenaId, extra(deletedId, `IT Deleted ${run}`), [playable.id]);
    await expect(
      floor.saveGame(arenaId, extra(crypto.randomUUID(), `it archived ${run}`.toUpperCase())),
    ).rejects.toMatchObject({ code: 'duplicate' });
    await floor.setGameActive(arenaId, archivedId, false);
    expect(await floor.gameUsage(arenaId, deletedId)).toEqual({ playingNow: 0, records: 0 });
    await floor.deleteGame(arenaId, deletedId);
    const after = await floor.games(arenaId);
    expect(after.find((g) => g.id === archivedId)?.active).toBe(false);
    expect(after.some((g) => g.id === deletedId)).toBe(false);
    expect((await floor.gameResources(arenaId)).some((c) => c.gameId === deletedId)).toBe(false);
    // A retried delete of a gone game is a no-op; an edit queued before it cannot bring it back.
    await floor.deleteGame(arenaId, deletedId);
    await expect(
      floor.saveGame(arenaId, extra(deletedId, `IT Deleted ${run}`)),
    ).rejects.toMatchObject({ code: 'not_found' });

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
    // A new address: Auth's sign-up confirmation, so the page asks for a password first.
    expect(fragment.get('type')).toBe('signup');

    // What the page does for a new login, in the browser where the owner is still signed in:
    // the invitee's session from the link lives on the page's own client (InviteeAuth), a
    // password they choose, accept. The dashboard's stored sign-in stays the owner's throughout.
    const page = TestBed.inject(InviteeAuth);
    page.begin();
    const account = await page.fromLink(
      fragment.get('access_token')!,
      fragment.get('refresh_token')!,
    );
    expect(account.email).toBe(invitee);
    expect((await auth.current())?.email).toBe(owner);
    await page.setPassword(password);
    await expect(page.accept(inviteId, token)).resolves.toEqual({
      arenaId,
      arenaName: `IT ${run}`,
      role: 'staff',
    });
    // A retried accept (double click, a second tab) never makes a second membership.
    await expect(page.accept(inviteId, token)).rejects.toMatchObject({ code: 'invite_used' });
    // Floor staff: not owner level there, so the page sends them to the staff app.
    await expect(page.canManage(arenaId)).resolves.toBe(false);
    await page.end();
    expect((await auth.current())?.email).toBe(owner);

    // The owner — never signed out — sees them on the list, no longer pending, and is still the
    // owner of the arena (what the dashboard's guard reads: no detour to Create Arena).
    const ownerView = await TestBed.inject(ArenaApi).myArenas();
    expect(accessOf(ownerView)).toBe('owner');
    const joined = (await users.list(arenaId)).find((u) => u.email === invitee);
    expect(joined).toMatchObject({ role: 'staff', active: true, perms: ['start'] });
    expect((await users.listInvites(arenaId)).map((i) => i.email)).not.toContain(invitee);
    await auth.signOut();

    handoff.write('dashboard.json', {
      arena_id: arenaId,
      game_id: gameId,
      game_name: name,
      archived_game_id: archivedId,
      deleted_game_id: deletedId,
      playable_station_id: playable.id,
      other_station_id: other.id,
      activity_code: 'PS5',
      warn_minutes: warnMinutes,
    });
  }, 180_000);
});
