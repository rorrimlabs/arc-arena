import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/arena/arena-api';
import { AppError } from '../../../core/auth/auth-api';
import { Supabase } from '../../../core/supabase/supabase';
import { ArenaUser, NewUser, UserChange } from './user.models';

/**
 * The arena's users (owners and staff): read through arena_staff(), new logins through the
 * staff-admin Edge Function (it holds the service-role key; the browser never does), and
 * changes as a `staff.update` op through sync_push — the same path, permission checks and
 * history as the floor app. Tests provide SampleUsersApi.
 */
@Service({ factory: () => new SupabaseUsersApi() })
export abstract class UsersApi {
  abstract list(arenaId: string): Promise<ArenaUser[]>;
  /** Creates the login (or links an existing one). `created` is false for an existing login. */
  abstract create(arenaId: string, user: NewUser): Promise<{ userId: string; created: boolean }>;
  abstract update(arenaId: string, userId: string, change: UserChange): Promise<void>;
}

const USER_MESSAGES: Readonly<Record<string, string>> = {
  owner_profile: 'That login is already an owner of this arena',
  last_settings_holder: 'Someone must keep the Settings permission',
  invalid_permission: 'Unknown permission',
  invalid_role: 'Choose Staff or Owner',
  not_found: 'That person is no longer on the list. Refresh',
  forbidden: 'Only an owner can do that',
  unauthorized: 'Your session has expired. Sign in again',
  email_exists: 'Someone already uses that email',
};

class SupabaseUsersApi extends UsersApi {
  private readonly supabase = inject(Supabase);

  async list(arenaId: string): Promise<ArenaUser[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('arena_staff', { p_arena: arenaId });
    if (error) throw dbError(error);
    return (data as Record<string, unknown>[]).map((r) => ({
      userId: String(r['user_id']),
      name: String(r['name']),
      email: String(r['email'] ?? ''),
      role: r['role'] === 'owner' ? 'owner' : 'staff',
      perms: (r['perms'] as string[] | null) ?? [],
      active: r['active'] === true,
      invited: r['invited'] === true,
      bills30d: Number(r['bills_30d'] ?? 0),
      takings30dPaise: Number(r['takings_30d_paise'] ?? 0),
      refunds30dPaise: Number(r['refunds_30d_paise'] ?? 0),
    }));
  }

  async create(arenaId: string, user: NewUser): Promise<{ userId: string; created: boolean }> {
    const client = await this.supabase.client();
    const { data, error } = await client.functions.invoke('staff-admin', {
      body: {
        arena_id: arenaId,
        email: user.email,
        name: user.name,
        password: user.password,
        role: user.role,
        perms: user.perms,
      },
    });
    if (error) {
      if (error.name === 'FunctionsHttpError') {
        const body = (await (error.context as Response).json().catch(() => ({}))) as {
          error?: string;
          message?: string;
        };
        const code = body.error ?? 'create_failed';
        throw new AppError(code, USER_MESSAGES[code] ?? body.message ?? 'Could not add them');
      }
      throw new AppError(
        'network',
        'Could not reach the server. Check the connection and try again',
      );
    }
    const out = data as { user_id: string; created: boolean };
    return { userId: out.user_id, created: out.created };
  }

  async update(arenaId: string, userId: string, change: UserChange): Promise<void> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('sync_push', {
      p_arena: arenaId,
      p_ops: [
        {
          op_id: crypto.randomUUID(),
          kind: 'staff.update',
          payload: {
            user_id: userId,
            name: change.name,
            perms: change.perms,
            active: change.active,
          },
        },
      ],
      p_device: 'admin-web',
    });
    if (error) throw dbError(error);
    const result = (data as { results: { status: string; error?: string }[] }).results[0];
    if (result?.status !== 'applied') {
      const code = result?.error ?? 'rejected';
      throw new AppError(code, USER_MESSAGES[code] ?? code);
    }
  }
}
