import { TestBed } from '@angular/core/testing';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { OverviewStore } from '../../features/overview/data/overview-store';
import { PricingStore } from '../../features/pricing/data/pricing-store';
import { periodFor } from '../../features/sales/data/sale.models';
import { SalesStore } from '../../features/sales/data/sales-store';
import { FloorOptionsStore } from '../../features/settings/data/floor-options';
import { UsersApi } from '../../features/users/data/users-api';
import { SampleUsersApi } from '../../features/users/data/users-api.sample';
import { UsersStore } from '../../features/users/data/users-store';
import { NOW, PageTest, startPage } from '../../testing/page-test';
import { ArenaApi } from '../arena/arena-api';
import { SampleArenaApi } from '../arena/arena-api.sample';
import { ArenaContext } from '../arena/arena-context';
import { AuthApi } from '../auth/auth-api';
import { SampleAuthApi } from '../auth/auth-api.sample';
import { LoginScope } from '../auth/login-scope';
import { Session } from '../auth/session';
import { FloorStore } from '../floor/floor-store';
import { NAV_ITEMS } from './nav';

describe('Shell', () => {
  let harness: RouterTestingHarness;

  beforeEach(async () => {
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: new SampleAuthApi() },
        { provide: ArenaApi, useValue: new SampleArenaApi() },
        { provide: UsersApi, useValue: new SampleUsersApi() },
      ],
    });
    harness = await RouterTestingHarness.create();
  });

  const root = () => harness.routeNativeElement?.ownerDocument.body as HTMLElement;

  it('lists every destination in the design order', async () => {
    await harness.navigateByUrl('/overview');
    const labels = [...root().querySelectorAll('nav[aria-label="Main"] a')].map((a) =>
      a.getAttribute('title'),
    );
    expect(labels).toEqual(NAV_ITEMS.map((item) => item.label));
  });

  it('marks the current page and shows its title', async () => {
    await harness.navigateByUrl('/sales');
    const current = root().querySelector('a[aria-current="page"]');
    expect(current?.getAttribute('title')).toBe('Sales');
    expect(root().querySelector('h1')?.textContent).toContain('Sales');
  });

  it('shows the selected arena and the signed-in owner', async () => {
    await harness.navigateByUrl('/overview');
    expect(root().textContent).toContain('404 Arena Koramangala');
    expect(root().textContent).toContain('Arjun Mehra');
  });

  it('signs out to the sign-in screen and keeps the shell behind sign-in', async () => {
    await harness.navigateByUrl('/overview');
    await TestBed.inject(Session).signOut();
    await harness.fixture.whenStable();
    expect(root().querySelector('h1')?.textContent).toContain('Owner sign in');

    await harness.navigateByUrl('/users');
    expect(root().querySelector('nav[aria-label="Main"]')).toBeNull();
  });
});

