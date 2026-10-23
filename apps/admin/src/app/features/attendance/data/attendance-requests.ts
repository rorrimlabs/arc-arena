import { Service, inject, signal } from '@angular/core';
import { dbError } from '../../../core/arena/arena-api';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import { CORRECTION_MESSAGES } from './attendance.models';

/** A staff member's missed-punch request waiting for a decision (attendance_requests). */
export interface AttendanceRequestRow {
  readonly id: string;
  readonly staffId: string;
  readonly staffName: string;
  /** 'add': a stretch never punched; 'fix_out': the clock-out of an existing entry. */
  readonly kind: 'add' | 'fix_out';
  readonly inAt: string;
  readonly outAt: string;
  readonly reason: string;
  readonly createdAt: string;
}

/** Server codes of attendance.request_decide (approval runs attendance.correct). */
export const REQUEST_MESSAGES: Readonly<Record<string, string>> = {
  ...CORRECTION_MESSAGES,
  not_found: 'That request is no longer there. Refresh',
  invalid_state: 'That request was already decided. Refresh',
  note_too_long: 'Keep the note under 500 characters',
  own_record: 'Nobody decides their own request. Ask someone else with Review attendance',
};

type Row = Record<string, unknown>;

/**
 * Pending missed-punch requests (Review attendance): read through RLS; Approve applies one as a
 * correction, Reject keeps it with the note (attendance.request_decide). A broadcast of an applied
 * `attendance.*` op reloads it (RealtimeSync).
 */
@Service()
export class AttendanceRequestsStore {
  private readonly supabase = inject(Supabase);
  private readonly arena = inject(ArenaContext);

  readonly pending = signal<readonly AttendanceRequestRow[]>([]);
  readonly error = signal('');
  private loaded = false;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.loaded = false;
      this.pending.set([]);
    });
  }

  async load(): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    try {
      const client = await this.supabase.client();
      const { data, error } = await client
        .from('attendance_requests')
        .select('id, staff_id, kind, in_at, out_at, reason, created_at, staff_profiles(name)')
        .eq('arena_id', arenaId)
        .eq('status', 'pending')
        .order('created_at');
      if (error) throw dbError(error);
      this.pending.set((data as Row[]).map(toRow));
      this.error.set('');
      this.loaded = true;
    } catch (e) {
      this.error.set(toAppError(e).message);
    }
  }

  /** Reads again only once something has loaded it (live updates). */
  async refresh(): Promise<void> {
    if (this.loaded) await this.load();
  }

  async decide(id: string, approve: boolean, note: string): Promise<void> {
    const payload: Record<string, unknown> = { id, approve };
    if (note.trim()) payload['note'] = note.trim();
    await pushOps(
      await this.supabase.client(),
      this.arena.current().id,
      [{ kind: 'attendance.request_decide', payload }],
      REQUEST_MESSAGES,
    );
    await this.load();
  }
}

function toRow(r: Row): AttendanceRequestRow {
  const staff = r['staff_profiles'] as Row | null;
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    staffName: staff ? String(staff['name'] ?? '') : '',
    kind: r['kind'] === 'fix_out' ? 'fix_out' : 'add',
    inAt: String(r['in_at']),
    outAt: String(r['out_at']),
    reason: String(r['reason'] ?? ''),
    createdAt: String(r['created_at']),
  };
}
