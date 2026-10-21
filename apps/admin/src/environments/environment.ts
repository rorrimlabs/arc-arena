/**
 * Development: the local Supabase stack (`supabase start` in the repo root).
 * Production builds use environment.production.ts (angular.json fileReplacements).
 */
export const environment = {
  /** Staging verification: points to arena-ops-staging Supabase project. */
  production: false,
  supabaseUrl: 'http://127.0.0.1:54431',
  /** Publishable key for arena-ops-staging */
  supabaseKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  /** Cloudflare Turnstile site key (public). Empty = no CAPTCHA. */
  turnstileSiteKey: '',
};
