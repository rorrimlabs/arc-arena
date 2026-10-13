import { Service, inject } from '@angular/core';
import { Supabase } from '../supabase/supabase';
import { pushOps } from '../sync/push-ops';

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

import { dbError } from '../supabase/db-error';

// Kept here too: the data services import it from this file.
export { dbError };

/** The arena's own details (arenas row): shown on bills and the floor app. */
export interface ArenaDetails {
  readonly name: string;
  /** Locality, e.g. Koramangala; empty when not set. */
  readonly area: string;
  readonly phone: string;
}

/** Refusals of arena.update, worded for the Settings screen. */
export const ARENA_MESSAGES: Readonly<Record<string, string>> = {
  invalid_name: 'Names must be 1 to 80 characters',
  invalid_area: 'Use up to 80 characters for the area',
  invalid_phone: 'Use 6 to 20 digits, spaces, +, ( ) or - for the phone',
  forbidden: 'You need the Settings permission for that',
};

/**
 * The signed-in login's arenas, creating its own (create_my_arena: one per login), and the
 * current arena's details: read from the arenas table (RLS), written as an arena.update op
 * through sync_push.
 */
@Service({ factory: () => new SupabaseArenaApi() })
export abstract class ArenaApi {
  abstract myArenas(): Promise<Membership[]>;
  /** Creates the arena with the starter catalog and makes the caller its owner. */
  abstract createArena(arenaName: string, ownerName: string): Promise<string>;
  abstract details(arenaId: string): Promise<ArenaDetails>;
  abstract saveDetails(arenaId: string, details: ArenaDetails): Promise<void>;
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

  async details(arenaId: string): Promise<ArenaDetails> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('arenas')
      .select('name, area, phone')
      .eq('id', arenaId)
      .single();
    if (error) throw dbError(error);
    const row = data as { name: string; area: string | null; phone: string | null };
    return { name: row.name, area: row.area ?? '', phone: row.phone ?? '' };
  }

  async saveDetails(arenaId: string, details: ArenaDetails): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'arena.update', payload: { ...details } }],
      ARENA_MESSAGES,
    );
  }
}
