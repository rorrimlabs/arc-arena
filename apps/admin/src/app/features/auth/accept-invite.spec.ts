import { PlatformLocation } from '@angular/common';
import { TestBed } from '@angular/core/testing';
import { MATERIAL_ANIMATIONS } from '@angular/material/core';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { ArenaApi } from '../../core/arena/arena-api';
import { SampleArenaApi } from '../../core/arena/arena-api.sample';
import { AppError, AuthApi } from '../../core/auth/auth-api';
import { InviteeAuth } from '../../core/auth/invitee-auth';
import { SampleAuthApi, SampleInvite } from '../../core/auth/auth-api.sample';
import { LOCAL_SERVER, LocalServer } from '../../core/supabase/local-server';
import { UsersApi } from '../users/data/users-api';
import { SampleUsersApi } from '../users/data/users-api.sample';

const INVITE = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
const TOKEN = '9f'.repeat(32);
const LINK = `/accept-invite?invite=${INVITE}&token=${TOKEN}`;
/** What Supabase Auth appends for a new login (invite) or an existing one (magic link). */
const session = (type: 'invite' | 'magiclink', access = 'at-farah') =>
  `#access_token=${access}&expires_at=1792000000&expires_in=3600&refresh_token=rt-1&token_type=bearer&type=${type}`;

