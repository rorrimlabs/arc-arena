import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import {
  ACCESSORY_STATUSES,
  Accessory,
  AccessoryKind,
  AccessoryMove,
  AccessoryStatus,
} from './accessory.models';

/**
 * Station accessories and their kinds: read from the controllers, accessory_kinds and
 * controller_moves tables (RLS), written as controller.* / accessory_kind.* ops through sync_push
 * (the settings permission, as on the floor app). Tests provide SampleAccessoriesApi.
 */
@Service({ factory: () => new SupabaseAccessoriesApi() })
export abstract class AccessoriesApi {
  abstract accessories(arenaId: string): Promise<Accessory[]>;
  /** One accessory as the server holds it now (read right before an edit), or null. */
  abstract accessory(arenaId: string, id: string): Promise<Accessory | null>;
  /** controller.upsert: the whole row (a new accessory, or an edit built on a fresh read). */
  abstract save(arenaId: string, accessory: Accessory): Promise<void>;
  /** controller.set_status: status and note only. */
  abstract setStatus(
    arenaId: string,
    id: string,
    status: AccessoryStatus,
    notes: string | null,
  ): Promise<void>;
  /**
   * controller.move: `returnHome` brings a lent accessory back to its station; `permanent`
   * re-homes it to `toId` (it now belongs there).
   */
  abstract move(
    arenaId: string,
    id: string,
    kind: 'returnHome' | 'permanent',
    toId?: string,
  ): Promise<void>;
  /** The newest moves of one accessory (read when it is opened). */
  abstract moves(arenaId: string, id: string, limit: number): Promise<AccessoryMove[]>;
  abstract kinds(arenaId: string): Promise<AccessoryKind[]>;
  abstract saveKind(arenaId: string, kind: AccessoryKind): Promise<void>;
  /** Deletes a kind nothing uses, or retires one still on an accessory. */
  abstract removeKind(arenaId: string, id: string): Promise<'deleted' | 'retired'>;
}

export const ACCESSORY_MESSAGES: Readonly<Record<string, string>> = {
  not_found: 'That accessory is no longer there. Refresh',
  controller_in_use: 'A session is using it right now · try again after it ends',
  controller_missing: 'That accessory is no longer there. Refresh',
  resource_missing: 'That station is no longer there. Refresh',
  missing_reference: 'That station or kind is no longer there. Refresh',
  cross_arena_reference: 'That station is no longer there. Refresh',
  kind_retired: 'That kind is turned off · pick another',
  accessory_kind_busy: 'One of these is in use in a session · try again after it ends',
  invalid_name: 'Enter a name of up to 40 characters',
  duplicate: 'Another kind already has that name',
  retry: 'It was moved on the floor just now · try again',
};

export const ACCESSORY_COLUMNS =
  'id, label, kind_id, home_resource_id, current_resource_id, status, notes, loan_return_to, loan_session_ref';

export function accessoryOps(c: Accessory): SyncOp[] {
  return [
    {
      kind: 'controller.upsert',
      payload: {
        id: c.id,
        label: c.label,
        kind_id: c.kindId,
        home_resource_id: c.homeId,
        current_resource_id: c.currentId,
        status: c.status,
        notes: c.notes,
        loan_return_to: c.loanReturnTo,
        loan_session_ref: c.loanSessionRef,
      },
    },
  ];
}

export function statusOps(id: string, status: AccessoryStatus, notes: string | null): SyncOp[] {
  return [{ kind: 'controller.set_status', payload: { id, status, notes } }];
}

export function moveOps(id: string, kind: 'returnHome' | 'permanent', toId?: string): SyncOp[] {
  return [
    {
      kind: 'controller.move',
      payload: { controller_id: id, kind, to_resource_id: toId ?? null, move_id: crypto.randomUUID() },
    },
  ];
}

