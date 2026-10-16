import { Service, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import { round6 } from '../../../shared/map/geo';

/**
 * The arena's clock-in rules (settings key `attendance`, validated by the server's
 * _attendance_settings; docs/STAFF.md §2 and §5). The floor app applies them on the server at
 * every clock-in and clock-out.
 */
export type OutsideRule = 'block' | 'flag' | 'allow';
export type MockRule = 'block' | 'flag';

export interface Geofence {
  readonly lat: number;
  readonly lng: number;
  readonly radiusM: number;
}

export interface AttendanceRules {
  /** Null: no arena location, so every punch's position is unknown. */
  readonly geofence: Geofence | null;
  /** For punches outside the circle or with an unknown position. */
  readonly outsideRule: OutsideRule;
  /** A fix less precise than this many metres counts as unknown. */
  readonly minAccuracyM: number;
  /** For a phone that reports a fake (mock) location. */
  readonly mockRule: MockRule;
  /** A clock-in left open longer than this is closed at clock-in + these hours and flagged. */
  readonly maxOpenHours: number;
}

/** What the server applies before an arena saves its own (_attendance_rules). */
export const DEFAULT_ATTENDANCE_RULES: AttendanceRules = {
  geofence: null,
  outsideRule: 'flag',
  minAccuracyM: 50,
  mockRule: 'block',
  maxOpenHours: 14,
};

/** The radius a new arena location starts with (docs/STAFF.md §5). */
export const DEFAULT_RADIUS_M = 100;

/** The server's limits (_attendance_settings), inclusive. */
export const ATTENDANCE_LIMITS = {
  radiusM: [20, 5000],
  minAccuracyM: [5, 500],
  maxOpenHours: [4, 24],
} as const;

export const OUTSIDE_RULES: readonly { value: OutsideRule; label: string; sub: string }[] = [
  {
    value: 'block',
    label: 'Block',
    sub: 'Refuse the clock-in or clock-out. Staff are told why and how to fix it.',
  },
  {
    value: 'flag',
    label: 'Flag for review',
    sub: 'Accept it and mark the entry for review.',
  },
  { value: 'allow', label: 'Allow', sub: 'Accept it and just record where it happened.' },
];

export const MOCK_RULES: readonly { value: MockRule; label: string; sub: string }[] = [
  { value: 'block', label: 'Block', sub: 'Refuse the clock-in or clock-out.' },
  { value: 'flag', label: 'Flag for review', sub: 'Accept it and mark the entry for review.' },
];

export const ATTENDANCE_RULE_MESSAGES: Readonly<Record<string, string>> = {
  invalid_attendance_settings:
    'The server refused these attendance settings: check the location, radius and limits',
  setting_not_shared:
    'This server does not accept attendance settings yet. Apply the latest migrations',
};

function oneOf<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

function intIn(value: unknown, [min, max]: readonly [number, number], fallback: number): number {
  const n = Number(value);
  return Number.isInteger(n) && n >= min && n <= max ? n : fallback;
}

/** The saved json → rules; anything missing or out of range reads as the default. */
export function parseAttendanceRules(json: unknown): AttendanceRules {
  const j = (json ?? {}) as Record<string, unknown>;
  const d = DEFAULT_ATTENDANCE_RULES;
  const g = j['geofence'] as Record<string, unknown> | null | undefined;
  const lat = Number(g?.['lat']);
  const lng = Number(g?.['lng']);
  const geofence =
    g && Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
      ? { lat, lng, radiusM: intIn(g['radius_m'], ATTENDANCE_LIMITS.radiusM, DEFAULT_RADIUS_M) }
      : null;
  return {
    geofence,
    outsideRule: oneOf(j['outside_rule'], ['block', 'flag', 'allow'], d.outsideRule),
    minAccuracyM: intIn(j['min_accuracy_m'], ATTENDANCE_LIMITS.minAccuracyM, d.minAccuracyM),
    mockRule: oneOf(j['mock_rule'], ['block', 'flag'], d.mockRule),
    maxOpenHours: intIn(j['max_open_hours'], ATTENDANCE_LIMITS.maxOpenHours, d.maxOpenHours),
  };
}

/** Rules → the `settings.save` json: exactly the five keys the server requires. */
export function attendanceJson(r: AttendanceRules): Record<string, unknown> {
  return {
    geofence: r.geofence
      ? { lat: round6(r.geofence.lat), lng: round6(r.geofence.lng), radius_m: r.geofence.radiusM }
      : null,
    outside_rule: r.outsideRule,
    min_accuracy_m: r.minAccuracyM,
    mock_rule: r.mockRule,
    max_open_hours: r.maxOpenHours,
  };
}

/** The settings screen's draft: numbers as typed (strings), so a half-typed value can be shown. */
export interface AttendanceDraft {
  readonly lat: string;
  readonly lng: string;
  readonly radius: string;
  readonly outsideRule: OutsideRule;
  readonly minAccuracy: string;
  readonly mockRule: MockRule;
  readonly maxOpenHours: string;
}

export type DraftField = 'location' | 'radius' | 'outsideRule' | 'minAccuracy' | 'maxOpenHours';
export type DraftProblems = Partial<Record<DraftField, string>>;

export function toDraft(r: AttendanceRules): AttendanceDraft {
  return {
    lat: r.geofence ? String(r.geofence.lat) : '',
    lng: r.geofence ? String(r.geofence.lng) : '',
    radius: String(r.geofence?.radiusM ?? DEFAULT_RADIUS_M),
    outsideRule: r.outsideRule,
    minAccuracy: String(r.minAccuracyM),
    mockRule: r.mockRule,
    maxOpenHours: String(r.maxOpenHours),
  };
}

function num(text: string): number {
  return text.trim() === '' ? Number.NaN : Number(text.trim());
}

function wholeIn(text: string, [min, max]: readonly [number, number]): boolean {
  const n = num(text);
  return Number.isInteger(n) && n >= min && n <= max;
}

/** The draft has an arena location (both coordinates typed). */
export function draftHasLocation(d: AttendanceDraft): boolean {
  return d.lat.trim() !== '' || d.lng.trim() !== '';
}

/** What the server would refuse in a draft, per field, in plain words; empty when none. */
export function draftProblems(d: AttendanceDraft): DraftProblems {
  const problems: DraftProblems = {};
  const located = draftHasLocation(d);
  if (located) {
    const lat = num(d.lat);
    const lng = num(d.lng);
    if (d.lat.trim() === '' || d.lng.trim() === '') {
      problems.location = 'Enter both latitude and longitude, or clear the location';
    } else if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
      problems.location = 'Latitude must be between -90 and 90';
    } else if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
      problems.location = 'Longitude must be between -180 and 180';
    }
    const [min, max] = ATTENDANCE_LIMITS.radiusM;
    if (!wholeIn(d.radius, ATTENDANCE_LIMITS.radiusM)) {
      problems.radius = `Radius must be a whole number of metres from ${min} to ${max}`;
    }
  }
  if (d.outsideRule === 'block' && !located) {
    problems.outsideRule =
      'Block needs the arena location: set it on the map, or choose Flag or Allow';
  }
  if (!wholeIn(d.minAccuracy, ATTENDANCE_LIMITS.minAccuracyM)) {
    const [min, max] = ATTENDANCE_LIMITS.minAccuracyM;
    problems.minAccuracy = `Minimum accuracy must be a whole number of metres from ${min} to ${max}`;
  }
  if (!wholeIn(d.maxOpenHours, ATTENDANCE_LIMITS.maxOpenHours)) {
    const [min, max] = ATTENDANCE_LIMITS.maxOpenHours;
    problems.maxOpenHours = `Auto-close must be a whole number of hours from ${min} to ${max}`;
  }
  return problems;
}

