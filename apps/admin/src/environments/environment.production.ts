/**
 * Production build settings (angular.json swaps this file in for environment.ts).
 *
 * Left empty on purpose: until both values are filled in, a production build shows a
 * "Setup needed" screen instead of the dashboard. To deploy, set:
 *
 *   supabaseUrl  the hosted project's URL, e.g. 'https://<project-ref>.supabase.co'
 *                (Project Settings → Data API). Must be https, not a local address.
 *   supabaseKey  the project's publishable key, 'sb_publishable_…' (Project Settings → API Keys),
 *                or its legacy anon key. Never the secret ('sb_secret_…') or service_role key:
 *                the build refuses them, and a secret key that was committed must be rotated.
 *
 * Then `npm run build`. The checks live in core/supabase/supabase.ts (configProblem).
 */
export const environment = {
  production: true,
  supabaseUrl: '',
  supabaseKey: '',
  /** Cloudflare Turnstile site key (public). Empty = no CAPTCHA (the local stack has none). */
  turnstileSiteKey: '',
};
