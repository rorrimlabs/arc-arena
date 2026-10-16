import { PillTone } from '../../../shared/status-pill/status-pill';
import { Geofence } from '../../settings/data/attendance-rules';

/**
 * The attendance log (docs/STAFF.md §2): stretches of work (attendance_entries) and the punch
 * evidence behind each end (attendance_punches). Server times only; instants are UTC ISO and
 * shown in IST.
 */

/** Where a punch was, as the server judged it ('arena_device': a registered clock-in tablet). */
export type Verdict = 'inside' | 'outside' | 'unknown' | 'arena_device';
export type LocationStatus =
  'ok' | 'denied' | 'gps_off' | 'timeout' | 'unavailable' | 'arena_device';
export type Review = 'none' | 'pending' | 'accepted' | 'corrected';
/** `superseded`: replaced by a correction; `voided`: struck out. Only `active` rows count. */
export type EntryStatus = 'active' | 'superseded' | 'voided';

/** The rules a punch was judged by (attendance_punches.geofence_snapshot). */
export interface PunchSnapshot {
  readonly geofence: Geofence | null;
  readonly outsideRule: string | null;
  readonly minAccuracyM: number | null;
  readonly mockRule: string | null;
}

/** One clock action and its evidence (immutable). */
export interface Punch {
  readonly id: string;
  readonly staffId: string;
  readonly kind: 'in' | 'out';
  /** When the server recorded it: the only time used. */
  readonly serverAt: string;
  /** The phone's own clock: evidence only. */
  readonly deviceAt: string | null;
  readonly via: string;
  readonly deviceId: string;
  readonly lat: number | null;
  readonly lng: number | null;
  readonly accuracyM: number | null;
  /** Null: the phone did not say (or there was no fix). */
  readonly isMocked: boolean | null;
  readonly locationStatus: LocationStatus;
  readonly distanceM: number | null;
  readonly geofence: Verdict;
  readonly snapshot: PunchSnapshot | null;
  readonly flags: readonly string[];
}

/** One stretch of work: a clock-in and (once closed) its clock-out. */
export interface AttendanceEntry {
  readonly id: string;
  readonly staffId: string;
  /** IST date of the clock-in ("2026-10-13"). */
  readonly workDate: string;
  readonly inAt: string;
  /** Null: still on the clock. */
  readonly outAt: string | null;
  readonly inPunchId: string | null;
  readonly outPunchId: string | null;
  readonly source: 'punch' | 'manual';
  readonly outSource: 'punch' | 'auto' | 'manual' | null;
  readonly flags: readonly string[];
  readonly review: Review;
  readonly reason: string | null;
  readonly status: EntryStatus;
  /** The row this one corrects (a correction's earlier version). */
  readonly replacesId: string | null;
  /** The login that made the row (the reviewer, for a correction or an added entry). */
  readonly createdBy: string | null;
}

export interface StaffMember {
  readonly id: string;
  readonly name: string;
  readonly active: boolean;
  /** The member's login (to tell their own entries apart). */
  readonly userId: string | null;
}

/** What the log reads for a period: active entries, their punches, and every staff name. */
export interface AttendanceLog {
  readonly staff: readonly StaffMember[];
  readonly entries: readonly AttendanceEntry[];
  readonly punches: readonly Punch[];
}

/** An entry with the names and punches it refers to. */
export interface LogRow {
  readonly entry: AttendanceEntry;
  readonly staffName: string;
  readonly inPunch: Punch | null;
  readonly outPunch: Punch | null;
}

export type VerdictFilter = 'any' | 'inside' | 'outside' | 'unknown';

export const VERDICT_FILTERS: readonly { value: VerdictFilter; label: string }[] = [
  { value: 'any', label: 'Any location' },
  { value: 'inside', label: 'Inside' },
  { value: 'outside', label: 'Outside' },
  { value: 'unknown', label: 'Unknown' },
];