/** A valid draft → rules; null when the draft has a problem (draftProblems says which). */
export function fromDraft(d: AttendanceDraft): AttendanceRules | null {
  if (Object.keys(draftProblems(d)).length) return null;
  return {
    geofence: draftHasLocation(d)
      ? { lat: round6(num(d.lat)), lng: round6(num(d.lng)), radiusM: num(d.radius) }
      : null,
    outsideRule: d.outsideRule,
    minAccuracyM: num(d.minAccuracy),
    mockRule: d.mockRule,
    maxOpenHours: num(d.maxOpenHours),
  };
}

/** Two drafts say the same thing (numbers compared as numbers: "100" and "100.0" match). */
export function sameDraft(a: AttendanceDraft, b: AttendanceDraft): boolean {
  const same = (x: string, y: string) => x.trim() === y.trim() || num(x) === num(y);
  // Without a location the radius is not saved, so it does not make the draft different.
  const located = draftHasLocation(a) || draftHasLocation(b);
  return (
    same(a.lat, b.lat) &&
    same(a.lng, b.lng) &&
    (!located || same(a.radius, b.radius)) &&
    a.outsideRule === b.outsideRule &&
    same(a.minAccuracy, b.minAccuracy) &&
    a.mockRule === b.mockRule &&
    same(a.maxOpenHours, b.maxOpenHours)
  );
}

