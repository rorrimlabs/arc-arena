/**
 * Template for the staging build (`ng build --configuration staging`). Copy it to
 * environment.staging.ts (git-ignored) and fill in the dedicated staging project:
 *
 *   supabaseUrl  'https://<staging-project-ref>.supabase.co' (Project Settings → Data API).
 *                Never the production project, never a local address.
 *   supabaseKey  the staging project's publishable key, 'sb_publishable_…'. Never the secret
 *                ('sb_secret_…') or service_role key: everything here ships in the browser.
 */
export const environment = {
  production: false,
  supabaseUrl: '',
  supabaseKey: '',
  /** Cloudflare Turnstile site key (public). Empty = no CAPTCHA. */
  turnstileSiteKey: '',
};