export function kindOps(k: AccessoryKind): SyncOp[] {
  return [
    {
      kind: 'accessory_kind.upsert',
      payload: {
        id: k.id,
        name: k.name,
        counts_as_controller: k.countsAsController,
        sort_order: k.sortOrder,
        active: k.active,
      },
    },
  ];
}

export function parseAccessory(r: Record<string, unknown>): Accessory {
  const status = String(r['status']) as AccessoryStatus;
  const str = (v: unknown) => (v == null ? null : String(v));
  return {
    id: String(r['id']),
    label: String(r['label']),
    kindId: str(r['kind_id']),
    homeId: String(r['home_resource_id']),
    currentId: String(r['current_resource_id']),
    // An unknown status is not usable, like the server's count of free pads.
    status: ACCESSORY_STATUSES.some((s) => s.value === status) ? status : 'unavailable',
    notes: str(r['notes']),
    loanReturnTo: str(r['loan_return_to']),
    loanSessionRef: str(r['loan_session_ref']),
  };
}

class SupabaseAccessoriesApi extends AccessoriesApi {
  private readonly supabase = inject(Supabase);

  async accessories(arenaId: string): Promise<Accessory[]> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('controllers')
      .select(ACCESSORY_COLUMNS)
      .eq('arena_id', arenaId)
      .order('label')
      .order('id');
    if (error) throw dbError(error);
    return ((data as Record<string, unknown>[] | null) ?? []).map(parseAccessory);
  }

  async accessory(arenaId: string, id: string): Promise<Accessory | null> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('controllers')
      .select(ACCESSORY_COLUMNS)
      .eq('arena_id', arenaId)
      .eq('id', id)
      .maybeSingle();
    if (error) throw dbError(error);
    return data ? parseAccessory(data as Record<string, unknown>) : null;
  }

  async save(arenaId: string, accessory: Accessory): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, accessoryOps(accessory), ACCESSORY_MESSAGES);
  }

  async setStatus(
    arenaId: string,
    id: string,
    status: AccessoryStatus,
    notes: string | null,
  ): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      statusOps(id, status, notes),
      ACCESSORY_MESSAGES,
    );
  }

  async move(
    arenaId: string,
    id: string,
    kind: 'returnHome' | 'permanent',
    toId?: string,
  ): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, moveOps(id, kind, toId), ACCESSORY_MESSAGES);
  }

  async moves(arenaId: string, id: string, limit: number): Promise<AccessoryMove[]> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('controller_moves')
      .select('id, from_resource_id, to_resource_id, kind, session_ref, moved_at')
      .eq('arena_id', arenaId)
      .eq('controller_id', id)
      .order('moved_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit);
    if (error) throw dbError(error);
    return ((data as Record<string, unknown>[] | null) ?? []).map((m) => ({
      id: String(m['id']),
      fromId: String(m['from_resource_id']),
      toId: String(m['to_resource_id']),
      kind: m['kind'] as AccessoryMove['kind'],
      sessionRef: m['session_ref'] == null ? null : String(m['session_ref']),
      at: String(m['moved_at']),
    }));
  }

  async kinds(arenaId: string): Promise<AccessoryKind[]> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('accessory_kinds')
      .select('id, name, counts_as_controller, sort_order, active')
      .eq('arena_id', arenaId)
      .order('sort_order')
      .order('name');
    if (error) throw dbError(error);
    return ((data as Record<string, unknown>[] | null) ?? []).map((k) => ({
      id: String(k['id']),
      name: String(k['name']),
      countsAsController: k['counts_as_controller'] === true,
      sortOrder: Number(k['sort_order'] ?? 0),
      active: k['active'] !== false,
    }));
  }

  async saveKind(arenaId: string, kind: AccessoryKind): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, kindOps(kind), ACCESSORY_MESSAGES);
  }

  async removeKind(arenaId: string, id: string): Promise<'deleted' | 'retired'> {
    const [result] = await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'accessory_kind.remove', payload: { id } }],
      ACCESSORY_MESSAGES,
    );
    return result?.['removed'] === 'retired' ? 'retired' : 'deleted';
  }
}
