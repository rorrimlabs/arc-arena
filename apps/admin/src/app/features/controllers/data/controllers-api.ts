import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import { CONTROLLER_STATUSES, Controller, ControllerStatus } from './controller.models';

/**
 * The arena's pads: read from the controllers table (RLS), written as controller.upsert /
 * controller.set_status ops through sync_push (the settings permission, as on the floor app).
 * Moving and lending pads stays a floor job. Tests provide SampleControllersApi.
 */
@Service({ factory: () => new SupabaseControllersApi() })
export abstract class ControllersApi {
  abstract controllers(arenaId: string): Promise<Controller[]>;
  /** One pad as the server holds it now (read right before an edit), or null. */
  abstract controller(arenaId: string, id: string): Promise<Controller | null>;
  /** controller.upsert: the whole row (a new pad, or an edit built on a fresh read). */
  abstract save(arenaId: string, controller: Controller): Promise<void>;
  /** controller.set_status: status and note only. */
  abstract setStatus(
    arenaId: string,
    id: string,
    status: ControllerStatus,
    notes: string | null,
  ): Promise<void>;
}

export const CONTROLLER_MESSAGES: Readonly<Record<string, string>> = {
  not_found: 'That controller is no longer there. Refresh',
  controller_in_use: 'A session is using it right now · try again after it ends',
  missing_reference: 'That station is no longer there. Refresh',
  cross_arena_reference: 'That station is no longer there. Refresh',
};

export const CONTROLLER_COLUMNS =
  'id, label, home_resource_id, current_resource_id, status, notes, loan_return_to, loan_session_ref';

export function controllerOps(c: Controller): SyncOp[] {
  return [
    {
      kind: 'controller.upsert',
      payload: {
        id: c.id,
        label: c.label,
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

export function statusOps(id: string, status: ControllerStatus, notes: string | null): SyncOp[] {
  return [{ kind: 'controller.set_status', payload: { id, status, notes } }];
}

export function parseController(r: Record<string, unknown>): Controller {
  const status = String(r['status']) as ControllerStatus;
  const str = (v: unknown) => (v == null ? null : String(v));
  return {
    id: String(r['id']),
    label: String(r['label']),
    homeId: String(r['home_resource_id']),
    currentId: String(r['current_resource_id']),
    // An unknown status is not usable, like the server's count of free pads.
    status: CONTROLLER_STATUSES.some((s) => s.value === status) ? status : 'unavailable',
    notes: str(r['notes']),
    loanReturnTo: str(r['loan_return_to']),
    loanSessionRef: str(r['loan_session_ref']),
  };
}

class SupabaseControllersApi extends ControllersApi {
  private readonly supabase = inject(Supabase);

  async controllers(arenaId: string): Promise<Controller[]> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('controllers')
      .select(CONTROLLER_COLUMNS)
      .eq('arena_id', arenaId)
      .order('label')
      .order('id');
    if (error) throw dbError(error);
    return ((data as Record<string, unknown>[] | null) ?? []).map(parseController);
  }

  async controller(arenaId: string, id: string): Promise<Controller | null> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('controllers')
      .select(CONTROLLER_COLUMNS)
      .eq('arena_id', arenaId)
      .eq('id', id)
      .maybeSingle();
    if (error) throw dbError(error);
    return data ? parseController(data as Record<string, unknown>) : null;
  }

  async save(arenaId: string, controller: Controller): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      controllerOps(controller),
      CONTROLLER_MESSAGES,
    );
  }

  async setStatus(
    arenaId: string,
    id: string,
    status: ControllerStatus,
    notes: string | null,
  ): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      statusOps(id, status, notes),
      CONTROLLER_MESSAGES,
    );
  }
}
