import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ArenaContext } from '../arena/arena-context';
import { Account } from '../auth/auth-api';
import { Session } from '../auth/session';
import { FloorStore } from '../floor/floor-store';
import { FloorOptionsStore } from '../../features/settings/data/floor-options';
import { OverviewStore } from '../../features/overview/data/overview-store';
import { PricingStore } from '../../features/pricing/data/pricing-store';
import { SalesStore } from '../../features/sales/data/sales-store';
import { UsersStore } from '../../features/users/data/users-store';
import { Supabase } from '../supabase/supabase';
import { RealtimeSync, TABLE_TARGETS } from './realtime-sync';

describe('RealtimeSync', () => {
  let sync: RealtimeSync;
  let mockFloor: { load: ReturnType<typeof vi.fn>; refresh: ReturnType<typeof vi.fn> };
  let mockSales: { refresh: ReturnType<typeof vi.fn> };
  let mockOverview: { refresh: ReturnType<typeof vi.fn> };
  let mockPricing: { load: ReturnType<typeof vi.fn> };
  let mockFloorOptions: { load: ReturnType<typeof vi.fn> };
  let mockUsers: { refresh: ReturnType<typeof vi.fn> };
  let mockArenaContext: { current: ReturnType<typeof vi.fn>; load: ReturnType<typeof vi.fn> };
  let user: ReturnType<typeof signal<Account | null>>;
  let sessionToken: string | null;
  const order: string[] = [];

  /** Last handler per table (any event), and every subscription made. */
  const postgresHandlers = new Map<string, (payload: unknown) => void>();
  const subscriptions: { table: string; event: string; filter: string; schema: string }[] = [];
  const broadcastHandlers = new Map<string, (payload: unknown) => void>();
  let channelSubscribeCallback: ((status: string) => void) | null = null;
  const mockChannel = {
    on: vi.fn((type: string, filter: unknown, cb: (payload: unknown) => void) => {
      if (type === 'postgres_changes') {
        const f = filter as { table: string; event: string; filter: string; schema: string };
        postgresHandlers.set(f.table, cb);
        subscriptions.push({ table: f.table, event: f.event, filter: f.filter, schema: f.schema });
      } else if (type === 'broadcast') {
        const event = (filter as { event: string }).event;
        broadcastHandlers.set(event, cb);
      }
      return mockChannel;
    }),
    subscribe: vi.fn((cb?: (status: string) => void) => {
      order.push('subscribe');
      if (cb) channelSubscribeCallback = cb;
      return mockChannel;
    }),
    send: vi.fn().mockResolvedValue('ok'),
  } as unknown as RealtimeChannel;

  const mockClient = {
    channel: vi.fn().mockReturnValue(mockChannel),
    removeChannel: vi.fn().mockResolvedValue('ok'),
    auth: {
      getSession: vi.fn(async () => ({
        data: { session: sessionToken ? { access_token: sessionToken } : null },
      })),
    },
    realtime: {
      setAuth: vi.fn(async () => {
        order.push('setAuth');
      }),
    },
  } as unknown as SupabaseClient;

  beforeEach(() => {
    vi.useFakeTimers();
    postgresHandlers.clear();
    subscriptions.length = 0;
    broadcastHandlers.clear();
    order.length = 0;
    channelSubscribeCallback = null;
    sessionToken = 'jwt-of-arjun';
    vi.clearAllMocks();

    mockFloor = {
      load: vi.fn().mockResolvedValue(undefined),
      refresh: vi.fn().mockResolvedValue(undefined),
    };
    mockSales = { refresh: vi.fn().mockResolvedValue(undefined) };
    mockOverview = { refresh: vi.fn().mockResolvedValue(undefined) };
    mockPricing = { load: vi.fn().mockResolvedValue(undefined) };
    mockFloorOptions = { load: vi.fn().mockResolvedValue(undefined) };
    mockUsers = { refresh: vi.fn().mockResolvedValue(undefined) };
    user = signal<Account | null>({ id: 'u0', email: 'arjun@404arena.in', name: 'Arjun Mehra' });

    mockArenaContext = {
      current: vi.fn().mockReturnValue({ id: 'arena-123', name: 'Test Arena' }),
      load: vi.fn().mockResolvedValue(undefined),
    };

    const mockSupabase = {
      misconfigured: false,
      client: vi.fn().mockResolvedValue(mockClient),
    };

    TestBed.configureTestingModule({
      providers: [
        RealtimeSync,
        { provide: ArenaContext, useValue: mockArenaContext },
        { provide: Session, useValue: { user } },
        { provide: Supabase, useValue: mockSupabase },
        { provide: FloorStore, useValue: mockFloor },
        { provide: SalesStore, useValue: mockSales },
        { provide: OverviewStore, useValue: mockOverview },
        { provide: PricingStore, useValue: mockPricing },
        { provide: FloorOptionsStore, useValue: mockFloorOptions },
        { provide: UsersStore, useValue: mockUsers },
      ],
    });

    sync = TestBed.inject(RealtimeSync);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const broadcast = (payload: unknown) => broadcastHandlers.get('sync')!({ payload });

  it('subscribes to channel arena:arena-123 with postgres changes and broadcast', async () => {
    await sync.setupArena('arena-123', true);

    expect(mockClient.channel).toHaveBeenCalledWith('arena:arena-123', {
      config: { private: true },
    });
    expect(mockChannel.subscribe).toHaveBeenCalled();
    expect(postgresHandlers.has('sessions')).toBe(true);
    expect(postgresHandlers.has('payments')).toBe(true);
    expect(postgresHandlers.has('games')).toBe(true);
    expect(postgresHandlers.has('resources')).toBe(true);
    expect(postgresHandlers.has('settings')).toBe(true);
    expect(broadcastHandlers.has('sync')).toBe(true);
  });

  it('joins the private channel only after handing Realtime the user JWT', async () => {
    await sync.setupArena('arena-123', true);
    expect(mockClient.realtime.setAuth).toHaveBeenCalledWith('jwt-of-arjun');
    expect(order).toEqual(['setAuth', 'subscribe']);
  });

  it('opens no channel without a session', async () => {
    sessionToken = null;
    await sync.setupArena('arena-123', true);
    expect(mockClient.channel).not.toHaveBeenCalled();
  });

  it('subscribes INSERT and UPDATE of every shown table, filtered by arena — never DELETE', async () => {
    await sync.setupArena('arena-123', true);

    const events = new Set(subscriptions.map((s) => s.event));
    expect(events).toEqual(new Set(['INSERT', 'UPDATE']));
    expect(subscriptions.every((s) => s.filter === 'arena_id=eq.arena-123')).toBe(true);
    expect(subscriptions.every((s) => s.schema === 'public')).toBe(true);
    const tables = [...new Set(subscriptions.map((s) => s.table))].sort();
    expect(tables).toEqual(
      [
        'activities',
        'billing_policies',
        'customers',
        'game_categories',
        'game_controls',
        'game_resources',
        'games',
        'group_assignments',
        'group_charges',
        'group_extensions',
        'group_payments',
        'group_sessions',
        'holidays',
        'payments',
        'rate_bands',
        'rate_cards',
        'rates',
        'resource_activities',
        'resources',
        'session_charges',
        'session_extensions',
        'session_segments',
        'sessions',
        'settings',
        'staff_profiles',
      ].sort(),
    );
    expect(tables).toEqual(Object.keys(TABLE_TARGETS).sort());
    for (const table of tables) {
      expect(subscriptions.filter((s) => s.table === table).map((s) => s.event)).toEqual([
        'INSERT',
        'UPDATE',
      ]);
    }
  });

  it('coalesces rapid session changes and reloads floor, overview, and sales', async () => {
    await sync.setupArena('arena-123', true);

    const onSessions = postgresHandlers.get('sessions')!;
    const onSegments = postgresHandlers.get('session_segments')!;

    onSessions({ eventType: 'INSERT' });
    onSegments({ eventType: 'INSERT' });
    onSessions({ eventType: 'UPDATE' });

    vi.advanceTimersByTime(100);
    expect(mockFloor.load).not.toHaveBeenCalled();

    vi.advanceTimersByTime(60);
    expect(mockFloor.load).toHaveBeenCalledTimes(1);
    expect(mockFloor.load).toHaveBeenCalledWith(['plays', 'visits'], true);
    expect(mockOverview.refresh).toHaveBeenCalledTimes(1);
    expect(mockSales.refresh).toHaveBeenCalledTimes(1);
  });

  it('reloads games when game table changes occur', async () => {
    await sync.setupArena('arena-123', true);

    const onGames = postgresHandlers.get('games')!;
    onGames({ eventType: 'UPDATE' });

    vi.advanceTimersByTime(160);
    expect(mockFloor.load).toHaveBeenCalledWith(['games'], true);
    expect(mockSales.refresh).not.toHaveBeenCalled();
  });

  it('reloads stations when resources table changes occur', async () => {
    await sync.setupArena('arena-123', true);

    const onResources = postgresHandlers.get('resources')!;
    onResources({ eventType: 'UPDATE' });

    vi.advanceTimersByTime(160);
    expect(mockFloor.load).toHaveBeenCalledWith(['stations'], true);
  });

  it('reloads floor options when settings table changes occur', async () => {
    await sync.setupArena('arena-123', true);

    const onSettings = postgresHandlers.get('settings')!;
    onSettings({ eventType: 'UPDATE' });

    vi.advanceTimersByTime(160);
    expect(mockFloorOptions.load).toHaveBeenCalledWith(true);
    // Business and happy hours are settings rows: pricing reloads too.
    expect(mockPricing.load).toHaveBeenCalledWith(true);
  });

  it('routes the newly published tables to the stores that show them', async () => {
    await sync.setupArena('arena-123', true);
    const fire = (table: string) => {
      vi.clearAllMocks();
      postgresHandlers.get(table)!({ eventType: 'INSERT' });
      vi.advanceTimersByTime(160);
    };

    fire('game_resources');
    expect(mockFloor.refresh).toHaveBeenCalledWith(['gameResources']);
    expect(mockFloor.load).not.toHaveBeenCalled();

    fire('game_controls');
    expect(mockFloor.load).toHaveBeenCalledWith(['games'], true);
    fire('game_categories');
    expect(mockFloor.load).toHaveBeenCalledWith(['games'], true);

    fire('staff_profiles');
    expect(mockUsers.refresh).toHaveBeenCalledTimes(1);
    expect(mockSales.refresh).not.toHaveBeenCalled();

    for (const table of [
      'group_sessions',
      'group_assignments',
      'group_payments',
      'group_extensions',
    ]) {
      fire(table);
      expect(mockFloor.load).toHaveBeenCalledWith(['plays', 'visits'], true);
      expect(mockOverview.refresh).toHaveBeenCalledTimes(1);
      expect(mockSales.refresh).toHaveBeenCalledTimes(1);
    }

    for (const table of ['session_charges', 'group_charges']) {
      fire(table);
      expect(mockSales.refresh).toHaveBeenCalledTimes(1);
      expect(mockOverview.refresh).toHaveBeenCalledTimes(1);
      expect(mockFloor.refresh).toHaveBeenCalledWith(['charges']);
    }

    fire('session_extensions');
    expect(mockSales.refresh).toHaveBeenCalledTimes(1);
    expect(mockOverview.refresh).toHaveBeenCalledTimes(1);

    for (const table of ['holidays', 'billing_policies', 'rate_cards', 'rate_bands', 'rates']) {
      fire(table);
      expect(mockPricing.load).toHaveBeenCalledWith(true);
      expect(mockFloorOptions.load).toHaveBeenCalledWith(true);
      expect(mockSales.refresh).not.toHaveBeenCalled();
    }
  });

  it('handles peer broadcast sync messages for matching arena', async () => {
    await sync.setupArena('arena-123', true);

    const onBroadcast = broadcastHandlers.get('sync')!;
    onBroadcast({
      payload: { arena_id: 'arena-123', kind: 'session.start' },
    });

    vi.advanceTimersByTime(160);
    expect(mockFloor.load).toHaveBeenCalledWith(['plays', 'visits'], true);
    expect(mockOverview.refresh).toHaveBeenCalledTimes(1);
  });

  it('routes a committed push by its applied kinds', async () => {
    await sync.setupArena('arena-123', true);
    broadcast({
      arena_id: 'arena-123',
      kind: 'push',
      kinds: ['game.set_compat', 'staff.update', 'controller.move'],
      source: 'mobile',
      at: '2026-10-13T14:00:00Z',
    });
    vi.advanceTimersByTime(160);

    expect(mockFloor.refresh).toHaveBeenCalledWith(['gameResources']);
    expect(mockUsers.refresh).toHaveBeenCalledTimes(1);
    expect(mockFloor.load).not.toHaveBeenCalled();
    expect(mockSales.refresh).not.toHaveBeenCalled();
    expect(mockPricing.load).not.toHaveBeenCalled();
  });

  it('a push of settings or payments refreshes pricing or the bills', async () => {
    await sync.setupArena('arena-123', true);
    broadcast({ arena_id: 'arena-123', kind: 'push', kinds: ['settings.save'], source: 'mobile' });
    vi.advanceTimersByTime(160);
    expect(mockPricing.load).toHaveBeenCalledWith(true);
    expect(mockFloorOptions.load).toHaveBeenCalledWith(true);

    vi.clearAllMocks();
    broadcast({ arena_id: 'arena-123', kind: 'push', kinds: ['payment.record'], source: 'mobile' });
    vi.advanceTimersByTime(160);
    expect(mockSales.refresh).toHaveBeenCalledTimes(1);
    expect(mockOverview.refresh).toHaveBeenCalledTimes(1);
    expect(mockPricing.load).not.toHaveBeenCalled();
  });

  it('reads a bare-map nudge (an older floor app) as the nudge itself', async () => {
    await sync.setupArena('arena-123', true);
    broadcastHandlers.get('sync')!({
      type: 'broadcast',
      event: 'sync',
      arena_id: 'arena-123',
      kind: 'push',
      kinds: ['payment.record'],
      source: 'mobile',
    });
    vi.advanceTimersByTime(160);
    expect(mockSales.refresh).toHaveBeenCalledTimes(1);

    vi.clearAllMocks();
    broadcastHandlers.get('sync')!({ type: 'broadcast', event: 'sync', arena_id: 'other', kind: 'push' });
    vi.advanceTimersByTime(160);
    expect(mockSales.refresh).not.toHaveBeenCalled();
  });

  it('falls back to a full refresh when a push names no kinds', async () => {
    await sync.setupArena('arena-123', true);
    broadcast({ arena_id: 'arena-123', kind: 'push', source: 'mobile' });
    vi.advanceTimersByTime(160);

    expect(mockFloor.load).toHaveBeenCalledWith(['plays', 'visits'], true);
    expect(mockFloor.load).toHaveBeenCalledWith(['stations'], true);
    expect(mockFloor.load).toHaveBeenCalledWith(['games'], true);
    expect(mockSales.refresh).toHaveBeenCalled();
    expect(mockOverview.refresh).toHaveBeenCalled();
    expect(mockPricing.load).toHaveBeenCalledWith(true);
    expect(mockUsers.refresh).toHaveBeenCalled();
  });

  it('ignores peer broadcast messages from a different arena', async () => {
    await sync.setupArena('arena-123', true);

    const onBroadcast = broadcastHandlers.get('sync')!;
    onBroadcast({
      payload: { arena_id: 'other-arena-999', kind: 'session.start' },
    });
    // No arena named: not this arena's either.
    onBroadcast({ payload: { kind: 'push', kinds: ['session.start'] } });

    vi.advanceTimersByTime(160);
    expect(mockFloor.load).not.toHaveBeenCalled();
    expect(mockSales.refresh).not.toHaveBeenCalled();
  });

  it('tears down previous channel when switching arenas', async () => {
    await sync.setupArena('arena-123', true);
    expect(mockClient.channel).toHaveBeenCalledWith('arena:arena-123', {
      config: { private: true },
    });

    await sync.setupArena('arena-456', true);
    expect(mockClient.removeChannel).toHaveBeenCalledWith(mockChannel);
    expect(mockClient.channel).toHaveBeenCalledWith('arena:arena-456', {
      config: { private: true },
    });
  });

  it('tears the channel down when the user signs out', async () => {
    TestBed.tick();
    await sync.setupArena('arena-123', true);
    expect(mockClient.removeChannel).not.toHaveBeenCalled();

    user.set(null);
    TestBed.tick();
    await vi.waitFor(() => expect(mockClient.removeChannel).toHaveBeenCalledWith(mockChannel));

    // Nothing left to refresh for a signed-out dashboard.
    postgresHandlers.get('sessions')!({ eventType: 'INSERT' });
    window.dispatchEvent(new Event('online'));
    vi.advanceTimersByTime(160);
    expect(mockFloor.load).not.toHaveBeenCalled();
  });

  it('catches up once subscribed', async () => {
    await sync.setupArena('arena-123', true);
    channelSubscribeCallback!('SUBSCRIBED');
    vi.advanceTimersByTime(160);
    expect(mockFloor.load).toHaveBeenCalledWith(['plays', 'visits'], true);
    expect(mockFloor.refresh).toHaveBeenCalledWith(['gameResources']);
  });

  it('broadcasts outgoing sync messages on active channel', async () => {
    await sync.setupArena('arena-123', true);

    await sync.broadcast('resource.upsert', { id: 'station-1' });
    expect(mockChannel.send).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'broadcast',
        event: 'sync',
        payload: expect.objectContaining({
          arena_id: 'arena-123',
          kind: 'resource.upsert',
          kinds: ['resource.upsert'],
        }),
      }),
    );
  });
});
