import { PlatformLocation } from '@angular/common';
import { TestBed } from '@angular/core/testing';
import { MATERIAL_ANIMATIONS } from '@angular/material/core';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { ArenaApi } from '../../core/arena/arena-api';
import { SampleArenaApi } from '../../core/arena/arena-api.sample';
import { AppError, AuthApi } from '../../core/auth/auth-api';
import { SampleAuthApi } from '../../core/auth/auth-api.sample';
import { LOCAL_SERVER } from '../../core/supabase/local-server';
import { UsersApi } from '../users/data/users-api';
import { SampleUsersApi } from '../users/data/users-api.sample';
import { RESET_LINK_EXPIRED, RESET_LINK_INCOMPLETE } from './reset-password';

/** What Supabase Auth appends to the reset link's redirect (implicit flow). */
const recovery = (access = 'at-arjun', type = 'recovery') =>
  `#access_token=${access}&expires_at=1792000000&expires_in=3600&refresh_token=rt-1&token_type=bearer&type=${type}`;

describe('Reset password (from the e-mailed link)', () => {
  let harness: RouterTestingHarness;
  let auth: SampleAuthApi;
  let arenas: SampleArenaApi;

  async function start(
    url: string,
    o: { owner?: boolean; prepare?: (auth: SampleAuthApi) => void } = {},
  ) {
    auth = new SampleAuthApi(false);
    auth.linkTokens.set('at-arjun', 'arjun@404arena.in');
    o.prepare?.(auth);
    arenas = new SampleArenaApi(o.owner ?? true);
    if (o.owner === false) {
      // Floor staff of one arena: no dashboard.
      arenas.memberships.push({
        arenaId: 'a1',
        arenaName: '404 Arena Koramangala',
        name: 'Arjun Mehra',
        role: 'staff',
        perms: ['start', 'bill'],
        active: true,
      });
    }
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: auth },
        { provide: ArenaApi, useValue: arenas },
        { provide: UsersApi, useValue: new SampleUsersApi() },
        { provide: MATERIAL_ANIMATIONS, useValue: { animationsDisabled: true } },
        { provide: LOCAL_SERVER, useValue: null },
      ],
    });
    harness = await RouterTestingHarness.create();
    await harness.navigateByUrl(url);
    await settle();
  }

  async function settle() {
    for (let i = 0; i < 3; i++) {
      await harness.fixture.whenStable();
      await new Promise((r) => setTimeout(r));
    }
  }

  const body = () => harness.routeNativeElement?.ownerDocument.body as HTMLElement;
  const heading = () => body().querySelector('h1')?.textContent?.trim();
  const alert = () => body().querySelector('[role="alert"]')?.textContent?.trim();
  const url = () => TestBed.inject(Router).url;
  const address = () => {
    const l = TestBed.inject(PlatformLocation);
    return l.pathname + l.search + l.hash;
  };

  function type(label: string, value: string) {
    const field = [...body().querySelectorAll('mat-form-field')].find((f) =>
      f.querySelector('mat-label')?.textContent?.includes(label),
    );
    const input = field?.querySelector('input') as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event('input'));
  }

  async function press(label: string) {
    const target = [...body().querySelectorAll('button, a')].find((b) =>
      b.textContent?.includes(label),
    ) as HTMLElement;
    target.click();
    await settle();
  }

  it('takes the session tokens out of the address straight away', async () => {
    await start('/reset-password' + recovery());
    expect(address()).toBe('/reset-password');
    expect(TestBed.inject(PlatformLocation).href).not.toContain('at-arjun');
    expect(TestBed.inject(PlatformLocation).href).not.toContain('rt-1');
  });

  it('an owner chooses a new password, then opens the dashboard and can sign in with it', async () => {
    await start('/reset-password' + recovery());
    expect(heading()).toBe('Choose a new password');
    expect(body().textContent).toContain('For arjun@404arena.in.');

    type('New password', 'short');
    type('Type it again', 'short');
    await press('Save new password');
    expect(alert()).toBe('Use at least 10 characters');

    type('New password', 'fresh-pass-77');
    type('Type it again', 'fresh-pass-78');
    await press('Save new password');
    expect(alert()).toBe('The two passwords are different');
    expect(auth.calls).toEqual(['link:at-arjun']);

    type('Type it again', 'fresh-pass-77');
    await press('Save new password');
    expect(auth.calls).toEqual(['link:at-arjun', 'setPassword']);
    expect(heading()).toBe('Password changed');
    expect(body().ownerDocument.activeElement?.textContent).toContain('Open dashboard');

    await press('Open dashboard');
    expect(url()).toBe('/overview');

    // The new password is the one that works now.
    await auth.signOut();
    await expect(auth.signIn('arjun@404arena.in', 'arena-pass-42')).rejects.toMatchObject({
      code: 'invalid_credentials',
    });
    await auth.signIn('arjun@404arena.in', 'fresh-pass-77');
  });

  it('floor staff are told to sign in on the staff app, and leave the dashboard signed out', async () => {
    await start('/reset-password' + recovery(), { owner: false });
    type('New password', 'floor-pass-42');
    type('Type it again', 'floor-pass-42');
    await press('Save new password');

    expect(heading()).toBe('Password changed');
    expect(body().textContent).toContain(
      'Sign in on the staff app with arjun@404arena.in and your new password.',
    );
    expect(body().textContent).not.toContain('Open dashboard');

    await press('Done');
    expect(auth.account).toBeNull();
    expect(url()).toBe('/sign-in');
  });

  it('a refused password is explained and can be chosen again', async () => {
    await start('/reset-password' + recovery());
    auth.setPassword = async () => {
      throw new AppError('same_password', 'That is already your password. Choose a new one');
    };
    type('New password', 'arena-pass-42');
    type('Type it again', 'arena-pass-42');
    await press('Save new password');
    expect(alert()).toBe('That is already your password. Choose a new one');
    expect(heading()).toBe('Choose a new password');
  });

  it('a used or expired link says to ask for a new one, which opens the reset request', async () => {
    await start(
      '/reset-password#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
    );
    expect(heading()).toBe('Password reset link');
    expect(alert()).toBe(RESET_LINK_EXPIRED);
    expect(auth.calls).toEqual([]);
    expect(address()).toBe('/reset-password');

    await press('Ask for a new link');
    expect(url()).toBe('/sign-in?step=forgot');
    expect(heading()).toBe('Reset your password');
  });

  it('a link the server no longer accepts is expired too', async () => {
    await start('/reset-password' + recovery('at-unknown'));
    expect(alert()).toBe(RESET_LINK_EXPIRED);
    expect(auth.account).toBeNull();
  });

  for (const [name, link] of [
    ['no tokens', '/reset-password'],
    ['another kind of link', '/reset-password' + recovery('at-arjun', 'magiclink')],
  ] as const) {
    it(`a link with ${name} is incomplete and asks nothing of the server`, async () => {
      await start(link);
      expect(alert()).toBe(RESET_LINK_INCOMPLETE);
      expect(auth.calls).toEqual([]);
    });
  }

  it('offline: says so and tries the same link again', async () => {
    let offline = true;
    await start('/reset-password' + recovery(), {
      prepare: (sample) => {
        const signInFromLink = sample.signInFromLink.bind(sample);
        sample.signInFromLink = async (access, refresh) => {
          if (offline) throw new AppError('network', 'Could not reach the server');
          return signInFromLink(access, refresh);
        };
      },
    });
    expect(heading()).toBe('Password reset link');
    expect(alert()).toBe('Could not reach the server');

    offline = false;
    await press('Try again');
    expect(heading()).toBe('Choose a new password');
  });
});
