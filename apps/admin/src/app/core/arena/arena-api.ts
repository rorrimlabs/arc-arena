import { Service, inject } from '@angular/core';
import type { PostgrestError } from '@supabase/supabase-js';
import { AppError } from '../auth/auth-api';
import { Supabase } from '../supabase/supabase';

/** One staff_profiles row of the signed-in login, as my_arenas() reports it. */
export interface Membership {
  readonly arenaId: string;
  readonly arenaName: string;
  /** This person's name in that arena. */
  readonly name: string;
  readonly role: 'owner' | 'staff';
  readonly perms: readonly string[];
  readonly active: boolean;
}

/** Owner level, as the server decides it (app_is_owner): the owner, or money / reports. */
export function isOwnerLevel(m: Membership): boolean {
  return (
    m.active && (m.role === 'owner' || m.perms.includes('money') || m.perms.includes('reports'))
  );
}

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

/** The signed-in login's arenas, and creating its own (create_my_arena: one per login). */
@Service({ factory: () => new SupabaseArenaApi() })
export abstract class ArenaApi {
  abstract myArenas(): Promise<Membership[]>;
  /** Creates the arena with the starter catalog and makes the caller its owner. */
  abstract createArena(arenaName: string, ownerName: string): Promise<string>;
}

class SupabaseArenaApi extends ArenaApi {
  private readonly supabase = inject(Supabase);

  async myArenas(): Promise<Membership[]> {
    const { data, error } = await (await this.supabase.client()).rpc('my_arenas');
    if (error) throw dbError(error);
    return (data as Record<string, unknown>[]).map((r) => ({
      arenaId: String(r['arena_id']),
      arenaName: String(r['arena_name']),
      name: String(r['name']),
      role: r['role'] === 'owner' ? 'owner' : 'staff',
      perms: (r['perms'] as string[] | null) ?? [],
      active: r['active'] === true,
    }));
  }

  async createArena(arenaName: string, ownerName: string): Promise<string> {
    const { data, error } = await (
      await this.supabase.client()
    ).rpc('create_my_arena', {
      p_arena_name: arenaName,
      p_owner_name: ownerName,
    });
    if (error) throw dbError(error);
    return String(data);
  }
}
