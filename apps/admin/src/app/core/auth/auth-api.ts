import { DOCUMENT, Service, inject } from '@angular/core';
import type { PostgrestError, User } from '@supabase/supabase-js';
import { Supabase } from '../supabase/supabase';

/** The signed-in person, as the dashboard shows them. */
export interface Account {
  readonly id: string;
  readonly email: string;
  readonly name: string;
}

/** A refusal with a stable code and words that say what to do. */
export class AppError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/** What accept_invite returns: the arena joined, and as what. */
export interface AcceptedInvite {
  readonly arenaId: string;
  readonly arenaName: string;
  readonly role: 'owner' | 'staff';
}

/** Shared with the server (minimum_password_length = 10, password_requirements = letters_digits). */
export const MIN_PASSWORD = 10;

export function passwordProblem(password: string): string | null {
  if (password.length < MIN_PASSWORD) return `Use at least ${MIN_PASSWORD} characters`;
  if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) return 'Use both letters and digits';
  return null;
}

const AUTH_MESSAGES: Readonly<Record<string, string>> = {
  invalid_credentials: 'Wrong email or password',
  email_not_confirmed: 'Confirm your email first: enter the code we sent you',
  user_already_exists: 'That email already has an account. Sign in instead',
  email_exists: 'That email already has an account. Sign in instead',
  weak_password: `The password is too weak. Use at least ${MIN_PASSWORD} characters with letters and digits`,
  email_address_invalid: 'Enter a valid email',
  validation_failed: 'Enter a valid email',
  otp_expired: 'That code is wrong or has expired. Check the latest email, or resend the code',
  over_email_send_rate_limit: 'Too many emails sent. Wait a few minutes, then try again',
  over_request_rate_limit: 'Too many attempts. Wait a few minutes, then try again',
  signup_disabled: 'This server does not accept new accounts',
  same_password: 'That is already your password. Choose a new one',
  session_expired: 'This sign-in has expired. Open the link from the e-mail again',
  refresh_token_not_found: 'This sign-in has expired. Open the link from the e-mail again',
};

const NETWORK_MESSAGE = 'Could not reach the server. Check the connection and try again';

/** supabase-js auth errors (checked by shape: the library is loaded lazily). */
function isAuthError(
  e: unknown,
): e is { code?: string; status?: number; name: string; message: string } {
  return typeof e === 'object' && e !== null && '__isAuthError' in e;
}

/** Turns any auth failure into an AppError the screens can show as-is. */
export function toAppError(e: unknown): AppError {
  if (e instanceof AppError) return e;
  if (isAuthError(e)) {
    const code = e.code ?? (e.status === 0 ? 'network' : 'auth_error');
    if (code === 'network' || e.name === 'AuthRetryableFetchError') {
      return new AppError('network', NETWORK_MESSAGE);
    }
    return new AppError(code, AUTH_MESSAGES[code] ?? e.message);
  }
  if (e instanceof TypeError) {
    return new AppError('network', NETWORK_MESSAGE);
  }
  return new AppError('unknown', e instanceof Error ? e.message : String(e));
}

/**
 * accept_invite refusals (PostgREST: the code is the message, `hint` is human text). The wrong
 * account is worded by the page, which knows who is signed in.
 */
export const INVITE_ACCEPT_MESSAGES: Readonly<Record<string, string>> = {
  invite_invalid:
    'This invitation link is not valid. Open the whole link from the e-mail, or ask for a new invitation.',
  invite_used:
    'This invitation was already accepted. Sign in with your e-mail and password instead.',
  invite_revoked:
    'This invitation was withdrawn. Ask the arena for a new one if you still need access.',
  invite_expired: 'This invitation has expired. Ask for a new invitation.',
  email_not_confirmed:
    'Your e-mail address is not confirmed yet. Open the link from the invitation e-mail again.',
  owner_profile: 'You are already an owner of this arena. Open the dashboard instead.',
  invite_wrong_account:
    'You are signed in with a different e-mail address than the invitation was sent to.',
  forbidden: 'Sign in first, then accept the invitation.',
};

export function acceptError(e: PostgrestError | Error): AppError {
  if (e instanceof TypeError || /fetch/i.test(e.message)) {
    return new AppError('network', NETWORK_MESSAGE);
  }
  const forbidden = 'code' in e && e.code === '42501';
  const code = /^[a-z_]+$/.test(e.message) ? e.message : forbidden ? 'forbidden' : 'unknown';
  return new AppError(
    code,
    INVITE_ACCEPT_MESSAGES[code] ?? 'Could not accept the invitation. Try again.',
  );
}

/**
 * Sign-in, owner sign-up (email + password, confirmed with the link in the email),
 * accepting an e-mailed invitation, resetting a forgotten password, and sign-out. The Supabase
 * implementation is the default; tests provide a sample one.
 */
