import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { Clock } from '../../../core/time/clock';
import { Attempt, writeThenReload } from '../../../core/sync/push-ops';
import { AttendanceApi } from './attendance-api';
import {
  AttendanceEntry,
  AttendanceLog,
  CorrectionPayload,
  LogRow,
  buildRows,
} from './attendance.models';

/** The IST days a log covers ("2026-10-07" … "2026-10-13", inclusive). */
export interface LogPeriod {
  readonly first: string;
  readonly last: string;
  /** Also superseded and voided rows ("Show voided/superseded"). */
  readonly withInactive?: boolean;
}

/**
 * The current arena's attendance log for one period of IST days (plus every entry still open),
 * and the reviewer's writes (correct, void, add, accept), each followed by a reload. A
 * broadcast of an applied `attendance.*` op reloads it (RealtimeSync).
 */
@Service()
export class AttendanceStore {
  private readonly api = inject(AttendanceApi);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);

  readonly log = signal<AttendanceLog | null>(null);
  readonly rows = computed<readonly LogRow[]>(() => {
    const log = this.log();
    return log ? buildRows(log) : [];
  });
  readonly byId = computed(() => new Map(this.rows().map((r) => [r.entry.id, r])));
  readonly staff = computed(() => this.log()?.staff ?? []);
  /** Rows read by id for correction chains (earlier versions not in the loaded period). */
  readonly extra = signal<ReadonlyMap<string, AttendanceEntry>>(new Map());
  readonly loading = signal(false);
  readonly loadError = signal('');
  /** When the log last came from the server (null before the first load). */
  readonly loadedAt = signal<Date | null>(null);
  private loadedKey: string | null = null;
  private outOfDate = false;
  private current: LogPeriod | null = null;
  private latest = 0;

  constructor() {
    // Sign-out or another login: the log leaves memory; a read in flight does not land.
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedKey = null;
      this.current = null;
      this.log.set(null);
      this.extra.set(new Map());
      this.loading.set(false);
      this.loadError.set('');
      this.loadedAt.set(null);
    });
  }

  async load(period: LogPeriod, force = false): Promise<void> {
    this.current = period;
    const arenaId = this.arena.current().id;
    if (!arenaId) return;
    const key = `${arenaId}|${period.first}|${period.last}|${period.withInactive ? 'all' : ''}`;
    if (!force && !this.outOfDate && key === this.loadedKey) return;
    const call = ++this.latest;
    if (this.loadedKey !== key) this.log.set(null);
    this.outOfDate = false;
    this.loadedKey = key;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const log = await this.api.load(
        arenaId,
        period.first,
        period.last,
        !!period.withInactive,
      );
      if (call === this.latest) {
        this.log.set(log);
        this.loadedAt.set(this.clock.now());
      }
    } catch (e) {
      if (call === this.latest) {
        this.loadError.set(toAppError(e).message);
        this.loadedKey = null;
      }
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Marks the log out of date without reading it (a live update while no screen shows it). */
  stale(): void {
    if (this.loadedKey) this.outOfDate = true;
  }

  /** A live update, the Refresh button or a reconnect: reads the open period again. */
  async refresh(): Promise<void> {
    if (this.current && (this.loadedKey || this.loadError())) {
      await this.load(this.current, true);
    }
  }

  /** An entry by id, whatever its status: from the log, else read once (correction chains). */
  entry(id: string): AttendanceEntry | undefined {
    return this.byId().get(id)?.entry ?? this.extra().get(id);
  }

  /** Reads entries not in the log (a correction's earlier rows); failures leave them unknown. */
  async fetchEntries(ids: readonly string[]): Promise<void> {
    const arenaId = this.arena.current().id;
    const missing = ids.filter((id) => !this.entry(id));
    if (!arenaId || !missing.length) return;
    try {
      const found = await this.api.entries(arenaId, missing);
      this.extra.update((m) => {
        const next = new Map(m);
        for (const e of found) next.set(e.id, e);
        return next;
      });
    } catch {
      // Not readable now: the detail says the earlier version could not be loaded.
    }
  }

  /** attendance.correct (edit, void or add); resolves with the resulting row's id. */
  async correct(payload: CorrectionPayload, attempt = new Attempt()): Promise<string> {
    const arenaId = this.arena.current().id;
    let id = '';
    await writeThenReload(
      async () => {
        id = await this.api.correct(arenaId, payload, attempt.id('op'));
      },
      () => this.refresh(),
    );
    return id;
  }

  /** attendance.review: accept a pending entry, with an optional note. */
  async review(entryId: string, note = ''): Promise<void> {
    const arenaId = this.arena.current().id;
    await writeThenReload(
      () => this.api.review(arenaId, entryId, note),
      () => this.refresh(),
    );
  }
}
