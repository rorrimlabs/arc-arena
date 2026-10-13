import { TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { ArenaContext } from '../app/core/arena/arena-context';
import { AuthApi } from '../app/core/auth/auth-api';
import { RealtimeSync } from '../app/core/sync/realtime-sync';
import { IT_RUN, handoff, itEnv, need, until, useNodeEventsForWebSockets } from './it-env';

/** What the spec reads off the dashboard's RealtimeSync (its private routing hooks). */
interface Observable {
  activeChannel: { state: string } | null;
  schedule(targets: readonly string[]): void;
  onBroadcast(arenaId: string, raw: unknown): void;
}

/**
 * Floor → dashboard, LIVE (tool/sync_it.sh step 3): the owner's dashboard joins the private arena
 * channel with its real RealtimeSync and must hear the floor's committed changes — Postgres
 * Changes routed to the sales/floor stores and the staff app's post-commit broadcast — while the
 * Flutter suites run. Writes $AO_IT_HANDOFF/admin_listening once joined.
 */
describe.skipIf(!IT_RUN || itEnv['AO_IT_LISTEN'] !== '1')('integration · dashboard live', () => {
  it('hears the floor’s committed changes over the private channel', async () => {
    const arenaId = need('AO_IT_ARENA');
    await useNodeEventsForWebSockets();
    const auth = TestBed.inject(AuthApi);
    await auth.signIn(need('AO_IT_OWNER_EMAIL'), need('AO_IT_PASSWORD'));
    const arena = TestBed.inject(ArenaContext);
    await arena.load(true);
    arena.select(arenaId);
    const realtime = TestBed.inject(RealtimeSync);
    TestBed.tick(); // let the shell's effect settle on this arena before joining
    await new Promise((r) => setTimeout(r, 300));
    await realtime.setupArena(arenaId, true);
    const live = realtime as unknown as Observable;
    await until(() => live.activeChannel?.state === 'joined', 'the private channel joined', 30_000);
    await new Promise((r) => setTimeout(r, 1_000)); // the join's own catch-up refresh

    const scheduled = vi.spyOn(live, 'schedule');
    const broadcasts: Record<string, unknown>[] = [];
    const onBroadcast = live.onBroadcast.bind(live);
    vi.spyOn(live, 'onBroadcast').mockImplementation((id, raw) => {
      broadcasts.push((raw ?? {}) as Record<string, unknown>);
      onBroadcast(id, raw);
    });
    handoff.write('admin_listening', { joined: true });

    const heardBroadcast = () =>
      broadcasts.some((b) => b['source'] === 'mobile' && b['arena_id'] === arenaId);
    const heardChange = () =>
      scheduled.mock.calls.some(([t]) => t.includes('sales') || t.includes('floor_plays'));
    try {
      await until(() => heardBroadcast() && heardChange(), 'floor events', 420_000);
    } catch {
      throw new Error(
        `floor → dashboard: mobile broadcast heard: ${heardBroadcast()}, ` +
          `floor table change heard: ${heardChange()} (${broadcasts.length} broadcasts, ` +
          `${scheduled.mock.calls.length} routed changes)`,
      );
    }
    const nudge = broadcasts.find((b) => b['source'] === 'mobile')!;
    expect(Object.keys(nudge).sort()).toEqual(['arena_id', 'at', 'kind', 'kinds', 'source']);
    expect(Array.isArray(nudge['kinds'])).toBe(true);
    await auth.signOut();
  }, 480_000);
});