/** "Within 100 m · flag outside" — the section's one-line summary. */
export function rulesSummary(r: AttendanceRules): string {
  const where = r.geofence ? `Within ${r.geofence.radiusM} m` : 'No arena location';
  const rule = OUTSIDE_RULES.find((o) => o.value === r.outsideRule)?.label ?? r.outsideRule;
  return `${where} · outside: ${rule.toLowerCase()}`;
}

/** Reads the setting row (RLS) and saves it as a settings.save op through sync_push. */
@Service({ factory: () => new SupabaseAttendanceRulesApi() })
export abstract class AttendanceRulesApi {
  /** The saved rules, or null when the arena has never saved any. */
  abstract load(arenaId: string): Promise<AttendanceRules | null>;
  abstract save(arenaId: string, rules: AttendanceRules): Promise<void>;
}

class SupabaseAttendanceRulesApi extends AttendanceRulesApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<AttendanceRules | null> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('settings')
      .select('json')
      .eq('arena_id', arenaId)
      .eq('key', 'attendance')
      .maybeSingle();
    if (error) throw dbError(error);
    return data ? parseAttendanceRules((data as { json: unknown }).json) : null;
  }

  async save(arenaId: string, rules: AttendanceRules): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'settings.save', payload: { key: 'attendance', json: attendanceJson(rules) } }],
      ATTENDANCE_RULE_MESSAGES,
    );
  }
}

/** The current arena's attendance rules; a save goes to the server first, then reloads. */
@Service()
export class AttendanceRulesStore {
  private readonly api = inject(AttendanceRulesApi);
  private readonly arena = inject(ArenaContext);

  /** What clock-ins use now (the defaults until the arena saves its own). */
  readonly rules = signal<AttendanceRules | null>(null);
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;
  private outOfDate = false;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.rules.set(null);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && !this.outOfDate && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.rules.set(null);
    this.outOfDate = false;
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const found = await this.api.load(arenaId);
      if (call !== this.latest) return;
      this.rules.set(found ?? DEFAULT_ATTENDANCE_RULES);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Marks the rules out of date without reading them (a live update nobody is looking at). */
  stale(): void {
    this.outOfDate = true;
  }

  /** Reads again if a screen has loaded the rules (live updates). */
  async refresh(): Promise<void> {
    if (this.loadedArena) await this.load(true);
  }

  async save(rules: AttendanceRules): Promise<void> {
    await this.api.save(this.arena.current().id, rules);
    await this.load(true);
  }
}
