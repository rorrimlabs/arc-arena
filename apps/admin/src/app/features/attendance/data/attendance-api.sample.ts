import { AppError } from '../../../core/auth/auth-api';
import { AttendanceApi } from './attendance-api';
import {
  AttendanceEntry,
  AttendanceLog,
  CORRECTION_MESSAGES,
  CorrectionPayload,
  Punch,
  StaffMember,
} from './attendance.models';

/** The sample arena's geofence (Koramangala), as the punches were judged against it. */
export const SAMPLE_FENCE = { lat: 12.9352, lng: 77.6245, radiusM: 100 };

const SNAPSHOT = {
  geofence: SAMPLE_FENCE,
  outsideRule: 'flag',
  minAccuracyM: 50,
  mockRule: 'flag',
};

export const SAMPLE_STAFF: StaffMember[] = [
  { id: 's1', name: 'Priya Nair', active: true, userId: 'u1' },
  { id: 's2', name: 'Rohan Das', active: true, userId: 'u2' },
  { id: 's3', name: 'Kavya Iyer', active: true, userId: 'u3' },
  // The owner (the signed-in sample login): untracked, but names the corrections they make.
  { id: 's0', name: 'Arjun Mehra', active: true, userId: 'u0' },
];

function punch(
  id: string,
  staffId: string,
  kind: 'in' | 'out',
  serverAt: string,
  over: Partial<Punch> = {},
): Punch {
  return {
    id,
    staffId,
    kind,
    serverAt,
    deviceAt: serverAt,
    via: 'own_device',
    deviceId: `dev-${staffId}`,
    lat: 12.9354,
    lng: 77.6247,
    accuracyM: 8,
    isMocked: false,
    locationStatus: 'ok',
    distanceM: 30,
    geofence: 'inside',
    snapshot: SNAPSHOT,
    flags: [],
    ...over,
  };
}

function entry(
  id: string,
  staffId: string,
  workDate: string,
  inAt: string,
  outAt: string | null,
  over: Partial<AttendanceEntry> = {},
): AttendanceEntry {
  return {
    id,
    staffId,
    workDate,
    inAt,
    outAt,
    inPunchId: `${id}-in`,
    outPunchId: outAt ? `${id}-out` : null,
    source: 'punch',
    outSource: outAt ? 'punch' : null,
    flags: [],
    review: 'none',
    reason: null,
    status: 'active',
    replacesId: null,
    createdBy: null,
    ...over,
  };
}

/**
 * The sample log around NOW (2026-10-13 7:30 pm IST): Priya on the clock since 9:02 am, Rohan
 * clocked out outside the arena (phone 5 min ahead), Kavya's clock-in with location off, an
 * entry closed automatically, a fake-location clock-in, and one entry older than a week.
 */
export function sampleAttendance(): { entries: AttendanceEntry[]; punches: Punch[] } {
  const entries = [
    entry('e1', 's1', '2026-10-13', '2026-10-13T03:32:00Z', null, {}),
    entry('e2', 's2', '2026-10-13', '2026-10-13T04:30:00Z', '2026-10-13T12:40:00Z', {
      flags: ['outside_out'],
      review: 'pending',
    }),
    entry('e3', 's3', '2026-10-12', '2026-10-12T05:00:00Z', '2026-10-12T13:30:00Z', {
      flags: ['unknown_in'],
      review: 'pending',
    }),
    entry('e4', 's1', '2026-10-11', '2026-10-11T03:30:00Z', '2026-10-11T17:30:00Z', {
      outPunchId: null,
      outSource: 'auto',
      flags: ['auto_out'],
      review: 'pending',
    }),
    entry('e6', 's3', '2026-10-10', '2026-10-10T05:00:00Z', '2026-10-10T12:00:00Z', {
      flags: ['mock_in'],
      review: 'pending',
    }),
    entry('e5', 's2', '2026-10-05', '2026-10-05T04:00:00Z', '2026-10-05T12:00:00Z'),
  ];
  const punches = [
    punch('e1-in', 's1', 'in', '2026-10-13T03:32:00Z', { distanceM: 42 }),
    punch('e2-in', 's2', 'in', '2026-10-13T04:30:00Z'),
    punch('e2-out', 's2', 'out', '2026-10-13T12:40:00Z', {
      deviceAt: '2026-10-13T12:45:00Z',
      lat: 12.9381,
      lng: 77.6262,
      accuracyM: 12,
      distanceM: 380,
      geofence: 'outside',
      flags: ['outside'],
    }),
    punch('e3-in', 's3', 'in', '2026-10-12T05:00:00Z', {
      lat: null,
      lng: null,
      accuracyM: null,
      isMocked: null,
      locationStatus: 'denied',
      distanceM: null,
      geofence: 'unknown',
      flags: ['unknown'],
    }),
    punch('e3-out', 's3', 'out', '2026-10-12T13:30:00Z'),
    punch('e4-in', 's1', 'in', '2026-10-11T03:30:00Z'),
    punch('e6-in', 's3', 'in', '2026-10-10T05:00:00Z', { isMocked: true, flags: ['mock'] }),
    punch('e6-out', 's3', 'out', '2026-10-10T12:00:00Z'),
    punch('e5-in', 's2', 'in', '2026-10-05T04:00:00Z'),
    punch('e5-out', 's2', 'out', '2026-10-05T12:00:00Z'),
  ];
  return { entries, punches };
}

