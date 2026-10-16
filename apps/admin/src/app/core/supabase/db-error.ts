import type { PostgrestError } from '@supabase/supabase-js';
import { AppError } from '../auth/auth-api';

const DB_MESSAGES: Readonly<Record<string, string>> = {
  arena_limit: 'This login already owns an arena',
  account_not_confirmed: 'Confirm your email first',
  invalid_name: 'Names must be 1 to 80 characters',
  forbidden: 'You do not have access to that. Sign in again',
};

/** Database refusals raise their stable code as the message (`raise exception 'arena_limit'`). */
export function dbError(e: PostgrestError | Error): AppError {
  const code = e.message;
  if ('code' in e && e.code === '42501') return new AppError('forbidden', DB_MESSAGES['forbidden']);
  if (e instanceof TypeError || /fetch/i.test(code)) {
    return new AppError(
      'network',
      'Could not reach the server. Check the connection and try again',
    );
  }
  return new AppError(code, DB_MESSAGES[code] ?? code);
}
