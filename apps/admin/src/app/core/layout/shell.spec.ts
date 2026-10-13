import { TestBed } from '@angular/core/testing';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { UsersApi } from '../../features/users/data/users-api';
import { SampleUsersApi } from '../../features/users/data/users-api.sample';
import { ArenaApi } from '../arena/arena-api';
import { SampleArenaApi } from '../arena/arena-api.sample';
import { AuthApi } from '../auth/auth-api';
import { SampleAuthApi } from '../auth/auth-api.sample';
import { Session } from '../auth/session';
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