describe('Shell: a login’s data and access', () => {
  let p: PageTest;

  async function start(path = '/sales') {
    TestBed.configureTestingModule({
      providers: [{ provide: UsersApi, useValue: new SampleUsersApi() }],
    });
    p = await startPage(path);
  }

  const auth = () => TestBed.inject(AuthApi) as SampleAuthApi;
  const arenas = () => TestBed.inject(ArenaApi) as SampleArenaApi;

  /** Fills every store, as the screens would. */
  async function loadEverything() {
    await Promise.all([
      TestBed.inject(FloorStore).load(['stations', 'games', 'plays']),
      TestBed.inject(OverviewStore).load('today'),
      TestBed.inject(PricingStore).load(),
      TestBed.inject(FloorOptionsStore).load(),
      TestBed.inject(UsersStore).load(),
    ]);
  }

  afterEach(() => p.cleanup());

  it('signing out clears every store and ends the session on the server', async () => {
    await start();
    await loadEverything();
    expect(TestBed.inject(SalesStore).bills().length).toBeGreaterThan(0);
    expect(TestBed.inject(FloorStore).stations().length).toBeGreaterThan(0);
    expect(TestBed.inject(UsersStore).users().length).toBeGreaterThan(0);

    (p.doc().querySelector('button[aria-label="Sign out"]') as HTMLButtonElement).click();
    await p.settle();

    expect(auth().calls).toContain('signOut');
    expect(p.url()).toBe('/sign-in');
    const floor = TestBed.inject(FloorStore);
    expect(floor.stations()).toEqual([]);
    expect(floor.games()).toEqual([]);
    expect(floor.plays()).toEqual([]);
    expect(floor.stationsReady()).toBe(false);
    expect(TestBed.inject(SalesStore).bills()).toEqual([]);
    expect(TestBed.inject(OverviewStore).bills()).toEqual([]);
    expect(TestBed.inject(OverviewStore).range()).toBeNull();
    expect(TestBed.inject(PricingStore).data()).toBeNull();
    expect(TestBed.inject(FloorOptionsStore).options()).toBeNull();
    expect(TestBed.inject(UsersStore).users()).toEqual([]);
    expect(TestBed.inject(UsersStore).invites()).toEqual([]);
    expect(TestBed.inject(ArenaContext).memberships()).toEqual([]);
  });

  it('a read still in flight when the login signs out never lands', async () => {
    await start('/overview');
    let release: () => void = () => undefined;
    const held = new Promise<void>((r) => (release = r));
    const slow =
      <T>(read: () => Promise<T>) =>
      () =>
        held.then(read);
    const sales = p.sales.list.bind(p.sales);
    const stations = p.floor.stations.bind(p.floor);
    p.sales.list = (...args) => slow(() => sales(...args))();
    p.floor.stations = slow(stations);

    const reads = Promise.all([
      TestBed.inject(SalesStore).load(periodFor('today', undefined, undefined, NOW), true),
      TestBed.inject(FloorStore).load(['stations'], true),
    ]);
    await TestBed.inject(Session).signOut();
    release();
    await reads;

    expect(TestBed.inject(SalesStore).bills()).toEqual([]);
    expect(TestBed.inject(SalesStore).loading()).toBe(false);
    expect(TestBed.inject(FloorStore).stations()).toEqual([]);
    expect(TestBed.inject(FloorStore).loading()).toBe(false);
  });

  it('another login signing in (another tab) opens the dashboard afresh for it', async () => {
    await start();
    expect(TestBed.inject(SalesStore).bills().length).toBeGreaterThan(0);
    // What the stores hold the moment the login changes (this clear runs after theirs).
    const atChange: number[] = [];
    TestBed.inject(LoginScope).onEnd(() =>
      atChange.push(
        TestBed.inject(SalesStore).bills().length,
        TestBed.inject(ArenaContext).memberships().length,
      ),
    );

    await auth().signIn('arjun@404arena.in', 'arena-pass-42');
    await p.settle();

    expect(atChange).toEqual([0, 0]);
    expect(p.url()).toBe('/overview');
    expect(TestBed.inject(ArenaContext).loaded()).toBe(true);
  });

  it('a manager whose access is turned off elsewhere loses the dashboard without a reload', async () => {
    await start();
    arenas().memberships = arenas().memberships.map((m) => ({ ...m, active: false }));

    // What a live staff change triggers (RealtimeSync → ArenaContext.load(true)).
    await TestBed.inject(ArenaContext).load(true);
    await p.settle();

    // Never Create Arena: the account page says access is off (an owner's: the operator restores).
    expect(p.url()).toBe('/account');
    expect(p.doc().querySelector('nav[aria-label="Main"]')).toBeNull();
    expect(p.text(p.doc().body)).toContain('Your access is turned off');
    expect(p.text(p.doc().body)).toContain('Ask the operator to restore it.');
  });

  it('access narrowed to floor work everywhere: told to use the staff app, not Create Arena', async () => {
    await start();
    arenas().memberships = arenas().memberships.map((m) => ({
      ...m,
      role: 'staff' as const,
      perms: ['start', 'bill'],
    }));
    await TestBed.inject(ArenaContext).load(true);
    await p.settle();
    expect(p.url()).toBe('/account');
    expect(p.text(p.doc().body)).toContain('Use the 404 Arena staff app');
    expect(p.doc().querySelector('input')).toBeNull();
  });

  it('access narrowed in one arena: the dashboard moves to the arena still managed', async () => {
    await start();
    const [first, second] = arenas().memberships;
    TestBed.inject(ArenaContext).select(first.arenaId);
    await p.settle();
    arenas().memberships = [{ ...first, role: 'staff', perms: ['start', 'bill'] }, second];

    await TestBed.inject(ArenaContext).load(true);
    await p.settle();

    expect(TestBed.inject(ArenaContext).current().id).toBe(second.arenaId);
    expect(p.text(p.doc().body)).toContain(second.arenaName);
    expect(p.url()).toBe('/sales');
  });

  it('settings taken away live: the dashboard turns view-only', async () => {
    await start();
    const context = TestBed.inject(ArenaContext);
    expect(p.text(p.doc().body)).not.toContain('View only.');
    arenas().memberships = arenas().memberships.map((m) => ({
      ...m,
      role: 'staff' as const,
      perms: ['money'],
    }));

    await context.load(true);
    await p.settle();

    expect(context.canEdit()).toBe(false);
    expect(p.text(p.doc().body)).toContain('View only.');
    expect(p.url()).toBe('/sales');
  });
});
