import {
  Account,
  AcceptedInvite,
  AppError,
  AuthApi,
  INVITE_ACCEPT_MESSAGES,
  passwordProblem,
} from './auth-api';
import { InviteeAuth, InviteeTokens } from './invitee-auth';

/** An invitation as the sample server holds it. */
export interface SampleInvite {
  readonly token: string;
  readonly email: string;
  readonly arenaId: string;
  readonly arenaName: string;
  readonly role: 'owner' | 'staff';
  state: 'open' | 'used' | 'revoked' | 'expired';
}

/**
 * Deterministic in-memory AuthApi for tests: one confirmed owner (arjun@404arena.in /
 * arena-pass-42), sign-ups need the code 123456. E-mailed links (invitations, password resets)
 * sign in with the access token registered in `linkTokens`; `invites` holds the invitations
 * accept_invite checks.
 */
export class SampleAuthApi extends AuthApi {
  static readonly CODE = '123456';
  account: Account | null;
  /** The sample server's logins (the invitee sign-in reads them too). */
  readonly logins = new Map<string, { password: string; confirmed: boolean; name: string }>([
    ['arjun@404arena.in', { password: 'arena-pass-42', confirmed: true, name: 'Arjun Mehra' }],
  ]);
  private listeners: ((a: Account | null) => void)[] = [];
  readonly calls: string[] = [];
  /** Access token from an e-mailed link → the address it signs in. */
  readonly linkTokens = new Map<string, string>();
  readonly invites = new Map<string, SampleInvite>();
  /** Called when an invitation is accepted (e.g. to add the membership it creates). */
  onAccept: (invite: SampleInvite) => void = () => undefined;
  /** The invitation page's own sign-in (InviteeAuth), on this sample server. */
  readonly invitee: SampleInviteeAuth = new SampleInviteeAuth(this);

  constructor(signedIn = true) {
    super();
    this.account = signedIn ? { id: 'u0', email: 'arjun@404arena.in', name: 'Arjun Mehra' } : null;
  }

  async current(): Promise<Account | null> {
    return this.account;
  }

  onChange(listener: (account: Account | null) => void): () => void {
    this.listeners.push(listener);
    return () => (this.listeners = this.listeners.filter((l) => l !== listener));
  }

  async signIn(email: string, password: string): Promise<void> {
    this.calls.push(`signIn:${email}`);
    const login = this.logins.get(email);
    if (!login || login.password !== password) {
      throw new AppError('invalid_credentials', 'Wrong email or password');
    }
    if (!login.confirmed) {
      throw new AppError('email_not_confirmed', 'Confirm your email first');
    }
    this.set({ id: `id-${email}`, email, name: login.name || email });
  }

  async signUp(email: string, password: string): Promise<'confirm' | 'signed-in'> {
    this.calls.push(`signUp:${email}`);
    if (!this.logins.has(email)) this.logins.set(email, { password, confirmed: false, name: '' });
    return 'confirm';
  }

  async verifySignUp(email: string, code: string): Promise<void> {
    this.calls.push(`verify:${email}:${code}`);
    const login = this.logins.get(email);
    if (!login || code !== SampleAuthApi.CODE) {
      throw new AppError('otp_expired', 'That code is wrong or has expired');
    }
    login.confirmed = true;
    this.set({ id: `id-${email}`, email, name: email });
  }

  async resendCode(email: string): Promise<void> {
    this.calls.push(`resend:${email}`);
  }

  async setName(name: string): Promise<void> {
    if (this.account) this.set({ ...this.account, name });
  }

  async signInFromLink(accessToken: string, refreshToken: string): Promise<Account> {
    this.calls.push(`link:${accessToken}`);
    const email = this.linkTokens.get(accessToken);
    if (!email || !refreshToken) {
      throw new AppError('session_expired', 'This sign-in has expired');
    }
    const login = this.logins.get(email) ?? { password: '', confirmed: true, name: '' };
    login.confirmed = true;
    this.logins.set(email, login);
    const account = { id: `id-${email}`, email, name: login.name || email };
    this.set(account);
    return account;
  }

  async setPassword(password: string): Promise<void> {
    this.calls.push('setPassword');
    if (!this.account) throw new AppError('session_expired', 'This sign-in has expired');
    if (passwordProblem(password)) throw new AppError('weak_password', 'The password is too weak');
    const login = this.logins.get(this.account.email);
    if (login) login.password = password;
  }

