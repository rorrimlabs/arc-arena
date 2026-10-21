import { Service, inject } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import {
  AttendanceEntry,
  AttendanceLog,
  CORRECTION_MESSAGES,
  CorrectionPayload,
  EntryStatus,
  LocationStatus,
  Punch,
  PunchSnapshot,
  Review,
  StaffMember,
  Verdict,
} from './attendance.models';

/**
 * Reads the attendance log through RLS (the owner and `attendance_review` holders see every
 * row of the arena). Punches come from the floor app (`attendance.punch`); reviewers correct,
 * void, add and accept entries with `attendance.correct` / `attendance.review` ops through
 * sync_push. Not part of any realtime publication; live updates come from the broadcast nudge.
 * Tests provide SampleAttendanceApi.
 */
@Service({ factory: () => new SupabaseAttendanceApi() })
export abstract class AttendanceApi {
  /**
   * Active entries whose work_date is within `first`…`last` (IST days, inclusive), plus every
   * entry still open; their punches; and every staff member's name.
   */
  abstract load(
    arenaId: string,
    first: string,
    last: string,
    withInactive?: boolean,
  ): Promise<AttendanceLog>;
  /** Entries by id, whatever their status (a correction's earlier rows). */
  abstract entries(arenaId: string, ids: readonly string[]): Promise<AttendanceEntry[]>;
  /** attendance.correct; resolves with the new row's id (or the voided row's). */
  abstract correct(arenaId: string, payload: CorrectionPayload, opId?: string): Promise<string>;
  /** attendance.review: a pending entry becomes accepted. */
  abstract review(arenaId: string, entryId: string, note: string): Promise<void>;
}

const ENTRY_COLUMNS =
  'id, staff_id, work_date, in_at, out_at, in_punch_id, out_punch_id, source, out_source, flags, review, reason, status, replaces_id, created_by';
const PUNCH_COLUMNS =
  'id, staff_id, kind, server_at, device_at, via, device_id, lat, lng, accuracy_m, is_mocked, location_status, distance_m, geofence, geofence_snapshot, flags';
/** Rows per request (PostgREST caps a response; longer periods read in pages). */
const PAGE = 1000;
/** Punch ids per `in.(…)` filter, keeping the request URL short. */
const ID_CHUNK = 150;

type Row = Record<string, unknown>;

function num(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function str(v: unknown): string | null {
  return v === null || v === undefined ? null : String(v);
}

export function toEntry(r: Row): AttendanceEntry {
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    workDate: String(r['work_date']),
    inAt: String(r['in_at']),
    outAt: str(r['out_at']),
    inPunchId: str(r['in_punch_id']),
    outPunchId: str(r['out_punch_id']),
    source: r['source'] === 'manual' ? 'manual' : 'punch',
    outSource: (str(r['out_source']) as AttendanceEntry['outSource']) ?? null,
    flags: (r['flags'] as string[] | null) ?? [],
    review: (str(r['review']) ?? 'none') as Review,
    reason: str(r['reason']),
    status: (str(r['status']) ?? 'active') as EntryStatus,
    replacesId: str(r['replaces_id']),
    createdBy: str(r['created_by']),
  };
}

export function toSnapshot(v: unknown): PunchSnapshot | null {
  if (!v || typeof v !== 'object') return null;
  const s = v as Row;
  const g = s['geofence'] as Row | null | undefined;
  const lat = num(g?.['lat']);
  const lng = num(g?.['lng']);
  const radius = num(g?.['radius_m']);
  return {
    geofence:
      lat !== null && lng !== null && radius !== null ? { lat, lng, radiusM: radius } : null,
    outsideRule: str(s['outside_rule']),
    minAccuracyM: num(s['min_accuracy_m']),
    mockRule: str(s['mock_rule']),
  };
}