@Service({ factory: () => new SupabaseAuthApi() })
export abstract class AuthApi {
  /** The session restored from storage, if any. */
  abstract current(): Promise<Account | null>;
  /** Called on every sign-in, sign-out and token refresh. Returns an unsubscribe function. */
  abstract onChange(listener: (account: Account | null) => void): () => void;
  abstract signIn(email: string, password: string): Promise<void>;
  /**
   * 'confirm' when the server e-mailed a confirmation link (it opens the dashboard's /register
   * page, signed in); 'signed-in' when it needs no confirmation.
   */
  abstract signUp(email: string, password: string): Promise<'confirm' | 'signed-in'>;
  abstract resendConfirmation(email: string): Promise<void>;
  /** Saves the owner's display name on their login (shown in the side nav). */
  abstract setName(name: string): Promise<void>;
  /**
   * Signs in with the tokens Supabase Auth put in an e-mailed link's fragment (the client does
   * not read URLs itself: detectSessionInUrl is off).
   */
  abstract signInFromLink(accessToken: string, refreshToken: string): Promise<Account>;
  /**
   * Sets the signed-in login's password (an invited person choosing their own, or a reset link's
   * login choosing a new one).
   */
  abstract setPassword(password: string): Promise<void>;
  /**
   * E-mails a link to choose a new password; it opens the dashboard's /reset-password page. The
   * server answers the same whether or not the address has a login.
   */
  abstract requestPasswordReset(email: string): Promise<void>;
  /** Ends this browser's session, on the server too when it can be reached. Never throws. */
  abstract signOut(): Promise<void>;
}

export function toAccount(user: User | null | undefined): Account | null {
  if (!user) return null;
  const email = user.email ?? '';
  const name = typeof user.user_metadata?.['name'] === 'string' ? user.user_metadata['name'] : '';
  return { id: user.id, email, name: name || email };
}

class SupabaseAuthApi extends AuthApi {
  private readonly supabase = inject(Supabase);
  private readonly document = inject(DOCUMENT);

  private async auth() {
    return (await this.supabase.client()).auth;
  }

  async current(): Promise<Account | null> {
    const { data } = await (await this.auth()).getSession();
    return toAccount(data.session?.user);
  }

  onChange(listener: (account: Account | null) => void): () => void {
    let unsubscribe = () => {};
    let stopped = false;
    void this.auth().then((auth) => {
      if (stopped) return;
      const { data } = auth.onAuthStateChange((_event, session) =>
        listener(toAccount(session?.user)),
      );
      unsubscribe = () => data.subscription.unsubscribe();
    });
    return () => {
      stopped = true;
      unsubscribe();
    };
  }

  async signIn(email: string, password: string): Promise<void> {
    const { error } = await (await this.auth()).signInWithPassword({ email, password });
    if (error) throw toAppError(error);
  }

  async signUp(email: string, password: string): Promise<'confirm' | 'signed-in'> {
    const { data, error } = await (
      await this.auth()
    ).signUp({
      email,
      password,
      // `signup: 'owner'` picks the owner wording in templates/confirmation.html (an invited new
      // address gets the same template without it).
      options: { emailRedirectTo: this.confirmUrl(), data: { signup: 'owner' } },
    });
    if (error) throw toAppError(error);
    return data.session ? 'signed-in' : 'confirm';
  }

  async resendConfirmation(email: string): Promise<void> {
    const { error } = await (
      await this.auth()
    ).resend({ type: 'signup', email, options: { emailRedirectTo: this.confirmUrl() } });
    if (error) throw toAppError(error);
  }

  /** The sign-up confirmation link opens /register on the dashboard's own address. */
  private confirmUrl(): string {
    return new URL('/register', this.document.location.origin).href;
  }

  async setName(name: string): Promise<void> {
    const { error } = await (await this.auth()).updateUser({ data: { name } });
    if (error) throw toAppError(error);
  }

  async signInFromLink(accessToken: string, refreshToken: string): Promise<Account> {
    const { data, error } = await (
      await this.auth()
    ).setSession({ access_token: accessToken, refresh_token: refreshToken });
    if (error) throw toAppError(error);
    const account = toAccount(data.user ?? data.session?.user);
    if (!account) throw new AppError('auth_error', 'Could not sign you in from this link');
    return account;
  }

  async setPassword(password: string): Promise<void> {
    const { error } = await (await this.auth()).updateUser({ password });
    if (error) throw toAppError(error);
  }

  async requestPasswordReset(email: string): Promise<void> {
    const { error } = await (
      await this.auth()
    ).resetPasswordForEmail(email, {
      redirectTo: new URL('/reset-password', this.document.location.origin).href,
    });
    if (error) throw toAppError(error);
  }

  async signOut(): Promise<void> {
    // Scope 'local' ends this browser's session on the server as well (POST /logout?scope=local
    // deletes the session, so its refresh token stops working at once). 'global' would also end
    // the login's other sessions, such as the counter tablet's floor app mid-shift. An access
    // token already issued lasts until it expires (jwt_expiry), as any JWT does.
    let failed: boolean;
    try {
      failed = (await (await this.auth()).signOut({ scope: 'local' })).error !== null;
    } catch {
      failed = true;
    }
    // supabase-js keeps the stored session when it cannot refresh an expired access token first
    // (offline), and the next visit would restore it: forget it here anyway.
    if (failed) this.supabase.forgetStoredSession();
  }
}
