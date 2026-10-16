import { Service, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';

/**
 * The arena's leave rules (settings key `leave_rules`; docs/STAFF_API.md › Settings keys):
 * the paid allowance per leave year, whether half days may be asked for, and how far back
 * unplanned leave may go. The leave year starts on each person's joining date; unused days
 * don't carry over.
 */
export interface LeaveRules {
  /** 0–366 in steps of 0.5. */
  readonly paidLeaveDays: number;
  readonly halfDayAllowed: boolean;
  /** 0–31. */
  readonly unplannedBackdateDays: number;
}

/** What the server applies while the arena has saved none. */
export const DEFAULT_LEAVE_RULES: LeaveRules = {
  paidLeaveDays: 12,
  halfDayAllowed: true,
  unplannedBackdateDays: 7,
};

export const LEAVE_LIMITS = {
  paidLeaveDays: [0, 366],
  unplannedBackdateDays: [0, 31],
} as const;

export const LEAVE_RULE_MESSAGES: Readonly<Record<string, string>> = {
  invalid_leave_rules:
    'The server refused these leave rules: paid days 0–366 (whole or half), backdating 0–31 days',
  setting_not_shared: 'This server does not accept leave rules yet. Apply the latest migrations',
};

function halfStep(n: number): boolean {
  return Math.round(n * 2) === n * 2;
}

/** The saved json → rules; anything missing or out of range reads as the default. */
export function parseLeaveRules(json: unknown): LeaveRules {
  const j = (json ?? {}) as Record<string, unknown>;
  const d = DEFAULT_LEAVE_RULES;
  const paid = Number(j['paid_leave_days']);
  const back = Number(j['unplanned_backdate_days']);
  return {
    paidLeaveDays:
      Number.isFinite(paid) && paid >= 0 && paid <= 366 && halfStep(paid) ? paid : d.paidLeaveDays,
    halfDayAllowed:
      typeof j['half_day_allowed'] === 'boolean'
        ? (j['half_day_allowed'] as boolean)
        : d.halfDayAllowed,
    unplannedBackdateDays:
      Number.isInteger(back) && back >= 0 && back <= 31 ? back : d.unplannedBackdateDays,
  };
}

/** Rules → the `settings.save` json: the whole object, exactly the three keys. */
export function leaveRulesJson(r: LeaveRules): Record<string, unknown> {
  return {
    paid_leave_days: r.paidLeaveDays,
    half_day_allowed: r.halfDayAllowed,
    unplanned_backdate_days: r.unplannedBackdateDays,
  };
}

/** The settings screen's draft: numbers as typed. */
export interface LeaveRulesDraft {
  readonly paidLeaveDays: string;
  readonly halfDayAllowed: boolean;
  readonly unplannedBackdateDays: string;
}

export type LeaveRulesProblems = Partial<Record<'paidLeaveDays' | 'unplannedBackdateDays', string>>;

export function toLeaveDraft(r: LeaveRules): LeaveRulesDraft {
  return {
    paidLeaveDays: String(r.paidLeaveDays),
    halfDayAllowed: r.halfDayAllowed,
    unplannedBackdateDays: String(r.unplannedBackdateDays),
  };
}

function num(text: string): number {
  return text.trim() === '' ? Number.NaN : Number(text.trim());
}

export function leaveDraftProblems(d: LeaveRulesDraft): LeaveRulesProblems {
  const problems: LeaveRulesProblems = {};
  const paid = num(d.paidLeaveDays);
  if (!Number.isFinite(paid) || paid < 0 || paid > 366 || !halfStep(paid)) {
    problems.paidLeaveDays = 'Paid leave must be 0 to 366 days, in whole or half days';
  }
  const back = num(d.unplannedBackdateDays);
  if (!Number.isInteger(back) || back < 0 || back > 31) {
    problems.unplannedBackdateDays = 'Backdating must be a whole number of days from 0 to 31';
  }
  return problems;
}

export function fromLeaveDraft(d: LeaveRulesDraft): LeaveRules | null {
  if (Object.keys(leaveDraftProblems(d)).length) return null;
  return {
    paidLeaveDays: num(d.paidLeaveDays),
    halfDayAllowed: d.halfDayAllowed,
    unplannedBackdateDays: num(d.unplannedBackdateDays),
  };
}

export function sameLeaveDraft(a: LeaveRulesDraft, b: LeaveRulesDraft): boolean {
  const same = (x: string, y: string) => x.trim() === y.trim() || num(x) === num(y);
  return (
    same(a.paidLeaveDays, b.paidLeaveDays) &&
    a.halfDayAllowed === b.halfDayAllowed &&
    same(a.unplannedBackdateDays, b.unplannedBackdateDays)
  );
}

/** "12 paid days a year · half days allowed". */
export function leaveRulesSummary(r: LeaveRules): string {
  return `${r.paidLeaveDays} paid day${r.paidLeaveDays === 1 ? '' : 's'} a year · half days ${
    r.halfDayAllowed ? 'allowed' : 'off'
  }`;
}

/** Reads the setting row (RLS) and saves it as a settings.save op through sync_push. */
@Service({ factory: () => new SupabaseLeaveRulesApi() })
export abstract class LeaveRulesApi {
  /** The saved rules, or null when the arena has never saved any. */
  abstract load(arenaId: string): Promise<LeaveRules | null>;
  abstract save(arenaId: string, rules: LeaveRules): Promise<void>;
}

class SupabaseLeaveRulesApi extends LeaveRulesApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<LeaveRules | null> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('settings')
      .select('json')
      .eq('arena_id', arenaId)
      .eq('key', 'leave_rules')
      .maybeSingle();
    if (error) throw dbError(error);
    return data ? parseLeaveRules((data as { json: unknown }).json) : null;
  }

  async save(arenaId: string, rules: LeaveRules): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'settings.save', payload: { key: 'leave_rules', json: leaveRulesJson(rules) } }],
      LEAVE_RULE_MESSAGES,
    );
  }
}

/** The current arena's leave rules; a save goes to the server first, then reloads. */
@Service()
export class LeaveRulesStore {
  private readonly api = inject(LeaveRulesApi);
  private readonly arena = inject(ArenaContext);

  readonly rules = signal<LeaveRules | null>(null);
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
      this.rules.set(found ?? DEFAULT_LEAVE_RULES);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  stale(): void {
    this.outOfDate = true;
  }

  async refresh(): Promise<void> {
    if (this.loadedArena) await this.load(true);
  }

  async save(rules: LeaveRules): Promise<void> {
    await this.api.save(this.arena.current().id, rules);
    await this.load(true);
  }
}
