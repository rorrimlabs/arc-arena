/**
 * Development: the local Supabase stack (`supabase start` in the repo root).
 * Production builds use environment.production.ts (angular.json fileReplacements).
 */
export const environment = {
  /** Production builds must use https and a hosted project (checked in core/supabase). */
  production: false,
  supabaseUrl: 'http://127.0.0.1:54431',
  /** Publishable key: safe in a browser — RLS and the client API decide what it can reach. */
  supabaseKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  /** Cloudflare Turnstile site key (public). Empty = no CAPTCHA (the local stack has none). */
  turnstileSiteKey: '',
};