export function toPunch(r: Row): Punch {
  const mocked = r['is_mocked'];
  return {
    id: String(r['id']),
    staffId: String(r['staff_id']),
    kind: r['kind'] === 'out' ? 'out' : 'in',
    serverAt: String(r['server_at']),
    deviceAt: str(r['device_at']),
    via: String(r['via'] ?? 'own_device'),
    deviceId: String(r['device_id'] ?? ''),
    lat: num(r['lat']),
    lng: num(r['lng']),
    accuracyM: num(r['accuracy_m']),
    isMocked: typeof mocked === 'boolean' ? mocked : null,
    locationStatus: String(r['location_status']) as LocationStatus,
    distanceM: num(r['distance_m']),
    geofence: String(r['geofence']) as Verdict,
    snapshot: toSnapshot(r['geofence_snapshot']),
    flags: (r['flags'] as string[] | null) ?? [],
  };
}

class SupabaseAttendanceApi extends AttendanceApi {
  private readonly supabase = inject(Supabase);

  async load(
    arenaId: string,
    first: string,
    last: string,
    withInactive = false,
  ): Promise<AttendanceLog> {
    const client = await this.supabase.client();
    const [staff, entries] = await Promise.all([
      this.staff(client, arenaId),
      this.period(client, arenaId, first, last, withInactive),
    ]);
    const ids = [
      ...new Set(entries.flatMap((e) => [e.inPunchId, e.outPunchId]).filter((id) => !!id)),
    ] as string[];
    const punches = await this.punches(client, arenaId, ids);
    return { staff, entries, punches };
  }

  private async staff(client: SupabaseClient, arenaId: string): Promise<StaffMember[]> {
    const { data, error } = await client
      .from('staff_profiles')
      .select('id, name, active, user_id')
      .eq('arena_id', arenaId)
      .order('name');
    if (error) throw dbError(error);
    return (data as Row[]).map((r) => ({
      id: String(r['id']),
      name: String(r['name']),
      active: r['active'] === true,
      userId: str(r['user_id']),
    }));
  }

  async entries(arenaId: string, ids: readonly string[]): Promise<AttendanceEntry[]> {
    if (!ids.length) return [];
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('attendance_entries')
      .select(ENTRY_COLUMNS)
      .eq('arena_id', arenaId)
      .in('id', [...ids]);
    if (error) throw dbError(error);
    return (data as Row[]).map(toEntry);
  }

  async correct(arenaId: string, payload: CorrectionPayload, opId?: string): Promise<string> {
    const [result] = await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'attendance.correct', payload: { ...payload }, opId }],
      CORRECTION_MESSAGES,
    );
    return String(result?.['entry_id'] ?? '');
  }

  async review(arenaId: string, entryId: string, note: string): Promise<void> {
    const payload: Record<string, unknown> = { entry_id: entryId };
    if (note.trim()) payload['note'] = note.trim();
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'attendance.review', payload }],
      CORRECTION_MESSAGES,
    );
  }

  private async period(
    client: SupabaseClient,
    arenaId: string,
    first: string,
    last: string,
    withInactive: boolean,
  ): Promise<AttendanceEntry[]> {
    const out: AttendanceEntry[] = [];
    for (let from = 0; ; from += PAGE) {
      let query = client.from('attendance_entries').select(ENTRY_COLUMNS).eq('arena_id', arenaId);
      // Superseded and voided rows only when asked ("Show voided/superseded").
      if (!withInactive) query = query.eq('status', 'active');
      const { data, error } = await query
        .or(`and(work_date.gte.${first},work_date.lte.${last}),out_at.is.null`)
        .order('in_at', { ascending: false })
        .order('id')
        .range(from, from + PAGE - 1);
      if (error) throw dbError(error);
      const rows = data as Row[];
      out.push(...rows.map(toEntry));
      if (rows.length < PAGE) return out;
    }
  }

  private async punches(client: SupabaseClient, arenaId: string, ids: string[]): Promise<Punch[]> {
    const chunks: string[][] = [];
    for (let i = 0; i < ids.length; i += ID_CHUNK) chunks.push(ids.slice(i, i + ID_CHUNK));
    const reads = await Promise.all(
      chunks.map((chunk) =>
        client
          .from('attendance_punches')
          .select(PUNCH_COLUMNS)
          .eq('arena_id', arenaId)
          .in('id', chunk),
      ),
    );
    const out: Punch[] = [];
    for (const { data, error } of reads) {
      if (error) throw dbError(error);
      out.push(...(data as Row[]).map(toPunch));
    }
    return out;
  }
}
