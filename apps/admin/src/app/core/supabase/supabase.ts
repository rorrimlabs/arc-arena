import { Service } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../../environments/environment';

/** What a build is configured with (environments/environment*.ts). */
export interface SupabaseConfig {
  readonly production: boolean;
  readonly supabaseUrl: string;
  readonly supabaseKey: string;
}

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '0.0.0.0', '::1', '[::1]']);

/** A Supabase stack on this computer or its local network, never a hosted project. */
export function isLocalHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return LOCAL_HOSTS.has(host) || host.endsWith('.local');
}

/**
 * Why this build cannot be used as configured, worded for whoever deploys it; null when it is
 * fine. Only a publishable key (`sb_publishable_…`) or a legacy JWT with role `anon` may reach a
 * browser; a production build must name a hosted project over https. The key itself is never
 * part of the message.
 */
export function configProblem(config: SupabaseConfig): string | null {
  const file = config.production
    ? 'environments/environment.production.ts'
    : 'environments/environment.ts';
  if (!config.supabaseUrl.trim() || !config.supabaseKey.trim()) {
    return `This build has no Supabase project set. Fill in supabaseUrl and supabaseKey in ${file}, then build again.`;
  }
  let url: URL;
  try {
    url = new URL(config.supabaseUrl);
  } catch {
    return `supabaseUrl in ${file} is not a valid web address.`;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    return `supabaseUrl in ${file} must start with https://.`;
  }
  if (config.production) {
    if (url.protocol !== 'https:') {
      return `A production build must reach Supabase over https. Fix supabaseUrl in ${file}.`;
    }
    const host = url.hostname.toLowerCase();
    if (isLocalHost(host)) {
      return `This production build points at a local Supabase stack (${host}). Set the hosted project's URL in ${file}.`;
    }
  }
  return keyProblem(config.supabaseKey.trim(), file);
}

function keyProblem(key: string, file: string): string | null {
  if (key.startsWith('sb_publishable_')) return null;
  if (key.startsWith('sb_secret_')) {
    return `supabaseKey in ${file} is a secret key, which must never reach a browser. Use the publishable key (sb_publishable_…) and rotate the secret key.`;
  }
  const role = jwtRole(key);
  if (role === 'anon') return null;
  if (role === 'service_role') {
    return `supabaseKey in ${file} is the service_role key, which must never reach a browser. Use the publishable (or anon) key and rotate the service_role key.`;
  }
  return `supabaseKey in ${file} is not a publishable key. Use the project's publishable key (sb_publishable_…) or its legacy anon key.`;
}

/** The `role` claim of a legacy JWT key, or null when the key is not a readable JWT. */
function jwtRole(key: string): string | null {
  const parts = key.split('.');
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload: unknown = JSON.parse(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)));
    const role = (payload as { role?: unknown } | null)?.role;
    return typeof role === 'string' ? role : null;
  } catch {
    return null;
  }
}

/** This build's configuration problem (null when usable); app.routes shows it instead of the app. */
export const CONFIG_PROBLEM = configProblem(environment);

/**
 * The one Supabase client, created on first use. supabase-js is loaded lazily so it stays out
 * of the initial bundle. Only the publishable key is ever in the browser; every write goes
 * through the database's client API (sync_push, create_my_arena, …) or the staff-admin function.
 */
@Service()
export class Supabase {
  private created?: Promise<SupabaseClient>;

  /** Why this build cannot connect (see configProblem); null when it is configured. */
  readonly configProblem = CONFIG_PROBLEM;
  /** True when this build cannot be used as configured (the setup screen is shown instead). */
  readonly misconfigured = this.configProblem !== null;

  client(): Promise<SupabaseClient> {
    // Never hand a missing, local or secret configuration to supabase-js.
    if (this.configProblem) return Promise.reject(new Error(this.configProblem));
    this.created ??= import('@supabase/supabase-js').then(({ createClient }) =>
      createClient(environment.supabaseUrl, environment.supabaseKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: false,
          storageKey: authStorageKey(environment.supabaseUrl),
        },
      }),
    );
    return this.created;
  }

  /**
   * A separate client whose sign-in lives only in this page's memory: never stored, never
   * refreshed, never shared with other tabs. The invitation page signs the invitee in here, so
   * accepting an invitation in a browser where an owner is signed in leaves the owner signed in
   * (the browser's stored session is the dashboard's, and every tab shares it).
   */
  async isolatedClient(): Promise<SupabaseClient> {
    if (this.configProblem) throw new Error(this.configProblem);
    const { createClient } = await import('@supabase/supabase-js');
    const memory = new Map<string, string>();
    return createClient(environment.supabaseUrl, environment.supabaseKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
        // Its own key and storage: nothing it does reaches the dashboard's stored session.
        storageKey: 'arenaos-invitee',
        storage: {
          getItem: (key) => memory.get(key) ?? null,
          setItem: (key, value) => void memory.set(key, value),
          removeItem: (key) => void memory.delete(key),
        },
      },
    });
  }

  /**
   * Removes the sign-in stored in this browser (localStorage), for a sign-out the server could
   * not be told about.
   */
  forgetStoredSession(): void {
    if (this.configProblem) return;
    const key = authStorageKey(environment.supabaseUrl);
    try {
      for (const suffix of ['', '-user', '-code-verifier']) localStorage.removeItem(key + suffix);
    } catch {
      // Storage blocked: nothing was stored either.
    }
  }
}

/** supabase-js's own default key, named here so sign-out can clear it (stored sign-ins stay). */
function authStorageKey(supabaseUrl: string): string {
  return `sb-${new URL(supabaseUrl).hostname.split('.')[0]}-auth-token`;
}
