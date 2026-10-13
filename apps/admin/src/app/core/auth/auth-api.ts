import { Service, inject } from '@angular/core';
import type { User } from '@supabase/supabase-js';
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
};

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
      return new AppError(
        'network',
        'Could not reach the server. Check the connection and try again',
      );
    }
    return new AppError(code, AUTH_MESSAGES[code] ?? e.message);
  }
  if (e instanceof TypeError) {
    return new AppError(
      'network',
      'Could not reach the server. Check the connection and try again',
    );
  }
  return new AppError('unknown', e instanceof Error ? e.message : String(e));
}

/**
 * Sign-in, owner sign-up (email + password, confirmed with the 6-digit code from the email) and
 * sign-out. The Supabase implementation is the default; tests provide a sample one.
 */
@Service({ factory: () => new SupabaseAuthApi() })
export abstract class AuthApi {
  /** The session restored from storage, if any. */
  abstract current(): Promise<Account | null>;
  /** Called on every sign-in, sign-out and token refresh. Returns an unsubscribe function. */
  abstract onChange(listener: (account: Account | null) => void): () => void;
  abstract signIn(email: string, password: string): Promise<void>;
  /** 'confirm' when the server e-mailed a code; 'signed-in' when it needs no confirmation. */
  abstract signUp(email: string, password: string): Promise<'confirm' | 'signed-in'>;
  abstract verifySignUp(email: string, code: string): Promise<void>;
  abstract resendCode(email: string): Promise<void>;
  /** Saves the owner's display name on their login (shown in the side nav). */
  abstract setName(name: string): Promise<void>;
  abstract signOut(): Promise<void>;
}

function toAccount(user: User | null | undefined): Account | null {
  if (!user) return null;
  const email = user.email ?? '';
  const name = typeof user.user_metadata?.['name'] === 'string' ? user.user_metadata['name'] : '';
  return { id: user.id, email, name: name || email };
}

class SupabaseAuthApi extends AuthApi {
  private readonly supabase = inject(Supabase);

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
    const { data, error } = await (await this.auth()).signUp({ email, password });
    if (error) throw toAppError(error);
    return data.session ? 'signed-in' : 'confirm';
  }

  async verifySignUp(email: string, code: string): Promise<void> {
    const { error } = await (await this.auth()).verifyOtp({ type: 'signup', email, token: code });
    if (error) throw toAppError(error);
  }

  async resendCode(email: string): Promise<void> {
    const { error } = await (await this.auth()).resend({ type: 'signup', email });
    if (error) throw toAppError(error);
  }

  async setName(name: string): Promise<void> {
    const { error } = await (await this.auth()).updateUser({ data: { name } });
    if (error) throw toAppError(error);
  }

  async signOut(): Promise<void> {
    // Offline sign-out still clears the local session.
    await (await this.auth()).signOut({ scope: 'local' });
  }
}
