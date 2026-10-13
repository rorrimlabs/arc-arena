import { Service, effect, inject } from '@angular/core';
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { ArenaContext } from '../arena/arena-context';
import { Session } from '../auth/session';
import { FloorStore } from '../floor/floor-store';
import { FloorOptionsStore } from '../../features/settings/data/floor-options';
import { OverviewStore } from '../../features/overview/data/overview-store';
import { PricingStore } from '../../features/pricing/data/pricing-store';
import { SalesStore } from '../../features/sales/data/sales-store';
import { UsersStore } from '../../features/users/data/users-store';
import { Supabase } from '../supabase/supabase';
import { SYNC_EVENT, arenaTopic } from './push-ops';

export type RefreshTarget =
  | 'floor_plays'
  | 'floor_charges'
  | 'stations'
  | 'games'
  | 'game_resources'
  | 'customers'
  | 'sales'
  | 'overview'
  | 'pricing'
  | 'settings'
  | 'users'
  | 'arena';

const BILLS: readonly RefreshTarget[] = ['floor_plays', 'overview', 'sales'];
const PRICES: readonly RefreshTarget[] = ['pricing', 'settings'];

/**
 * The published tables the dashboard shows, and what each one's changes refresh. Bookings and
 * controllers are published for the floor app but not shown here, so they are not subscribed.
 */
export const TABLE_TARGETS: Readonly<Record<string, readonly RefreshTarget[]>> = {
  sessions: BILLS,
  session_segments: ['floor_plays', 'overview'],
  session_charges: ['sales', 'overview', 'floor_charges'],
  session_extensions: ['sales', 'overview', 'floor_plays'],
  payments: ['sales', 'overview', 'floor_plays'],
  group_sessions: BILLS,
  group_assignments: BILLS,
  group_charges: [...BILLS, 'floor_charges'],
  group_payments: BILLS,
  group_extensions: BILLS,
  resources: ['stations'],
  resource_activities: ['stations', 'pricing'],
  activities: ['pricing', 'stations'],
  games: ['games'],
  game_controls: ['games'],
  game_categories: ['games'],
  game_resources: ['game_resources'],
  customers: ['customers'],
  staff_profiles: ['users'],
  // Business and happy hours live in settings rows: a settings change refreshes pricing too.
  settings: PRICES,
  rates: PRICES,
  rate_cards: PRICES,
  rate_bands: PRICES,
  holidays: PRICES,
  billing_policies: PRICES,
};

const ALL_TARGETS: readonly RefreshTarget[] = [
  'floor_plays',
  'floor_charges',
  'stations',
  'games',
  'game_resources',
  'customers',
  'sales',
  'overview',
  'pricing',
  'settings',
  'users',
];

/** What a committed op kind (`session.start`, `game.set_compat`…) refreshes, by its prefix. */
const KIND_TARGETS: readonly (readonly [string, readonly RefreshTarget[]])[] = [
  ['session.', BILLS],
  ['group.', BILLS],
  ['payment.', ['sales', 'overview', 'floor_plays']],
  ['game.set_compat', ['game_resources']],
  ['game.', ['games']],
  ['resource.', ['stations', 'game_resources']],
  ['activity.', ['pricing', 'stations']],
  ['rate.', PRICES],
  ['policy.', PRICES],
  ['holiday.', PRICES],
  ['settings.', PRICES],
  ['hours.', PRICES],
  ['customer.', ['customers']],
  ['staff.', ['users']],
  ['arena.', ['arena', 'settings']],
  // Floor-only records the dashboard does not show.
  ['booking.', []],
  ['controller.', []],
];

export function targetsForKind(kind: string): readonly RefreshTarget[] {
  return KIND_TARGETS.find(([prefix]) => kind.startsWith(prefix))?.[1] ?? ALL_TARGETS;
}