export interface LogFilter {
  /** IST days, inclusive ("2026-10-07" … "2026-10-13"), matched on work_date. */
  readonly first: string;
  readonly last: string;
  readonly staffId: string | null;
  /** An entry matches when either of its punches does. */
  readonly verdict: VerdictFilter;
  /** Only entries waiting for review. */
  readonly needsReview: boolean;
  /** Only entries still open, whatever day they started. */
  readonly onClock: boolean;
}

export function asVerdictFilter(value: string | undefined): VerdictFilter {
  return VERDICT_FILTERS.some((v) => v.value === value) ? (value as VerdictFilter) : 'any';
}

/** Entries and punches joined with names; newest clock-in first. */
export function buildRows(log: AttendanceLog): LogRow[] {
  const names = new Map(log.staff.map((s) => [s.id, s.name]));
  const punches = new Map(log.punches.map((p) => [p.id, p]));
  return log.entries
    .map((entry) => ({
      entry,
      staffName: names.get(entry.staffId) ?? 'Former staff',
      inPunch: (entry.inPunchId && punches.get(entry.inPunchId)) || null,
      outPunch: (entry.outPunchId && punches.get(entry.outPunchId)) || null,
    }))
    .sort((a, b) => Date.parse(b.entry.inAt) - Date.parse(a.entry.inAt));
}

/** The verdict a filter value matches ("inside" includes a clock-in tablet's punches). */
function verdictMatches(v: Verdict | undefined, want: VerdictFilter): boolean {
  if (!v) return false;
  return want === 'inside' ? v === 'inside' || v === 'arena_device' : v === want;
}

export function filterRows(rows: readonly LogRow[], f: LogFilter): LogRow[] {
  return rows.filter((r) => {
    const e = r.entry;
    // "On the clock now" shows every open entry, even one started before the period.
    if (f.onClock) {
      if (e.outAt !== null) return false;
    } else if (e.workDate < f.first || e.workDate > f.last) {
      return false;
    }
    if (f.staffId && e.staffId !== f.staffId) return false;
    if (f.needsReview && e.review !== 'pending') return false;
    if (
      f.verdict !== 'any' &&
      !verdictMatches(r.inPunch?.geofence, f.verdict) &&
      !verdictMatches(r.outPunch?.geofence, f.verdict)
    ) {
      return false;
    }
    return true;
  });
}

/** Worked minutes: out − in, or so far for an open entry (from its stored clock-in, never a counter). */
export function entryMinutes(e: AttendanceEntry, now: Date): number {
  const end = e.outAt ? Date.parse(e.outAt) : now.getTime();
  return Math.max(0, Math.floor((end - Date.parse(e.inAt)) / 60_000));
}

export const VERDICT_LABELS: Readonly<Record<Verdict, string>> = {
  inside: 'Inside',
  outside: 'Outside',
  unknown: 'Unknown',
  arena_device: 'Arena tablet',
};

const VERDICT_TONES: Readonly<Record<Verdict, PillTone>> = {
  inside: 'success',
  outside: 'warning',
  unknown: 'info',
  arena_device: 'success',
};

export function verdictLabel(v: Verdict): string {
  return VERDICT_LABELS[v] ?? v;
}

export function verdictTone(v: Verdict): PillTone {
  return VERDICT_TONES[v] ?? 'info';
}

/** A flag's meaning without the in/out end (punch flags carry none; entry flags end _in/_out). */
const FLAG_WORDS: Readonly<Record<string, string>> = {
  outside: 'Outside the arena',
  unknown: 'Location unknown',
  low_accuracy: 'Weak GPS',
  no_geofence: 'No arena location set',
  mock: 'Fake location',
};

const WHOLE_FLAGS: Readonly<Record<string, string>> = {
  auto_out: 'Closed automatically',
  worked_on_leave: 'Worked on a leave day',
  manual: 'Added by hand',
};