  /** Like the server: the same answer whether or not the address has a login. */
  async requestPasswordReset(email: string): Promise<void> {
    this.calls.push(`reset:${email}`);
  }

  /** accept_invite as `account`, with the server's checks (used by both sign-ins). */
  acceptAs(account: Account | null, inviteId: string, token: string): AcceptedInvite {
    const fail = (code: string) => new AppError(code, INVITE_ACCEPT_MESSAGES[code]);
    if (!account) throw fail('forbidden');
    const invite = this.invites.get(inviteId);
    if (!invite || invite.token !== token) throw fail('invite_invalid');
    if (invite.state === 'used') throw fail('invite_used');
    if (invite.state === 'revoked') throw fail('invite_revoked');
    if (invite.state === 'expired') throw fail('invite_expired');
    if (invite.email !== account.email) throw fail('invite_wrong_account');
    invite.state = 'used';
    this.onAccept(invite);
    return { arenaId: invite.arenaId, arenaName: invite.arenaName, role: invite.role };
  }

  async signOut(): Promise<void> {
    this.calls.push('signOut');
    this.set(null);
  }

  private set(account: Account | null): void {
    this.account = account;
    this.listeners.forEach((l) => l(account));
  }
}

/**
 * The invitation page's sign-in on the sample server: the same logins, links and invitations as
 * SampleAuthApi, but its own session — it never changes SampleAuthApi.account (the dashboard's
 * sign-in), as the real one never touches the browser's stored session. Calls are recorded in
 * the shared `calls`, under the same names.
 */
export class SampleInviteeAuth extends InviteeAuth {
  private signedIn: Account | null = null;
  /** Arenas (by id) where the invitee is owner level after joining (canManage). */
  readonly manages = new Set<string>();
  /** Set to make the next accept fail with this error (nothing is accepted). */
  failNext: AppError | null = null;

  constructor(private readonly server: SampleAuthApi) {
    super();
  }

  begin(): void {
    this.signedIn = null;
  }

  account(): Account | null {
    return this.signedIn;
  }

  async fromLink(accessToken: string, refreshToken: string): Promise<Account> {
    this.server.calls.push(`link:${accessToken}`);
    const email = this.server.linkTokens.get(accessToken);
    if (!email || !refreshToken) {
      throw new AppError('session_expired', 'This sign-in has expired');
    }
    const login = this.server.logins.get(email) ?? { password: '', confirmed: true, name: '' };
    login.confirmed = true;
    this.server.logins.set(email, login);
    this.signedIn = { id: `id-${email}`, email, name: login.name || email };
    return this.signedIn;
  }

  async signIn(email: string, password: string): Promise<Account> {
    this.server.calls.push(`signIn:${email}`);
    const login = this.server.logins.get(email);
    if (!login || login.password !== password) {
      throw new AppError('invalid_credentials', 'Wrong email or password');
    }
    if (!login.confirmed) throw new AppError('email_not_confirmed', 'Confirm your email first');
    this.signedIn = { id: `id-${email}`, email, name: login.name || email };
    return this.signedIn;
  }

  async setPassword(password: string): Promise<void> {
    this.server.calls.push('setPassword');
    if (!this.signedIn) throw new AppError('session_expired', 'This sign-in has expired');
    if (passwordProblem(password)) throw new AppError('weak_password', 'The password is too weak');
    const login = this.server.logins.get(this.signedIn.email);
    if (login) login.password = password;
  }

  async accept(inviteId: string, token: string): Promise<AcceptedInvite> {
    this.server.calls.push(`accept:${inviteId}`);
    const failure = this.failNext;
    this.failNext = null;
    if (failure) throw failure;
    const joined = this.server.acceptAs(this.signedIn, inviteId, token);
    if (joined.role === 'owner') this.manages.add(joined.arenaId);
    return joined;
  }

  async canManage(arenaId: string): Promise<boolean> {
    return this.manages.has(arenaId);
  }

  tokens(): InviteeTokens | null {
    if (!this.signedIn) return null;
    const access = [...this.server.linkTokens].find(([, e]) => e === this.signedIn?.email)?.[0];
    return { accessToken: access ?? `at-${this.signedIn.email}`, refreshToken: 'rt-invitee' };
  }

  async end(): Promise<void> {
    if (this.signedIn) this.server.calls.push('invitee:end');
    this.signedIn = null;
  }
}