/**
 * Live updates for the dashboard over the current arena's PRIVATE Realtime channel
 * (`arena:<id>`; Realtime Authorization admits only active members, so the user's JWT is set
 * before joining):
 * 1. Postgres Changes: INSERT and UPDATE of the published tables, filtered by arena_id (RLS also
 *    applies). DELETE is never subscribed — Supabase neither filters nor RLS-checks delete
 *    events, so they would leak other arenas' row ids; deletions arrive as a broadcast nudge.
 * 2. Broadcast `sync`: sent by a device after its push committed, listing the applied op kinds.
 *
 * Bursts are coalesced; each refresh re-reads through the stores' normal RLS-checked queries.
 * The channel follows the signed-in user and the selected arena, and is torn down on sign-out.
 */
@Service()
export class RealtimeSync {
  private readonly supabase = inject(Supabase);
  private readonly session = inject(Session);
  private readonly arena = inject(ArenaContext);
  private readonly floor = inject(FloorStore);
  private readonly sales = inject(SalesStore);
  private readonly overview = inject(OverviewStore);
  private readonly pricing = inject(PricingStore);
  private readonly floorOptions = inject(FloorOptionsStore);
  private readonly users = inject(UsersStore);

  private activeChannel: RealtimeChannel | null = null;
  private subscribedArenaId: string | null = null;
  /** Bumped by every setup and teardown: callbacks of an older channel do nothing. */
  private generation = 0;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly pendingTargets = new Set<RefreshTarget>();
  private readonly onlineHandler = () => this.onOnline();

  constructor() {
    if (typeof window !== 'undefined') {
      window.addEventListener('online', this.onlineHandler);
    }

    // Follow the signed-in user and the selected arena; nobody signed in → no channel.
    effect(() => {
      const signedIn = this.session.user() !== null;
      const arenaId = this.arena.current().id;
      if (!signedIn) {
        if (this.subscribedArenaId !== null || this.activeChannel) void this.teardownCurrent();
        return;
      }
      if (arenaId !== this.subscribedArenaId) void this.setupArena(arenaId);
    });
  }

  /**
   * Tells the arena's other devices that `kind` was committed. Writes normally announce
   * themselves through pushOps after the server applied them; this is for anything else.
   */
  async broadcast(kind: string, meta: Record<string, unknown> = {}): Promise<void> {
    const channel = this.activeChannel;
    const arenaId = this.subscribedArenaId;
    if (!channel || !arenaId) return;

    try {
      await channel.send({
        type: 'broadcast',
        event: SYNC_EVENT,
        payload: {
          ...meta,
          arena_id: arenaId,
          kind,
          kinds: [kind],
          source: 'admin-web',
          at: new Date().toISOString(),
        },
      });
    } catch {
      // Not delivered: the other devices still see the rows through their own change feed.
    }
  }

  async setupArena(arenaId: string, force = false): Promise<void> {
    await this.teardownCurrent();

    const isVitest = Boolean(
      (
        (globalThis as Record<string, unknown>)['process'] as
          { env?: Record<string, string> } | undefined
      )?.env?.['VITEST'],
    );
    if (!arenaId || this.supabase.misconfigured || (isVitest && !force)) {
      return;
    }
    const run = ++this.generation;
    const live = () => run === this.generation;
    this.subscribedArenaId = arenaId;

    try {
      const client = await this.supabase.client();
      // The private channel is authorized with the user's JWT: no session, no channel.
      const { data } = await client.auth.getSession();
      const token = data.session?.access_token;
      if (!live()) return;
      if (!token) {
        this.subscribedArenaId = null;
        return;
      }
      await client.realtime.setAuth(token);
      if (!live()) return;

      const channel = client.channel(arenaTopic(arenaId), { config: { private: true } });
      const filter = `arena_id=eq.${arenaId}`;
      for (const [table, targets] of Object.entries(TABLE_TARGETS)) {
        for (const event of ['INSERT', 'UPDATE'] as const) {
          channel.on('postgres_changes', { event, schema: 'public', table, filter }, () => {
            if (live()) this.schedule(targets);
          });
        }
      }

      channel.on('broadcast', { event: SYNC_EVENT }, (message) => {
        // {type, event, payload: {...}} — what this client and the floor app send; a bare map
        // (an older floor app's broadcast) is read as the nudge itself.
        const m = message as { payload?: unknown };
        if (live()) this.onBroadcast(arenaId, m.payload ?? message);
      });

      channel.subscribe((status) => {
        if (status === 'SUBSCRIBED' && live()) {
          // Catch up on anything missed while (re)connecting.
          this.schedule(['floor_plays', 'stations', 'games', 'game_resources']);
        }
      });

      this.activeChannel = channel;
    } catch {
      // Offline: the screens still load on their own; coming back online joins again.
      if (live()) this.subscribedArenaId = null;
    }
  }

