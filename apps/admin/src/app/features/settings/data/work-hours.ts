import { Service, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import { formatMinutes } from '../../../shared/time/ist';

/**
 * The arena's working-hours rules (settings key `work_hours`, docs/STAFF_API.md): how late and
 * early are judged, when the shift break is taken off, rounding, the half-day and full-day
 * thresholds, the standard day and extra hours, the week start and the auto clock-out grace.
 * The whole object is saved; the server's defaults apply while no row exists.
 */
export type Rounding = 'exact' | 'nearest_15' | 'down_15';
export type ExtraBasis = 'day' | 'week';

export interface WorkHours {
  readonly lateGraceMin: number;
  readonly earlyLeaveMin: number;
  readonly breakAfterMin: number;
  readonly rounding: Rounding;
  readonly fullDayPct: number;
  readonly halfDayPct: number;
  readonly standardDayMin: number;
  readonly extraBasis: ExtraBasis;
  /** ISO weekday, 1 = Monday … 7 = Sunday. */
  readonly weekStart: number;
  readonly autoOutAfterMin: number;
}

/** What the server applies before an arena saves its own. */
export const DEFAULT_WORK_HOURS: WorkHours = {
  lateGraceMin: 10,
  earlyLeaveMin: 15,
  breakAfterMin: 300,
  rounding: 'exact',
  fullDayPct: 75,
  halfDayPct: 40,
  standardDayMin: 480,
  extraBasis: 'day',
  weekStart: 1,
  autoOutAfterMin: 120,
};

/** The server's ranges, inclusive (full day must also be above half day). */
export const WORK_HOURS_LIMITS = {
  lateGraceMin: [0, 120],
  earlyLeaveMin: [0, 240],
  breakAfterMin: [0, 1440],
  fullDayPct: [1, 100],
  halfDayPct: [1, 99],
  standardDayMin: [60, 1440],
  weekStart: [1, 7],
  autoOutAfterMin: [0, 720],
} as const;

export const ROUNDINGS: readonly { value: Rounding; label: string; sub: string }[] = [
  { value: 'exact', label: 'Exact', sub: 'Count every minute worked.' },
  {
    value: 'nearest_15',
    label: 'Nearest 15 minutes',
    sub: 'A day of 7h 52m counts as 7h 45m; 7h 53m counts as 8h.',
  },
  {
    value: 'down_15',
    label: 'Round down to 15 minutes',
    sub: 'A day of 7h 59m counts as 7h 45m.',
  },
];

export const EXTRA_BASES: readonly { value: ExtraBasis; label: string; sub: string }[] = [
  { value: 'day', label: 'Per day', sub: 'Time beyond the standard day, each working day.' },
  {
    value: 'week',
    label: 'Per week',
    sub: 'Time beyond the week’s standard days added up, so a short day evens out a long one.',
  },
];

export const WEEKDAYS: readonly { value: number; label: string; short: string }[] = [
  { value: 1, label: 'Monday', short: 'Mon' },
  { value: 2, label: 'Tuesday', short: 'Tue' },
  { value: 3, label: 'Wednesday', short: 'Wed' },
  { value: 4, label: 'Thursday', short: 'Thu' },
  { value: 5, label: 'Friday', short: 'Fri' },
  { value: 6, label: 'Saturday', short: 'Sat' },
  { value: 7, label: 'Sunday', short: 'Sun' },
];

export const WORK_HOURS_MESSAGES: Readonly<Record<string, string>> = {
  invalid_work_hours: 'The server refused these working hours: check the values marked above',
  forbidden: 'You need the Settings permission for that',
};

function oneOf<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

function intIn(value: unknown, [min, max]: readonly [number, number], fallback: number): number {
  const n = Number(value);
  return value !== null && value !== '' && Number.isInteger(n) && n >= min && n <= max
    ? n
    : fallback;
}

/** The saved json → rules; anything missing or out of range reads as the default. */
export function parseWorkHours(json: unknown): WorkHours {
  const j = (json ?? {}) as Record<string, unknown>;
  const d = DEFAULT_WORK_HOURS;
  const L = WORK_HOURS_LIMITS;
  const full = intIn(j['full_day_pct'], L.fullDayPct, d.fullDayPct);
  const half = intIn(j['half_day_pct'], L.halfDayPct, d.halfDayPct);
  const pcts = half < full ? { full, half } : { full: d.fullDayPct, half: d.halfDayPct };
  return {
    lateGraceMin: intIn(j['late_grace_min'], L.lateGraceMin, d.lateGraceMin),
    earlyLeaveMin: intIn(j['early_leave_min'], L.earlyLeaveMin, d.earlyLeaveMin),
    breakAfterMin: intIn(j['break_after_min'], L.breakAfterMin, d.breakAfterMin),
    rounding: oneOf(j['rounding'], ['exact', 'nearest_15', 'down_15'], d.rounding),
    fullDayPct: pcts.full,
    halfDayPct: pcts.half,
    standardDayMin: intIn(j['standard_day_min'], L.standardDayMin, d.standardDayMin),
    extraBasis: oneOf(j['extra_basis'], ['day', 'week'], d.extraBasis),
    weekStart: intIn(j['week_start'], L.weekStart, d.weekStart),
    autoOutAfterMin: intIn(j['auto_out_after_min'], L.autoOutAfterMin, d.autoOutAfterMin),
  };
}

/** Rules → the `settings.save` json: exactly the ten keys the server requires. */
export function workHoursJson(w: WorkHours): Record<string, unknown> {
  return {
    late_grace_min: w.lateGraceMin,
    early_leave_min: w.earlyLeaveMin,
    break_after_min: w.breakAfterMin,
    rounding: w.rounding,
    full_day_pct: w.fullDayPct,
    half_day_pct: w.halfDayPct,
    standard_day_min: w.standardDayMin,
    extra_basis: w.extraBasis,
    week_start: w.weekStart,
    auto_out_after_min: w.autoOutAfterMin,
  };
}

/** The settings screen's draft: numbers as typed; the standard day as hours + minutes. */
export interface WorkHoursDraft {
  readonly lateGrace: string;
  readonly earlyLeave: string;
  readonly breakAfter: string;
  readonly rounding: Rounding;
  readonly fullDayPct: string;
  readonly halfDayPct: string;
  readonly standardHours: string;
  readonly standardMinutes: string;
  readonly extraBasis: ExtraBasis;
  readonly weekStart: number;
  readonly autoOutAfter: string;
}

export type WorkHoursField =
  | 'lateGrace'
  | 'earlyLeave'
  | 'breakAfter'
  | 'fullDayPct'
  | 'halfDayPct'
  | 'standardDay'
  | 'autoOutAfter';
export type WorkHoursProblems = Partial<Record<WorkHoursField, string>>;

export function toWorkHoursDraft(w: WorkHours): WorkHoursDraft {
  return {
    lateGrace: String(w.lateGraceMin),
    earlyLeave: String(w.earlyLeaveMin),
    breakAfter: String(w.breakAfterMin),
    rounding: w.rounding,
    fullDayPct: String(w.fullDayPct),
    halfDayPct: String(w.halfDayPct),
    standardHours: String(Math.floor(w.standardDayMin / 60)),
    standardMinutes: String(w.standardDayMin % 60),
    extraBasis: w.extraBasis,
    weekStart: w.weekStart,
    autoOutAfter: String(w.autoOutAfterMin),
  };
}

function num(text: string): number {
  return text.trim() === '' ? Number.NaN : Number(text.trim());
}

function wholeIn(text: string, [min, max]: readonly [number, number]): boolean {
  const n = num(text);
  return Number.isInteger(n) && n >= min && n <= max;
}

/** The standard day typed as hours + minutes, in minutes; NaN when either is not whole. */
export function draftStandardDay(d: WorkHoursDraft): number {
  const h = d.standardHours.trim() === '' ? 0 : num(d.standardHours);
  const m = d.standardMinutes.trim() === '' ? 0 : num(d.standardMinutes);
  if (!Number.isInteger(h) || !Number.isInteger(m) || h < 0 || m < 0 || m > 59) return Number.NaN;
  return h * 60 + m;
}

/** What the server would refuse in a draft, per field, in plain words; empty when none. */
export function workHoursProblems(d: WorkHoursDraft): WorkHoursProblems {
  const L = WORK_HOURS_LIMITS;
  const p: WorkHoursProblems = {};
  const minutes = (field: WorkHoursField, text: string, range: readonly [number, number], what: string) => {
    if (!wholeIn(text, range)) {
      p[field] = `${what} must be a whole number of minutes from ${range[0]} to ${range[1]}`;
    }
  };
  minutes('lateGrace', d.lateGrace, L.lateGraceMin, 'Late grace');
  minutes('earlyLeave', d.earlyLeave, L.earlyLeaveMin, 'Early leave');
  minutes('breakAfter', d.breakAfter, L.breakAfterMin, 'Break after');
  minutes('autoOutAfter', d.autoOutAfter, L.autoOutAfterMin, 'Auto clock-out grace');
  if (!wholeIn(d.fullDayPct, L.fullDayPct)) {
    p.fullDayPct = 'Full day must be a whole percentage from 1 to 100';
  }
  if (!wholeIn(d.halfDayPct, L.halfDayPct)) {
    p.halfDayPct = 'Half day must be a whole percentage from 1 to 99';
  } else if (!p.fullDayPct && num(d.halfDayPct) >= num(d.fullDayPct)) {
    p.halfDayPct = 'Half day must be less than full day';
  }
  const std = draftStandardDay(d);
  const [min, max] = L.standardDayMin;
  if (!Number.isFinite(std) || std < min || std > max) {
    p.standardDay = 'The standard day must be from 1 hour to 24 hours (minutes 0–59)';
  }
  return p;
}

/** A valid draft → rules; null when the draft has a problem (workHoursProblems says which). */
export function fromWorkHoursDraft(d: WorkHoursDraft): WorkHours | null {
  if (Object.keys(workHoursProblems(d)).length) return null;
  return {
    lateGraceMin: num(d.lateGrace),
    earlyLeaveMin: num(d.earlyLeave),
    breakAfterMin: num(d.breakAfter),
    rounding: d.rounding,
    fullDayPct: num(d.fullDayPct),
    halfDayPct: num(d.halfDayPct),
    standardDayMin: draftStandardDay(d),
    extraBasis: d.extraBasis,
    weekStart: d.weekStart,
    autoOutAfterMin: num(d.autoOutAfter),
  };
}

/** Two drafts say the same thing (numbers compared as numbers: "8" h "0" m matches "8" h ""). */
export function sameWorkHoursDraft(a: WorkHoursDraft, b: WorkHoursDraft): boolean {
  const same = (x: string, y: string) => x.trim() === y.trim() || num(x) === num(y);
  const stdA = draftStandardDay(a);
  const stdB = draftStandardDay(b);
  return (
    same(a.lateGrace, b.lateGrace) &&
    same(a.earlyLeave, b.earlyLeave) &&
    same(a.breakAfter, b.breakAfter) &&
    a.rounding === b.rounding &&
    same(a.fullDayPct, b.fullDayPct) &&
    same(a.halfDayPct, b.halfDayPct) &&
    (stdA === stdB ||
      (a.standardHours.trim() === b.standardHours.trim() &&
        a.standardMinutes.trim() === b.standardMinutes.trim())) &&
    a.extraBasis === b.extraBasis &&
    a.weekStart === b.weekStart &&
    same(a.autoOutAfter, b.autoOutAfter)
  );
}

/** "8h standard day · 10 min late grace" — the section's one-line summary. */
export function workHoursSummary(w: WorkHours): string {
  return `${formatMinutes(w.standardDayMin)} standard day · ${w.lateGraceMin} min late grace`;
}

/** Reads the setting row (RLS) and saves it as a settings.save op through sync_push. */
@Service({ factory: () => new SupabaseWorkHoursApi() })
export abstract class WorkHoursApi {
  /** The saved rules, or null when the arena has never saved any. */
  abstract load(arenaId: string): Promise<WorkHours | null>;
  abstract save(arenaId: string, rules: WorkHours): Promise<void>;
}

class SupabaseWorkHoursApi extends WorkHoursApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<WorkHours | null> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('settings')
      .select('json')
      .eq('arena_id', arenaId)
      .eq('key', 'work_hours')
      .maybeSingle();
    if (error) throw dbError(error);
    return data ? parseWorkHours((data as { json: unknown }).json) : null;
  }

  async save(arenaId: string, rules: WorkHours): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'settings.save', payload: { key: 'work_hours', json: workHoursJson(rules) } }],
      WORK_HOURS_MESSAGES,
    );
  }
}

/** The current arena's working-hours rules; a save goes to the server first, then reloads. */
@Service()
export class WorkHoursStore {
  private readonly api = inject(WorkHoursApi);
  private readonly arena = inject(ArenaContext);

  /** What the server uses now (the defaults until the arena saves its own). */
  readonly rules = signal<WorkHours | null>(null);
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
      this.rules.set(found ?? DEFAULT_WORK_HOURS);
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

  async save(rules: WorkHours): Promise<void> {
    await this.api.save(this.arena.current().id, rules);
    await this.load(true);
  }
}
