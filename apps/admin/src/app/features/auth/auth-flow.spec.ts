import { TestBed } from '@angular/core/testing';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { ArenaApi } from '../../core/arena/arena-api';
import { SampleArenaApi } from '../../core/arena/arena-api.sample';
import { AppError, AuthApi } from '../../core/auth/auth-api';
import { SampleAuthApi } from '../../core/auth/auth-api.sample';
import { UsersApi } from '../users/data/users-api';
import { SampleUsersApi } from '../users/data/users-api.sample';

describe('Owner auth flow', () => {
  let harness: RouterTestingHarness;
  let auth: SampleAuthApi;
  let arenas: SampleArenaApi;

  async function start(url: string, signedIn: boolean, owned: boolean) {
    auth = new SampleAuthApi(signedIn);
    arenas = new SampleArenaApi(owned);
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: auth },
        { provide: ArenaApi, useValue: arenas },
        { provide: UsersApi, useValue: new SampleUsersApi() },
      ],
    });
    harness = await RouterTestingHarness.create();
    await harness.navigateByUrl(url);
  }

  const body = () => harness.routeNativeElement?.ownerDocument.body as HTMLElement;
  const url = () => TestBed.inject(Router).url;
  const heading = () => body().querySelector('h1')?.textContent?.trim();

  function type(label: string, value: string) {
    const field = [...body().querySelectorAll('mat-form-field')].find((f) =>
      f.querySelector('mat-label')?.textContent?.includes(label),
    );
    const input = field?.querySelector('input') as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event('input'));
  }

  async function press(label: string) {
    const button = [...body().querySelectorAll('button')].find((b) =>
      b.textContent?.includes(label),
    ) as HTMLButtonElement;
    button.click();
    await harness.fixture.whenStable();
    await new Promise((r) => setTimeout(r));
    await harness.fixture.whenStable();
  }

  async function follow(label: string) {
    const link = [...body().querySelectorAll('a')].find((a) =>
      a.textContent?.includes(label),
    ) as HTMLAnchorElement;
    link.click();
    await harness.fixture.whenStable();
    await new Promise((r) => setTimeout(r));
    await harness.fixture.whenStable();
  }

  const field = (label: string) =>
    [...body().querySelectorAll('mat-form-field')]
      .find((f) => f.querySelector('mat-label')?.textContent?.includes(label))
      ?.querySelector('input') as HTMLInputElement | undefined;

  const alert = () => body().querySelector('[role="alert"]')?.textContent?.trim();
  const status = () =>
    body().querySelector('[role="status"]')?.textContent?.replace(/\s+/g, ' ').trim();

  it('a signed-out visitor is sent to sign in', async () => {
    await start('/users', false, true);
    expect(heading()).toBe('Owner sign in');
  });

  it('wrong credentials are explained and nothing opens', async () => {
    await start('/sign-in', false, true);
    type('Email', 'arjun@404arena.in');
    type('Password', 'not-it-123');
    await press('Sign in');
    expect(alert()).toBe('Wrong email or password');
    expect(url()).toBe('/sign-in');
  });

  it('fields are checked before the server', async () => {
    await start('/sign-in', false, true);
    await press('Sign in');
    expect(alert()).toBe('Enter your email');
    expect(auth.calls).toEqual([]);
  });

  it('an owner signs in to the dashboard', async () => {
    await start('/sign-in', false, true);
    type('Email', 'arjun@404arena.in');
    type('Password', 'arena-pass-42');
    await press('Sign in');
    expect(url()).toBe('/overview');
  });

  /** What Supabase Auth appends to the confirmation link's redirect (implicit flow). */
  const confirmation = (access: string) =>
    `#access_token=${access}&expires_at=1792000000&expires_in=3600&refresh_token=rt-1&token_type=bearer&type=signup`;

  it('register: password rules, then the link, then create the arena', async () => {
    await start('/register', false, false);
    expect(heading()).toBe('Create your account');
    type('Email', 'new@arena.in');
    type('Password', 'short');
    type('Type it again', 'short');
    await press('Create account');
    expect(alert()).toBe('Use at least 10 characters');

    type('Password', 'arena-pass-77');
    type('Type it again', 'arena-pass-78');
    await press('Create account');
    expect(alert()).toBe('The two passwords are different');

    type('Type it again', 'arena-pass-77');
    await press('Create account');
    expect(heading()).toBe('Check your email');
    expect(body().textContent).toContain('new@arena.in');

    await press('Resend link');
    expect(status()).toBe('Sent a new link to new@arena.in.');
    expect(auth.calls).toEqual(['signUp:new@arena.in', 'resend:new@arena.in']);

    // A used or expired link confirms nothing.
    await follow('Back to sign in');
    await harness.navigateByUrl('/register#error=access_denied&error_code=otp_expired');
    await settled();
    expect(heading()).toBe('Confirmation link');
    expect(alert()).toContain('has expired or was already used');
    expect(auth.account).toBeNull();

    // The link from the e-mail signs the new login in and goes on to create the arena.
    auth.linkTokens.set('at-new', 'new@arena.in');
    await follow('Go to sign in');
    await harness.navigateByUrl('/register' + confirmation('at-new'));
    await settled();
    expect(url()).toBe('/create-arena');
    expect(heading()).toBe('Create your arena');

    type('Arena name', 'Game Zone');
    type('Your name', 'Sam Rao');
    await press('Create arena');
    await settled();
    expect(url()).toBe('/setup');
    expect(arenas.memberships.map((m) => m.arenaName)).toEqual(['Game Zone']);
  });

  it('an unconfirmed login signing in is taken to enter its code', async () => {
    await start('/register', false, false);
    type('Email', 'late@arena.in');
    type('Password', 'arena-pass-77');
    type('Type it again', 'arena-pass-77');
    await press('Create account');
    await harness.navigateByUrl('/sign-in');
    type('Email', 'late@arena.in');
    type('Password', 'arena-pass-77');
    await press('Sign in');
    expect(heading()).toBe('Check your email');
    expect(body().textContent).toContain('late@arena.in');
  });

  it('the invitation page opens for a signed-out visitor (no guard sends it away)', async () => {
    await start('/accept-invite', false, true);
    expect(url()).toBe('/accept-invite');
    expect(heading()).toBe('Invitation link incomplete');
  });

  it('the invitation page also opens while signed in (not redirected to the dashboard)', async () => {
    await start('/accept-invite', true, true);
    expect(url()).toBe('/accept-invite');
    expect(heading()).toBe('Invitation link incomplete');
    expect(body().querySelector('nav[aria-label="Main"]')).toBeNull();
  });

  it('a signed-in login without an arena goes to create one', async () => {
    await start('/users', true, false);
    expect(url()).toBe('/create-arena');
  });

  it('forgot password: the typed email carries over, the link is sent, sign-in is one click away', async () => {
    await start('/sign-in', false, true);
    type('Email', 'Arjun@404arena.in');
    await follow('Forgot your password?');
    expect(url()).toBe('/sign-in?step=forgot');
    expect(heading()).toBe('Reset your password');
    expect(field('Email')?.value).toBe('Arjun@404arena.in');
    // The step's field takes focus (the link that was used is gone).
    expect(body().ownerDocument.activeElement).toBe(field('Email'));

    await press('Send reset link');
    expect(auth.calls).toEqual(['reset:arjun@404arena.in']);
    expect(heading()).toBe('Check your email');
    expect(status()).toBe(
      'If arjun@404arena.in has an account, we sent it a link to choose a new password. Nothing there? Check spam, or send it again.',
    );

    await press('Send again');
    expect(auth.calls).toEqual(['reset:arjun@404arena.in', 'reset:arjun@404arena.in']);

    await follow('Back to sign in');
    expect(url()).toBe('/sign-in');
    expect(heading()).toBe('Owner sign in');
  });

  it('forgot password: the email is checked before the server', async () => {
    await start('/sign-in?step=forgot', false, true);
    expect(heading()).toBe('Reset your password');
    await press('Send reset link');
    expect(alert()).toBe('Enter your email');
    type('Email', 'not-an-email');
    await press('Send reset link');
    expect(alert()).toBe('Enter a valid email');
    expect(auth.calls).toEqual([]);
  });

  it('forgot password: a refusal (too many emails) is explained and nothing moves on', async () => {
    await start('/sign-in?step=forgot', false, true);
    auth.requestPasswordReset = async () => {
      throw new AppError(
        'over_email_send_rate_limit',
        'Too many emails sent. Wait a few minutes, then try again',
      );
    };
    type('Email', 'arjun@404arena.in');
    await press('Send reset link');
    expect(alert()).toBe('Too many emails sent. Wait a few minutes, then try again');
    expect(heading()).toBe('Reset your password');
  });

  it('forgot password is for signed-out visitors (a signed-in owner stays on the dashboard)', async () => {
    await start('/sign-in?step=forgot', true, true);
    expect(url()).toBe('/overview');
  });

  async function settled() {
    for (let i = 0; i < 3; i++) {
      await harness.fixture.whenStable();
      await new Promise((r) => setTimeout(r));
    }
  }
  /** Staff in a1 only (floor permissions, no owner level). */
  const staffOnly = () => [
    {
      arenaId: 'a1',
      arenaName: '404 Arena Koramangala',
      name: 'Farah Khan',
      role: 'staff' as const,
      perms: ['start', 'bill'],
      active: true,
    },
  ];

  it('an owner who refreshes on a dashboard page stays on it (no detour)', async () => {
    await start('/sales', true, true);
    await settled();
    expect(url()).toBe('/sales');
  });

  it('an owner can never be sent to Create Arena by hand', async () => {
    await start('/create-arena', true, true);
    await settled();
    expect(url()).toBe('/overview');
  });

  it('a new owner (no membership at all) creates an arena, and only they do', async () => {
    await start('/', true, false);
    expect(url()).toBe('/create-arena');
    expect(heading()).toBe('Create your arena');
  });

  for (const target of ['/', '/sales', '/users', '/create-arena']) {
    it(`floor staff opening ${target} are told to use the staff app, never Create Arena`, async () => {
      auth = new SampleAuthApi(true);
      arenas = new SampleArenaApi(false);
      arenas.memberships = staffOnly();
      TestBed.configureTestingModule({
        providers: [
          provideRouter(routes, withComponentInputBinding()),
          { provide: AuthApi, useValue: auth },
          { provide: ArenaApi, useValue: arenas },
          { provide: UsersApi, useValue: new SampleUsersApi() },
        ],
      });
      harness = await RouterTestingHarness.create();
      await harness.navigateByUrl(target);
      await settled();
      expect(url()).toBe('/account');
      expect(heading()).toBe('Use the ARQ staff app');
      expect(status()).toContain('You are on the staff of 404 Arena Koramangala');
      expect(body().querySelector('nav[aria-label="Main"]')).toBeNull();
      expect(field('Arena name')).toBeUndefined();
    });
  }

  it('a login whose access was turned off is told so, never offered Create Arena', async () => {
    await start('/', true, false);
    arenas.memberships = staffOnly().map((m) => ({ ...m, active: false }));
    await harness.navigateByUrl('/account');
    await settled();
    expect(heading()).toBe('Your access is turned off');
    await harness.navigateByUrl('/create-arena');
    await settled();
    expect(url()).toBe('/account');
  });

  it('a failed membership read is never taken for "no arena": it says so and retries', async () => {
    auth = new SampleAuthApi(true);
    arenas = new SampleArenaApi(true);
    let fail = true;
    const real = arenas.myArenas.bind(arenas);
    arenas.myArenas = async () => {
      if (fail) throw new AppError('network', 'No connection. Check the internet and try again.');
      return real();
    };
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: auth },
        { provide: ArenaApi, useValue: arenas },
        { provide: UsersApi, useValue: new SampleUsersApi() },
      ],
    });
    harness = await RouterTestingHarness.create();
    await harness.navigateByUrl('/sales');
    await settled();
    expect(url()).toBe('/account');
    expect(heading()).toBe("We couldn't check your access");
    fail = false;
    await press('Try again');
    await settled();
    expect(url()).toBe('/overview');
  });

  it('a slow membership read: the guards wait (one read), then open the dashboard once', async () => {
    auth = new SampleAuthApi(true);
    arenas = new SampleArenaApi(true);
    const real = arenas.myArenas.bind(arenas);
    let reads = 0;
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    arenas.myArenas = async () => {
      reads++;
      await gate;
      return real();
    };
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: auth },
        { provide: ArenaApi, useValue: arenas },
        { provide: UsersApi, useValue: new SampleUsersApi() },
      ],
    });
    harness = await RouterTestingHarness.create();
    const navigation = harness.navigateByUrl('/stations');
    await new Promise((r) => setTimeout(r, 20));
    // Still deciding: nothing was sent to Create Arena while the read was in flight.
    expect(url()).not.toBe('/create-arena');
    release();
    await navigation;
    await settled();
    expect(url()).toBe('/stations');
    expect(reads).toBe(1);
  });

  it('signing in returns to the page that asked for it', async () => {
    await start('/sales?range=week', false, true);
    expect(url()).toBe('/sign-in?next=%2Fsales%3Frange%3Dweek');
    type('Email', 'arjun@404arena.in');
    type('Password', 'arena-pass-42');
    await press('Sign in');
    await settled();
    expect(url()).toBe('/sales?range=week');
  });

  it('a crafted ?next= never leaves the app', async () => {
    await start('/sign-in?next=%2F%2Fevil.example', false, true);
    type('Email', 'arjun@404arena.in');
    type('Password', 'arena-pass-42');
    await press('Sign in');
    await settled();
    expect(url()).toBe('/overview');
  });
});