/** Deterministic in-memory AttendanceApi for tests; corrections apply as the server would. */
export class SampleAttendanceApi extends AttendanceApi {
  staff = [...SAMPLE_STAFF];
  data = sampleAttendance();
  /** Every load, as [first, last] (and whether superseded / voided rows were asked for). */
  readonly loads: [string, string][] = [];
  readonly inactiveLoads: boolean[] = [];
  /** Every write, as `kind` + payload (what sync_push would get). */
  readonly ops: { kind: string; payload: Record<string, unknown> }[] = [];
  /** The signed-in login, for the own-record rule ('u0' is the sample owner). */
  userId = 'u0';
  ownerRole = true;
  /** Refuse the next write with this code (e.g. 'period_finalised'). */
  refuseNext: string | null = null;
  private nextId = 1;

  async load(
    _arenaId: string,
    first: string,
    last: string,
    withInactive = false,
  ): Promise<AttendanceLog> {
    this.loads.push([first, last]);
    this.inactiveLoads.push(withInactive);
    const entries = this.data.entries.filter(
      (e) =>
        (withInactive || e.status === 'active') &&
        ((e.workDate >= first && e.workDate <= last) || e.outAt === null),
    );
    const ids = new Set(entries.flatMap((e) => [e.inPunchId, e.outPunchId]));
    return {
      staff: this.staff,
      entries,
      punches: this.data.punches.filter((p) => ids.has(p.id)),
    };
  }

  async entries(_arenaId: string, ids: readonly string[]): Promise<AttendanceEntry[]> {
    return this.data.entries.filter((e) => ids.includes(e.id));
  }

  async correct(_arenaId: string, payload: CorrectionPayload): Promise<string> {
    this.ops.push({ kind: 'attendance.correct', payload: { ...payload } });
    const refuse = (code: string) => new AppError(code, CORRECTION_MESSAGES[code] ?? code);
    if (this.refuseNext) {
      const code = this.refuseNext;
      this.refuseNext = null;
      throw refuse(code);
    }
    if (!payload.reason.trim()) throw refuse('reason_required');
    const staffOf = (id: string) => this.staff.find((s) => s.id === id);
    const own = (staffId: string) => !this.ownerRole && staffOf(staffId)?.userId === this.userId;
    if (payload.action === 'add') {
      if (!staffOf(payload.staff_id)) throw refuse('not_found');
      if (own(payload.staff_id)) throw refuse('own_record');
      const id = `m${this.nextId++}`;
      this.data.entries.push({
        id,
        staffId: payload.staff_id,
        workDate: new Date(Date.parse(payload.in_at) + 330 * 60_000).toISOString().slice(0, 10),
        inAt: payload.in_at,
        outAt: payload.out_at,
        inPunchId: null,
        outPunchId: null,
        source: 'manual',
        outSource: 'manual',
        flags: [],
        review: 'corrected',
        reason: payload.reason,
        status: 'active',
        replacesId: null,
        createdBy: this.userId,
      });
      return id;
    }
    const old = this.data.entries.find((e) => e.id === payload.entry_id);
    if (!old) throw refuse('not_found');
    if (own(old.staffId)) throw refuse('own_record');
    if (old.status !== 'active') throw refuse('not_active');
    const rest = this.data.entries.filter((e) => e.id !== old.id);
    if (payload.action === 'void') {
      this.data.entries = [...rest, { ...old, status: 'voided' }];
      return old.id;
    }
    const id = `c${this.nextId++}`;
    this.data.entries = [
      ...rest,
      { ...old, status: 'superseded' },
      {
        ...old,
        id,
        inAt: payload.in_at,
        outAt: payload.out_at,
        outSource: payload.out_at ? 'manual' : null,
        outPunchId: payload.out_at ? old.outPunchId : null,
        source: 'manual',
        review: 'corrected',
        reason: payload.reason,
        status: 'active',
        replacesId: old.id,
        createdBy: this.userId,
      },
    ];
    return id;
  }

  async review(_arenaId: string, entryId: string, note: string): Promise<void> {
    const payload: Record<string, unknown> = { entry_id: entryId };
    if (note.trim()) payload['note'] = note.trim();
    this.ops.push({ kind: 'attendance.review', payload });
    const e = this.data.entries.find((x) => x.id === entryId);
    if (!e) throw new AppError('not_found', CORRECTION_MESSAGES['not_found']);
    if (e.review !== 'pending') {
      throw new AppError('not_pending', CORRECTION_MESSAGES['not_pending']);
    }
    this.data.entries = this.data.entries.map((x) =>
      x.id === entryId ? { ...x, review: 'accepted' as const } : x,
    );
  }
}