/** "auto_out" → "Closed automatically", "mock_in" → "Fake location (in)", "outside" → "Outside the arena". */
export function flagLabel(code: string): string {
  if (WHOLE_FLAGS[code]) return WHOLE_FLAGS[code];
  const m = /^(.*)_(in|out)$/.exec(code);
  if (m && FLAG_WORDS[m[1]]) return `${FLAG_WORDS[m[1]]} (${m[2]})`;
  if (FLAG_WORDS[code]) return FLAG_WORDS[code];
  const words = code.replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function flagTone(code: string): PillTone {
  if (code.startsWith('mock')) return 'danger';
  if (code === 'auto_out' || code.startsWith('outside') || code === 'worked_on_leave') {
    return 'warning';
  }
  return 'info';
}

/**
 * The flags worth a chip on a list row: outside / unknown are already shown by the in and out
 * badges, so they are left out there (the detail and the export list them all).
 */
export function rowFlags(flags: readonly string[]): string[] {
  return flags.filter((f) => !/^(outside|unknown)(_in|_out)?$/.test(f));
}

export function reviewLabel(r: Review): { label: string; tone: PillTone } | null {
  switch (r) {
    case 'pending':
      return { label: 'Needs review', tone: 'warning' };
    case 'accepted':
      return { label: 'Accepted', tone: 'info' };
    case 'corrected':
      return { label: 'Corrected', tone: 'info' };
    default:
      return null;
  }
}

const LOCATION_STATUS: Readonly<Record<LocationStatus, string>> = {
  ok: 'GPS fix',
  denied: 'Location permission off',
  gps_off: 'Location services off',
  timeout: 'No GPS fix in time',
  unavailable: 'Location unavailable',
  arena_device: 'Arena tablet (no GPS needed)',
};

export function locationStatusLabel(s: LocationStatus): string {
  return LOCATION_STATUS[s] ?? s;
}

/**
 * How far the phone's clock was from the server's at the punch: "5 min ahead" / "3 min behind";
 * null when it was within 2 minutes or the phone sent no time.
 */
export function phoneSkew(p: Punch): string | null {
  if (!p.deviceAt) return null;
  const diff = (Date.parse(p.deviceAt) - Date.parse(p.serverAt)) / 60_000;
  if (Math.abs(diff) <= 2) return null;
  const minutes = Math.round(Math.abs(diff));
  return `${minutes} min ${diff > 0 ? 'ahead' : 'behind'}`;
}

/**
 * The circle to draw for an entry: the geofence its clock-in (else clock-out) was judged
 * against, else `fallback` (the current setting). `fromPunch` says which one it is.
 */
export function entryFence(
  row: Pick<LogRow, 'inPunch' | 'outPunch'>,
  fallback: Geofence | null,
): { fence: Geofence | null; fromPunch: boolean } {
  const judged = row.inPunch?.snapshot?.geofence ?? row.outPunch?.snapshot?.geofence ?? null;
  return judged ? { fence: judged, fromPunch: true } : { fence: fallback, fromPunch: false };
}

/** "12.934512, 77.610123" */
export function formatLatLng(lat: number, lng: number): string {
  return `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
}

/** "Superseded" / "Voided" for a row that no longer counts; null for an active one. */
export function entryStatusLabel(s: EntryStatus): { label: string; tone: PillTone } | null {
  switch (s) {
    case 'superseded':
      return { label: 'Superseded', tone: 'info' };
    case 'voided':
      return { label: 'Voided', tone: 'danger' };
    default:
      return null;
  }
}

/** Refusals of attendance.correct and attendance.review, in plain words. */
export const CORRECTION_MESSAGES: Readonly<Record<string, string>> = {
  reason_required: 'Give a reason for the change',
  not_found: 'That entry or person is no longer there. Refresh',
  own_record:
    'Nobody corrects or accepts their own attendance. Ask someone else with Review attendance',
  not_active: 'That entry was already corrected or voided. Refresh to see the current one',
  invalid_times:
    'Check the times: clock-out must be after clock-in, neither in the future, and at most 24 hours apart',
  overlap: 'Those times overlap another entry of theirs. Change the times or correct that one first',
  period_finalised:
    'That day is in a finalised salary run, so it can’t change. Make the fix as an adjustment in the next run',
  not_pending: 'That entry no longer needs review. Refresh',
  forbidden: 'You need the Review attendance permission for that',
  invalid_payload: 'Check the values and try again',
};

const IST_OFFSET_MS = 330 * 60_000;

/** IST date + time ("2026-10-13", "09:05") → the UTC instant (ISO); null when either is invalid. */
export function istInstant(date: string, time: string): string | null {
  const d = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date.trim());
  const t = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(time.trim());
  if (!d || !t || +t[1] > 23 || +t[2] > 59) return null;
  const utc = Date.UTC(+d[1], +d[2] - 1, +d[3], +t[1], +t[2]);
  const check = new Date(utc);
  if (check.getUTCDate() !== +d[3] || check.getUTCMonth() !== +d[2] - 1) return null;
  return new Date(utc - IST_OFFSET_MS).toISOString();
}

/** A UTC instant → its IST date and time, for the date and time pickers. */
export function istParts(iso: string): { date: string; time: string } {
  const local = new Date(Date.parse(iso) + IST_OFFSET_MS).toISOString();
  return { date: local.slice(0, 10), time: local.slice(11, 16) };
}

/** What a correction carries before it is sent (times as UTC ISO). */
export type CorrectionPayload =
  | {
      readonly action: 'edit';
      readonly entry_id: string;
      readonly in_at: string;
      readonly out_at: string | null;
      readonly reason: string;
    }
  | { readonly action: 'void'; readonly entry_id: string; readonly reason: string }
  | {
      readonly action: 'add';
      readonly staff_id: string;
      readonly in_at: string;
      readonly out_at: string;
      readonly reason: string;
    };

/**
 * What the server would refuse in a correction's times or reason, in plain words (null when
 * none): a reason, a clock-in, a clock-out after it (required when adding), neither in the
 * future, and at most 24 hours apart.
 */
export function correctionProblem(
  c: { inAt: string | null; outAt: string | null; reason: string; outRequired: boolean },
  now: Date,
): string | null {
  if (!c.inAt) return 'Pick the clock-in date and time';
  if (c.outRequired && !c.outAt) return 'Pick the clock-out date and time';
  const inMs = Date.parse(c.inAt);
  if (inMs > now.getTime()) return 'The clock-in can’t be in the future';
  if (c.outAt) {
    const outMs = Date.parse(c.outAt);
    if (outMs <= inMs) return 'The clock-out must be after the clock-in';
    if (outMs > now.getTime()) return 'The clock-out can’t be in the future';
    if (outMs - inMs > 24 * 60 * 60_000) return 'An entry can be at most 24 hours long';
  }
  if (!c.reason.trim()) return CORRECTION_MESSAGES['reason_required'];
  return null;
}

/**
 * The signed-in login may not correct or accept this entry: it is their own and they are not
 * the owner (docs/STAFF_API.md own-record rule).
 */
export function isOwnRecord(
  entryStaffId: string,
  staff: readonly StaffMember[],
  userId: string | null | undefined,
  role: string | null,
): boolean {
  if (!userId || role === 'owner') return false;
  return staff.some((s) => s.id === entryStaffId && s.userId === userId);
}

/** "Corrected from 9:02 am–6:10 pm by Arjun · wrong clock-out" for a correction's earlier row. */
export function correctionLine(
  previous: Pick<AttendanceEntry, 'inAt' | 'outAt'>,
  by: string | null,
  reason: string | null,
  formatTime: (iso: string) => string,
): string {
  const span = `${formatTime(previous.inAt)}–${previous.outAt ? formatTime(previous.outAt) : 'open'}`;
  return [`Corrected from ${span}`, by ? ` by ${by}` : '', reason ? ` · ${reason}` : ''].join('');
}
