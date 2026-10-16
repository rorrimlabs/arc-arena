import { Service, computed, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { LoginScope } from '../../../core/auth/login-scope';
import { PayPolicy, payPolicyPayload } from '../../payroll/data/pay-policy';
import { PaySetupApi } from './pay-setup-api';
import { HrDraft, PaySetupData, RateDraft, hrPayload, ratePayload } from './pay-setup.models';

/**
 * The current arena's pay setup: staff, HR profiles, pay rates and pay rules. A write goes to
 * the server first, then everything is read again. A broadcast of an applied `hr_profile.*`,
 * `pay_rate.*`, `pay_policy.*` or `salary_run.*` op reloads it (RealtimeSync).
 */
@Service()
export class PaySetupStore {
  private readonly api = inject(PaySetupApi);
  private readonly arena = inject(ArenaContext);

  readonly data = signal<PaySetupData | null>(null);
  readonly loading = signal(false);
  readonly loadError = signal('');
  readonly staff = computed(() => this.data()?.staff ?? []);
  readonly profileOf = computed(
    () => new Map((this.data()?.profiles ?? []).map((p) => [p.staffId, p])),
  );
  readonly policies = computed(() =>
    [...(this.data()?.policies ?? [])].sort((a, b) =>
      b.effectiveFrom.localeCompare(a.effectiveFrom),
    ),
  );
  readonly nameOfUser = computed(() => new Map(this.staff().map((s) => [s.userId, s.name])));

  private loadedArena: string | null = null;
  private outOfDate = false;
  private latest = 0;

  constructor() {
    inject(LoginScope).onEnd(() => {
      this.latest++;
      this.loadedArena = null;
      this.data.set(null);
      this.loading.set(false);
      this.loadError.set('');
    });
  }

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && !this.outOfDate && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.data.set(null);
    this.outOfDate = false;
    const call = ++this.latest;
    this.loading.set(true);
    this.loadError.set('');
    try {
      const data = await this.api.load(arenaId);
      if (call !== this.latest) return;
      this.data.set(data);
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
    if (this.loadedArena || this.loadError()) await this.load(true);
  }

  ratesOf(staffId: string) {
    return (this.data()?.rates ?? [])
      .filter((r) => r.staffId === staffId)
      .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom));
  }

  userName(userId: string | null): string {
    return (userId && this.nameOfUser().get(userId)) || 'someone';
  }

  async saveProfile(staffId: string, draft: HrDraft): Promise<void> {
    await this.api.send(this.arena.current().id, {
      kind: 'hr_profile.save',
      payload: hrPayload(staffId, draft),
    });
    await this.load(true);
  }

  async addRate(staffId: string, draft: RateDraft): Promise<void> {
    await this.api.send(this.arena.current().id, {
      kind: 'pay_rate.add',
      payload: ratePayload(crypto.randomUUID(), staffId, draft),
    });
    await this.load(true);
  }

  async addPolicy(effectiveFrom: string, policy: PayPolicy): Promise<void> {
    await this.api.send(this.arena.current().id, {
      kind: 'pay_policy.add',
      payload: payPolicyPayload(crypto.randomUUID(), effectiveFrom, policy),
    });
    await this.load(true);
  }
}
