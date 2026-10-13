import { TestBed } from '@angular/core/testing';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../../app.routes';
import { ArenaApi } from '../../core/arena/arena-api';
import { SampleArenaApi } from '../../core/arena/arena-api.sample';
import { AuthApi } from '../../core/auth/auth-api';
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

  const alert = () => body().querySelector('[role="alert"]')?.textContent?.trim();

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

  it('register: password rules, then the code, then create the arena', async () => {
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

    type('Code', '000000');
    await press('Confirm');
    expect(alert()).toContain('wrong or has expired');

    await press('Resend code');
    expect(body().querySelector('[role="status"]')?.textContent).toContain('Sent a new code');

    type('Code', SampleAuthApi.CODE);
    await press('Confirm');
    expect(url()).toBe('/create-arena');
    expect(heading()).toBe('Create your arena');

    type('Arena name', 'Game Zone');
    type('Your name', 'Sam Rao');
    await press('Create arena');
    expect(url()).toBe('/users');
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

  it('a signed-in login without an arena goes to create one', async () => {
    await start('/users', true, false);
    expect(url()).toBe('/create-arena');
  });
});
