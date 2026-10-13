import { Service } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../../environments/environment';

/**
 * The one Supabase client, created on first use. supabase-js is loaded lazily so it stays out
 * of the initial bundle. Only the publishable key is ever in the browser; every write goes
 * through the database's client API (sync_push, create_my_arena, …) or the staff-admin function.
 */
@Service()
export class Supabase {
  private created?: Promise<SupabaseClient>;

  /** True when this build has no project configured (production values left empty). */
  readonly misconfigured = !environment.supabaseUrl || !environment.supabaseKey;

  client(): Promise<SupabaseClient> {
    this.created ??= import('@supabase/supabase-js').then(({ createClient }) =>
      createClient(
        environment.supabaseUrl || 'http://invalid.local',
        environment.supabaseKey || 'missing',
        { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } },
      ),
    );
    return this.created;
  }
}