  private onBroadcast(arenaId: string, raw: unknown): void {
    const payload = (raw ?? {}) as { arena_id?: unknown; kinds?: unknown; kind?: unknown };
    // Only nudges about this arena (a message without one is not trusted to be).
    if (payload.arena_id !== arenaId) return;
    const kinds = Array.isArray(payload.kinds)
      ? payload.kinds.filter((k): k is string => typeof k === 'string')
      : null;
    if (kinds) {
      this.schedule(kinds.length ? kinds.flatMap((k) => targetsForKind(k)) : ALL_TARGETS);
    } else if (typeof payload.kind === 'string' && payload.kind !== 'push') {
      this.schedule(targetsForKind(payload.kind));
    } else {
      this.schedule(ALL_TARGETS);
    }
  }

  private async teardownCurrent(): Promise<void> {
    this.generation++;
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    this.pendingTargets.clear();

    const channel = this.activeChannel;
    this.activeChannel = null;
    this.subscribedArenaId = null;

    if (channel) {
      try {
        const client: SupabaseClient = await this.supabase.client();
        await client.removeChannel(channel);
      } catch {
        // Ignore channel unsubscribe errors during teardown
      }
    }
  }

  private onOnline(): void {
    const arenaId = this.arena.current().id;
    if (this.session.user() === null || !arenaId) return;
    if (!this.activeChannel) {
      // The channel never joined (offline at the time): join now; SUBSCRIBED catches up.
      void this.setupArena(arenaId);
      return;
    }
    this.schedule(ALL_TARGETS);
  }

  /** Coalesces rapid events within a 150ms window. */
  private schedule(targets: readonly RefreshTarget[]): void {
    if (!targets.length) return;
    for (const t of targets) {
      this.pendingTargets.add(t);
    }

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }

    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.flush();
    }, 150);
  }

  private async flush(): Promise<void> {
    const targets = new Set(this.pendingTargets);
    this.pendingTargets.clear();

    const jobs: Promise<void>[] = [];

    if (targets.has('floor_plays')) {
      jobs.push(this.floor.load(['plays', 'visits'], true));
    }
    if (targets.has('floor_charges')) {
      jobs.push(this.floor.refresh(['charges']));
    }
    if (targets.has('stations')) {
      jobs.push(this.floor.load(['stations'], true));
    }
    if (targets.has('games')) {
      jobs.push(this.floor.load(['games'], true));
    }
    if (targets.has('game_resources')) {
      jobs.push(this.floor.refresh(['gameResources']));
    }
    if (targets.has('customers')) {
      jobs.push(this.floor.load(['customers'], true));
    }
    if (targets.has('sales')) {
      jobs.push(this.sales.refresh());
    }
    if (targets.has('overview')) {
      jobs.push(this.overview.refresh());
    }
    if (targets.has('pricing')) {
      jobs.push(this.pricing.load(true));
    }
    if (targets.has('settings')) {
      jobs.push(this.floorOptions.load(true));
    }
    if (targets.has('users')) {
      jobs.push(this.users.refresh());
    }
    if (targets.has('arena')) {
      jobs.push(this.arena.load(true));
    }

    await Promise.allSettled(jobs);
  }

  destroy(): void {
    if (typeof window !== 'undefined') {
      window.removeEventListener('online', this.onlineHandler);
    }
    void this.teardownCurrent();
  }
}
