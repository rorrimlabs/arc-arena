import { Account, AppError, AuthApi } from './auth-api';

/**
 * Deterministic in-memory AuthApi for tests: one confirmed owner (arjun@404arena.in /
 * arena-pass-42), sign-ups need the code 123456.
 */
export class SampleAuthApi extends AuthApi {
  static readonly CODE = '123456';
  account: Account | null;
  private readonly logins = new Map<string, { password: string; confirmed: boolean; name: string }>(
    [['arjun@404arena.in', { password: 'arena-pass-42', confirmed: true, name: 'Arjun Mehra' }]],
  );
  private listeners: ((a: Account | null) => void)[] = [];
  readonly calls: string[] = [];

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

  async signOut(): Promise<void> {
    this.set(null);
  }

  private set(account: Account | null): void {
    this.account = account;
    this.listeners.forEach((l) => l(account));
  }
}
