import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { SyncOp } from '../../../core/sync/push-ops';
import { PayrollApi, PayrollOverview } from './payroll-api';
import {
  DeductionCode,
  NewAdjustmentKind,
  Period,
  RunDetail,
  adjustmentPayload,
  createRunPayload,
  lastFinalisedEnd,
  reversePayload,
  setDeductionPayload,
} from './payroll.models';

/**
 * The current arena's salary runs and the open run's lines and adjustments. Every action goes to
 * the server first; then the runs list and the open run are read again (the server recomputes
 * the lines). A broadcast of an applied `salary_run.*` / `salary_adjustment.*` / `pay_*` op
 * reloads it (RealtimeSync).
 */
@Service()
export class PayrollStore {
  private readonly api = inject(PayrollApi);
  private readonly arena = inject(ArenaContext);

  readonly overview = signal<PayrollOverview | null>(null);
  readonly runs = computed(() => this.overview()?.runs ?? []);
  readonly byId = computed(() => new Map(this.runs().map((r) => [r.id, r])));
  readonly finalisedEnd = computed(() => lastFinalisedEnd(this.runs()));
  readonly loading = signal(false);
  readonly loadError = signal('');

  /** The open run's id and its lines and adjustments (null while reading). */
  readonly detailId = signal<string | null>(null);
  readonly detail = signal<RunDetail | null>(null);
  readonly detailError = signal('');

  private loadedArena: string | null = null;
  private outOfDate = false;
  private detailOutOfDate = false;
  private latest = 0;
  private latestDetail = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.latestDetail++;
      this.loadedArena = null;
      this.overview.set(null);
      this.detailId.set(null);
      this.detail.set(null);
      this.loading.set(false);
      this.loadError.set('');
      this.detailError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && !this.outOfDate && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) {
      this.overview.set(null);
      this.detailId.set(null);
      this.detail.set(null);
    }
    this.outOfDate = false;
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const overview = await this.api.overview(arenaId);
      if (call !== this.latest) return;
      this.overview.set(overview);
      this.loadedArena = arenaId;
    } catch (e) {
      if (call === this.latest) this.loadError.set(toAppError(e).message);
    } finally {
      if (call === this.latest) this.loading.set(false);
    }
  }

  /** Reads a run's lines and adjustments (again when forced or another run). */
  async open(runId: string | null, force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!runId || !arenaId) {
      this.latestDetail++;
      this.detailId.set(null);
      this.detail.set(null);
      return;
    }
    if (!force && !this.detailOutOfDate && runId === this.detailId() && this.detail()) return;
    this.detailOutOfDate = false;
    if (runId !== this.detailId()) this.detail.set(null);
    this.detailId.set(runId);
    this.detailError.set('');
    const call = ++this.latestDetail;
    try {
      const detail = await this.api.detail(arenaId, runId);
      if (call === this.latestDetail) this.detail.set(detail);
    } catch (e) {
      if (call === this.latestDetail) this.detailError.set(toAppError(e).message);
    }
  }

  stale(): void {
    this.outOfDate = true;
    this.detailOutOfDate = true;
  }

  async refresh(): Promise<void> {
    if (this.loadedArena || this.loadError()) await this.load(true);
    if (this.detailId()) await this.open(this.detailId(), true);
  }

  /** A user's name in this arena, or "someone". */
  userName(userId: string | null): string {
    return (userId && this.overview()?.people.get(userId)) || 'someone';
  }

  private async send(op: SyncOp, runId: string | null): Promise<Record<string, unknown>> {
    const result = await this.api.send(this.arena.current().id, op);
    await this.load(true);
    if (runId && runId === this.detailId()) await this.open(runId, true);
    return result;
  }

  async create(id: string, period: Period): Promise<number> {
    const result = await this.send(
      { kind: 'salary_run.create', payload: createRunPayload(id, period) },
      null,
    );
    return Number(result['staff_count'] ?? 0);
  }

  async recalculate(runId: string): Promise<void> {
    await this.send({ kind: 'salary_run.recalculate', payload: { id: runId } }, runId);
  }

  async setDeduction(
    runId: string,
    staffId: string,
    code: DeductionCode,
    applied: boolean,
    note: string,
  ): Promise<void> {
    await this.send(
      {
        kind: 'salary_run.set_deduction',
        payload: setDeductionPayload(runId, staffId, code, applied, note),
      },
      runId,
    );
  }

  async addAdjustment(
    runId: string,
    staffId: string,
    kind: NewAdjustmentKind,
    amountPaise: number,
    note: string,
  ): Promise<void> {
    await this.send(
      {
        kind: 'salary_adjustment.add',
        payload: adjustmentPayload(crypto.randomUUID(), runId, staffId, kind, amountPaise, note),
      },
      runId,
    );
  }

  async reverse(runId: string, adjustmentId: string, note: string): Promise<void> {
    await this.send(
      {
        kind: 'salary_adjustment.reverse',
        payload: reversePayload(crypto.randomUUID(), adjustmentId, note),
      },
      runId,
    );
  }

  async finalise(runId: string): Promise<void> {
    await this.send({ kind: 'salary_run.finalise', payload: { id: runId } }, runId);
  }

  async discard(runId: string): Promise<void> {
    await this.send({ kind: 'salary_run.discard', payload: { id: runId } }, runId);
  }
}
