import type { AuthError } from '@supabase/supabase-js';
import { USER_MESSAGES, emailFailure } from './users-api';

function authError(o: { name?: string; status?: number; code?: string }): AuthError {
  return { name: o.name ?? 'AuthApiError', status: o.status, code: o.code, message: 'x' } as AuthError;
}

describe('emailFailure', () => {
  it('a rate limit (429 or an over_*_rate_limit code) says to wait', () => {
    expect(emailFailure(authError({ status: 429 })).code).toBe('email_rate_limited');
    expect(emailFailure(authError({ code: 'over_email_send_rate_limit' })).message).toBe(
      USER_MESSAGES['email_rate_limited'],
    );
  });

  it('a server that refuses new logins says so', () => {
    expect(emailFailure(authError({ code: 'signup_disabled' })).code).toBe('signup_disabled');
    expect(emailFailure(authError({ code: 'otp_disabled' })).code).toBe('signup_disabled');
  });

  it('no answer from Auth is a network problem, not a refused e-mail', () => {
    expect(emailFailure(authError({ name: 'AuthRetryableFetchError' })).code).toBe('network');
  });

  it('anything else: the e-mail could not be sent', () => {
    const err = emailFailure(authError({ status: 500, code: 'unexpected_failure' }));
    expect(err.code).toBe('email_failed');
    expect(err.message).toBe(USER_MESSAGES['email_failed']);
  });
});
