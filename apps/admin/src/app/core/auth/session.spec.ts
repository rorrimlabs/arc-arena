import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { Account, AuthApi } from './auth-api';
import { SampleAuthApi } from './auth-api.sample';
import { LoginScope } from './login-scope';
import { Session } from './session';

/** A server sign-out that waits until released, as one does offline. */
class SlowSignOutApi extends SampleAuthApi {
  release: () => void = () => undefined;
  /** What the client reports while it still refreshes the old session first. */
  emit: (a: Account | null) => void = () => undefined;

  override onChange(listener: (account: Account | null) => void): () => void {
    this.emit = listener;
    return super.onChange(listener);
  }

  override async signOut(): Promise<void> {
    this.calls.push('signOut:start');
    await new Promise<void>((r) => (this.release = r));
    await super.signOut();
  }
}

describe('Session', () => {
  const arjun: Account = { id: 'u0', email: 'arjun@404arena.in', name: 'Arjun Mehra' };

  function setup() {
    const api = new SlowSignOutApi();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([{ path: '**', children: [] }]),
        { provide: AuthApi, useValue: api },
      ],
    });
    const ended: string[] = [];
    const session = TestBed.inject(Session);
    TestBed.inject(LoginScope).onEnd(() => ended.push(session.user()?.id ?? 'none'));
    return { api, session, ended };
  }

  it('sign-out drops the login at once, before the server has answered', async () => {
    const { api, session, ended } = setup();
    await session.ready;
    expect(session.user()?.id).toBe('u0');

    const out = session.signOut();
    expect(session.user()).toBeNull();
    // The stores were cleared while the old login was still the current one.
    expect(ended).toEqual(['u0']);

    // The client refreshing the old session meanwhile does not sign it back in.
    api.emit(arjun);
    expect(session.user()).toBeNull();

    api.release();
    await out;
    expect(api.calls).toEqual(['signOut:start', 'signOut']);
    expect(session.user()).toBeNull();
    expect(ended).toEqual(['u0']);
  });

  it('the next sign-in waits for the previous session to end on the server', async () => {
    const { api, session } = setup();
    await session.ready;
    const out = session.signOut();
    const signIn = session.signIn('arjun@404arena.in', 'arena-pass-42');
    await new Promise((r) => setTimeout(r));
    expect(api.calls).toEqual(['signOut:start']);

    api.release();
    await Promise.all([out, signIn]);
    expect(api.calls).toEqual(['signOut:start', 'signOut', 'signIn:arjun@404arena.in']);
    expect(session.user()?.email).toBe('arjun@404arena.in');
  });

  it('a token refresh (same login) clears nothing; another login clears once', async () => {
    const { api, session, ended } = setup();
    await session.ready;
    api.emit({ ...arjun, name: 'Arjun M.' });
    expect(ended).toEqual([]);
    expect(session.user()?.name).toBe('Arjun M.');

    api.emit({ id: 'u9', email: 'farah@404arena.in', name: 'Farah Khan' });
    expect(ended).toEqual(['u0']);
    expect(session.user()?.id).toBe('u9');
  });
});
