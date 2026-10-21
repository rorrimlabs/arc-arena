/**
 * Development: the local Supabase stack (`supabase start` in the repo root).
 * Production builds use environment.production.ts (angular.json fileReplacements).
 */
export const environment = {
  /** Staging verification: points to arena-ops-staging Supabase project. */
  production: false,
  supabaseUrl: 'https://sqznpjqktvsabjxvpzjh.supabase.co',
  /** Publishable key for arena-ops-staging */
  supabaseKey: 'sb_publishable_vo1KvcDlevRjN-yNychSFw_qSRa0pWG',
  /** Cloudflare Turnstile site key (public). Empty = no CAPTCHA. */
  turnstileSiteKey: '',
};