describe('Accept invitation', () => {
  let harness: RouterTestingHarness;
  let auth: SampleAuthApi;
  let arenas: SampleArenaApi;
  let invite: SampleInvite;

  async function start(
    url: string,
    o: { signedIn?: boolean; role?: 'owner' | 'staff'; local?: LocalServer } = {},
  ) {
    auth = new SampleAuthApi(o.signedIn ?? false);
    arenas = new SampleArenaApi(false);
    invite = {
      token: TOKEN,
      email: 'farah@404arena.in',
      arenaId: 'a1',
      arenaName: '404 Arena Koramangala',
      role: o.role ?? 'staff',
      state: 'open',
    };
    auth.invites.set(INVITE, invite);
    auth.linkTokens.set('at-farah', 'farah@404arena.in');
    // accept_invite creates the membership the dashboard then reads (my_arenas).
    auth.onAccept = (i) =>
      arenas.memberships.push({
        arenaId: i.arenaId,
        arenaName: i.arenaName,
        name: 'Farah Khan',
        role: i.role,
        perms: i.role === 'owner' ? ['settings', 'money', 'reports'] : ['start', 'bill'],
        active: true,
      });
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: auth },
        { provide: InviteeAuth, useValue: auth.invitee },
        { provide: ArenaApi, useValue: arenas },
        { provide: UsersApi, useValue: new SampleUsersApi() },
        { provide: MATERIAL_ANIMATIONS, useValue: { animationsDisabled: true } },
        { provide: LOCAL_SERVER, useValue: o.local ?? null },
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
  /** The address bar (Angular's platform location: the browser's, faked in tests). */
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
    const button = [...body().querySelectorAll('button')].find((b) =>
      b.textContent?.includes(label),
    ) as HTMLButtonElement;
    button.click();
    await settle();
  }

  it('an owner signed in on this browser stays themselves while someone accepts here', async () => {
    // The owner's dashboard and the invitee's link share one browser (one stored session).
    await start(LINK + session('invite'), { signedIn: true });
    arenas.memberships.push({
      arenaId: 'a1',
      arenaName: '404 Arena Koramangala',
      name: 'Arjun Mehra',
      role: 'owner',
      perms: ['settings', 'money', 'reports'],
      active: true,
    });
    type('Password', 'floor-pass-42');
    type('Type it again', 'floor-pass-42');
    await press('Save password and join');
    // The dashboard's login was never replaced by the invitee's.
    expect(auth.account?.email).toBe('arjun@404arena.in');
    expect(heading()).toBe('You have joined 404 Arena Koramangala');
    // Done ends only the invitee's sign-in; the owner is back on their dashboard.
    await press('Done');
    expect(auth.account?.email).toBe('arjun@404arena.in');
    expect(TestBed.inject(Router).url).toBe('/overview');
  });

  it('takes the token out of the address straight away', async () => {
    await start(LINK + session('invite'));
    expect(address()).toBe('/accept-invite');
    expect(TestBed.inject(PlatformLocation).href).not.toContain(TOKEN);
    expect(TestBed.inject(PlatformLocation).href).not.toContain('at-farah');
  });

  it('a new login chooses its password, then joins as staff', async () => {
    await start(LINK + session('invite'));
    expect(heading()).toBe('Choose your password');
    expect(body().textContent).toContain('Signed in as farah@404arena.in');

    type('Password', 'short');
    type('Type it again', 'short');
    await press('Save password and join');
    expect(alert()).toBe('Use at least 10 characters');

    type('Password', 'floor-pass-42');
    type('Type it again', 'floor-pass-43');
    await press('Save password and join');
    expect(alert()).toBe('The two passwords are different');
    expect(auth.calls).not.toContain(`accept:${INVITE}`);

    type('Type it again', 'floor-pass-42');
    await press('Save password and join');
    // The password is set before the invitation is accepted.
    expect(auth.calls).toEqual(['link:at-farah', 'setPassword', `accept:${INVITE}`]);
    expect(heading()).toBe('You have joined 404 Arena Koramangala');
    expect(body().textContent).toContain(
      'Sign in on the staff app with farah@404arena.in and your password.',
    );
    expect(body().textContent).not.toContain('Open dashboard');

    await press('Done');
    expect(auth.account).toBeNull();
    expect(TestBed.inject(Router).url).toBe('/sign-in');
  });

  it('on the local test server, choosing a password and joining both say the login is only there', async () => {
    await start(LINK + session('invite'), {
      local: { address: '127.0.0.1:54431', mailUrl: null },
    });
    const note = () => body().querySelector('app-local-server-note [role="note"]')?.textContent;
    expect(heading()).toBe('Choose your password');
    expect(note()).toContain('Local test server (127.0.0.1:54431).');
    expect(note()).toContain('exist only on this computer');
    expect(note()).not.toContain('local mailbox');

    type('Password', 'floor-pass-42');
    type('Type it again', 'floor-pass-42');
    await press('Save password and join');
    expect(heading()).toBe('You have joined 404 Arena Koramangala');
    expect(note()).toContain('dart_define.prod.json');
  });

  it('on a hosted project the invitation page has no local server note', async () => {
    await start(LINK + session('invite'));
    expect(body().querySelector('app-local-server-note [role="note"]')).toBeNull();
  });

  it('an existing login opens the magic link and accepts, password optional', async () => {
    await start(LINK + session('magiclink'), { role: 'owner' });
    expect(heading()).toBe('Accept your invitation');
    expect(body().textContent).toContain('Signed in as farah@404arena.in');

    await press('Accept invitation');
    expect(auth.calls).toEqual(['link:at-farah', `accept:${INVITE}`]);
    expect(heading()).toBe('Welcome to 404 Arena Koramangala');

    await press('Open dashboard');
    expect(TestBed.inject(Router).url).toBe('/overview');
  });

  it('a new password chosen while confirming is saved before accepting', async () => {
    await start(LINK + session('magiclink'));
    type('New password (optional)', 'new-pass-777');
    await press('Accept invitation');
    expect(alert()).toBe('The two passwords are different');
    type('Type it again', 'new-pass-777');
    await press('Accept invitation');
    expect(auth.calls).toEqual(['link:at-farah', 'setPassword', `accept:${INVITE}`]);
    expect(heading()).toBe('You have joined 404 Arena Koramangala');
  });

  it('an owner signed in on this browser is never taken for the invitee', async () => {
    // No link session: the invitee signs in on the page, whoever the dashboard is signed in as.
    await start(LINK, { signedIn: true });
    expect(heading()).toBe('Sign in to accept');
    expect(auth.calls).not.toContain(`accept:${INVITE}`);
  });

  it('signing in with a different login than invited: says who, nothing changes', async () => {
    await start(LINK, { signedIn: true });
    type('Email', 'arjun@404arena.in');
    type('Password', 'arena-pass-42');
    await press('Sign in and accept');
    expect(heading()).toBe('Could not accept the invitation');
    expect(alert()).toBe(
      'You are signed in as arjun@404arena.in, but this invitation was sent to a different e-mail address. Sign out, then open the link from the e-mail again.',
    );
    expect(invite.state).toBe('open');

    await press('Sign in as someone else');
    expect(heading()).toBe('Sign in to accept');
    // The dashboard's own login was not signed out by any of this.
    expect(auth.account?.email).toBe('arjun@404arena.in');
  });

  it('the account was made but accepting failed: try again joins once, password kept', async () => {
    await start(LINK + session('invite'));
    type('Password', 'floor-pass-42');
    type('Type it again', 'floor-pass-42');
    auth.invitee.failNext = new AppError(
      'network',
      'No connection. Check the internet and try again.',
    );
    await press('Save password and join');
    expect(heading()).toBe('Could not accept the invitation');
    expect(invite.state).toBe('open');
    await press('Try again');
    expect(heading()).toBe('You have joined 404 Arena Koramangala');
    // The password was saved once; the retry only accepted.
    expect(auth.calls.filter((c) => c === 'setPassword')).toHaveLength(1);
    expect(arenas.memberships.filter((m) => m.name === 'Farah Khan')).toHaveLength(1);
  });

  it('a co-owner takes over this browser’s dashboard only when they choose to', async () => {
    await start(LINK + session('magiclink'), { signedIn: true, role: 'owner' });
    await press('Accept invitation');
    expect(heading()).toBe('Welcome to 404 Arena Koramangala');
    expect(body().textContent).toContain('arjun@404arena.in is signed in to the dashboard');
    expect(auth.account?.email).toBe('arjun@404arena.in');
    await press('Open dashboard');
    expect(auth.account?.email).toBe('farah@404arena.in');
    expect(TestBed.inject(Router).url).toBe('/overview');
  });

  it('without a link session, an existing login signs in to accept', async () => {
    await start(LINK);
    expect(heading()).toBe('Sign in to accept');
    // This invitation went to the address that already has a login.
    auth.invites.set(INVITE, { ...invite, email: 'arjun@404arena.in' });

    type('Email', 'arjun@404arena.in');
    type('Password', 'wrong-pass-1');
    await press('Sign in and accept');
    expect(alert()).toBe('Wrong email or password');

    type('Password', 'arena-pass-42');
    await press('Sign in and accept');
    expect(auth.calls).toEqual([
      'signIn:arjun@404arena.in',
      'signIn:arjun@404arena.in',
      `accept:${INVITE}`,
    ]);
    expect(heading()).toBe('You have joined 404 Arena Koramangala');
  });

  for (const [state, message] of [
    ['expired', 'This invitation has expired. Ask for a new invitation.'],
    [
      'used',
      'This invitation was already accepted. Sign in with your e-mail and password instead.',
    ],
    [
      'revoked',
      'This invitation was withdrawn. Ask the arena for a new one if you still need access.',
    ],
  ] as const) {
    it(`an invitation that was ${state} is explained`, async () => {
      await start(LINK + session('magiclink'));
      invite.state = state;
      await press('Accept invitation');
      expect(heading()).toBe('Could not accept the invitation');
      expect(alert()).toBe(message);
    });
  }

  it('a token that does not match is invalid', async () => {
    await start(`/accept-invite?invite=${INVITE}&token=${'0a'.repeat(32)}` + session('magiclink'));
    await press('Accept invitation');
    expect(alert()).toBe(
      'This invitation link is not valid. Open the whole link from the e-mail, or ask for a new invitation.',
    );
  });

  it('a link without its token is incomplete and asks nothing of the server', async () => {
    await start(`/accept-invite?invite=${INVITE}` + session('invite'));
    expect(heading()).toBe('Invitation link incomplete');
    expect(alert()).toContain('This invitation link is incomplete.');
    expect(auth.calls).toEqual([]);
    expect(address()).toBe('/accept-invite');
  });

  it('an expired e-mail link says to ask for a new invitation', async () => {
    await start(
      LINK +
        '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
    );
    expect(alert()).toBe('This link has expired. Ask for a new invitation.');
    expect(auth.calls).toEqual([]);
    expect(address()).toBe('/accept-invite');
    // Someone who already chose a password can still accept by signing in.
    await press('Sign in to accept');
    expect(heading()).toBe('Sign in to accept');
  });
});
