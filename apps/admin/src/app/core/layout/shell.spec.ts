import { TestBed } from '@angular/core/testing';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { Session } from '../auth/session';
import { NAV_ITEMS } from './nav';

describe('Shell', () => {
  let harness: RouterTestingHarness;

  beforeEach(async () => {
    TestBed.configureTestingModule({
      providers: [provideRouter(routes, withComponentInputBinding())],
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
    expect(root().textContent).toContain('Koramangala');
    expect(root().textContent).toContain('Arjun Mehra');
  });

  it('signs out to the sign-in screen and keeps the shell behind sign-in', async () => {
    await harness.navigateByUrl('/overview');
    TestBed.inject(Session).signOut();
    await harness.fixture.whenStable();
    expect(root().querySelector('h1')?.textContent).toContain('Owner sign in');

    await harness.navigateByUrl('/staff');
    expect(root().querySelector('nav[aria-label="Main"]')).toBeNull();
  });
});
