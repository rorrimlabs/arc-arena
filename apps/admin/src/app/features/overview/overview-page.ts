import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import { MatCard } from '@angular/material/card';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { FloorStore } from '../../core/floor/floor-store';
import { initials } from '../../core/floor/floor.models';
import { PageHeader } from '../../core/layout/page-header';
import { injectNow } from '../../core/time/ticker';
import { formatRupees } from '../../shared/money/rupees.pipe';
import { istDayStart } from '../../shared/time/ist';
import { PricingStore } from '../pricing/data/pricing-store';
import { LivePane } from './components/live-pane';
import { OverviewStore } from './data/overview-store';
import {
  PERIODS,
  Period,
  asPeriod,
  billedByType,
  byStaff,
  chartScale,
  delta,
  paymentRows,
  takingsBars,
  topGames,
  totals,
} from './data/overview.models';

/**
 * Overview (design: `isOverview`): the period's takings against the one before, a takings chart,
 * payment split, takings by station type, top games and staff, with the Live aside. All figures
 * come from closed bills (arena_sales) and billed lines; the period is in the URL (`?period=7d`).
 */
@Component({
  selector: 'app-overview-page',
  imports: [
    PageHeader,
    LivePane,
    MatButton,
    MatButtonToggleGroup,
    MatButtonToggle,
    MatCard,
    MatProgressBar,
  ],
  host: { class: 'flex min-h-full flex-wrap content-start' },
  template: `
    <div class="flex min-w-0 flex-[1_1_560px] flex-col">
      <app-page-header title="Overview">
        <mat-button-toggle-group
          class="arena-seg"
          aria-label="Period"
          [value]="period()"
          (change)="pick($event.value)"
        >
          @for (p of periods; track p.key) {
            <mat-button-toggle [value]="p.key">{{ p.label }}</mat-button-toggle>
          }
        </mat-button-toggle-group>
      </app-page-header>
      @if (store.loading()) {
        <mat-progress-bar mode="indeterminate" aria-label="Loading figures" />
      }
      <div class="flex flex-col gap-4 p-5">
        <p class="text-sm leading-[1.4] text-muted">{{ subtitle() }}</p>
        @if (store.loadError(); as error) {
          <div class="flex flex-col items-start gap-3">
            <p role="alert" class="text-sm text-danger">{{ error }}</p>
            <button mat-stroked-button type="button" (click)="store.load(period(), true)">
              Try again
            </button>
          </div>
        }

        <div class="grid grid-cols-[repeat(auto-fit,minmax(190px,1fr))] gap-4">
          @for (k of kpis(); track k.label) {
            <mat-card appearance="outlined">
              <div class="flex flex-col gap-2.5 px-5 py-4.5">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-sm leading-none font-medium text-muted">{{ k.label }}</span>
                  <span class="icon text-xl text-subtle" aria-hidden="true">{{ k.icon }}</span>
                </div>
                <span class="font-display text-[30px] leading-none font-bold tabular-nums">{{
                  k.value
                }}</span>
                <div class="flex flex-wrap items-center gap-2">
                  <span
                    class="inline-flex h-6 items-center rounded-[6px] px-2 text-xs leading-none font-semibold"
                    [class.bg-success-soft]="k.up === true"
                    [class.text-success]="k.up === true"
                    [class.bg-danger-soft]="k.up === false"
                    [class.text-danger]="k.up === false"
                    [class.bg-info-soft]="k.up === null"
                    [class.text-muted]="k.up === null"
                    >{{ k.delta }}</span
                  >
                  <span class="text-[13px] leading-[1.2] text-muted">{{ compare() }}</span>
                </div>
              </div>
            </mat-card>
          }
        </div>

        <mat-card appearance="outlined">
          <div class="flex flex-col gap-4 p-5">
            <div class="flex flex-col gap-1.5">
              <h2 class="text-base leading-[1.2] font-semibold">Takings</h2>
              <p class="text-[13px] leading-[1.3] text-muted">{{ chartSub() }}</p>
            </div>
            <div class="flex gap-2.5" role="img" [attr.aria-label]="chartLabel()">
              <div
                class="flex h-60 min-w-11 flex-col justify-between pb-5.5 text-right font-mono text-[11px] leading-none font-medium text-subtle"
                aria-hidden="true"
              >
                <span>{{ scale().top }}</span
                ><span>{{ scale().mid }}</span
                ><span>₹0</span>
              </div>
              <div class="flex min-w-0 flex-1 flex-col gap-2" aria-hidden="true">
                <div
                  class="flex h-[218px] items-end border-b border-border-strong bg-[linear-gradient(var(--arena-border)_1px,transparent_1px)] bg-[length:100%_50%]"
                  [class.gap-0.75]="bars().length > 20"
                  [class.gap-2]="bars().length <= 20"
                >
                  @for (b of bars(); track $index) {
                    <div class="flex h-full flex-1 items-end" [title]="b.tip">
                      <div
                        class="w-full rounded-t-[4px]"
                        [class.bg-primary]="!b.future"
                        [class.bg-border]="b.future"
                        [class.opacity-60]="b.future"
                        [style.height.%]="height(b.paise)"
                      ></div>
                    </div>
                  }
                </div>
                <div
                  class="flex"
                  [class.gap-0.75]="bars().length > 20"
                  [class.gap-2]="bars().length <= 20"
                >
                  @for (b of bars(); track $index) {
                    <span
                      class="min-w-0 flex-1 text-center font-mono text-[11px] leading-none font-medium whitespace-nowrap text-subtle"
                      >{{ b.label }}</span
                    >
                  }
                </div>
              </div>
            </div>
          </div>
        </mat-card>

        <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,280px),1fr))] gap-4">
          <mat-card appearance="outlined">
            <div class="flex flex-col gap-3.5 p-5">
              <h2 class="text-base leading-[1.2] font-semibold">Payment split</h2>
              <div
                class="flex h-3 gap-0.5 overflow-hidden rounded-[6px] bg-surface-sunken"
                role="img"
                [attr.aria-label]="'UPI ' + upiShare() + '% of takings'"
              >
                <div class="bg-primary" [style.width.%]="upiShare()"></div>
                @if (upiShare() < 100 && takings() > 0) {
                  <div class="flex-1 bg-subtle"></div>
                }
              </div>
              @for (p of payments(); track p.method) {
                <div class="flex items-center gap-2.5">
                  <span
                    class="size-2.5 rounded-[3px]"
                    [class.bg-primary]="p.method === 'upi'"
                    [class.bg-subtle]="p.method !== 'upi'"
                    aria-hidden="true"
                  ></span>
                  <span class="flex-1 text-sm leading-[1.2]">{{ p.label }}</span>
                  <span class="text-[13px] leading-none text-muted">{{ p.bills }} bills</span>
                  <span
                    class="min-w-20 text-right text-sm leading-none font-semibold tabular-nums"
                    >{{ rupees(p.paise) }}</span
                  >
                </div>
              }
              <div
                class="flex justify-between border-t border-border pt-3 text-[13px] leading-none text-muted"
              >
                <span>Discounts given</span>
                <span class="font-medium text-subtle" title="Discounts aren't recorded on bills yet"
                  >Not connected yet</span
                >
              </div>
            </div>
          </mat-card>

          <mat-card appearance="outlined">
            <div class="flex flex-col gap-3.5 p-5">
              <h2 class="text-base leading-[1.2] font-semibold">By station type</h2>
              @for (t of types(); track t.code) {
                <div class="flex flex-col gap-1.5">
                  <div class="flex justify-between text-sm leading-[1.2]">
                    <span>{{ t.name }}</span>
                    <span class="font-semibold tabular-nums">{{ rupees(t.paise) }}</span>
                  </div>
                  <div class="h-1.5 rounded-[3px] bg-surface-sunken" aria-hidden="true">
                    <div class="h-full rounded-[3px] bg-primary" [style.width.%]="t.share"></div>
                  </div>
                </div>
              } @empty {
                @if (pricing.loadError(); as error) {
                  <p role="alert" class="text-[13px] text-danger">
                    Station types couldn't load: {{ error }}
                  </p>
                } @else {
                  <p class="text-[13px] text-muted">No station types yet.</p>
                }
              }
            </div>
          </mat-card>

          <mat-card appearance="outlined">
            <div class="flex flex-col gap-1 p-5">
              <h2 class="pb-2 text-base leading-[1.2] font-semibold">Top games</h2>
              <ol class="flex flex-col gap-1">
                @for (g of games(); track g.name; let i = $index) {
                  <li class="flex min-h-9.5 items-center gap-3">
                    <span
                      class="w-5 font-mono text-[13px] leading-none font-semibold text-subtle"
                      >{{ i + 1 }}</span
                    >
                    <span class="min-w-0 flex-1 truncate text-sm leading-[1.2]">{{ g.name }}</span>
                    <span class="text-[13px] leading-none text-muted">{{ g.time }}</span>
                  </li>
                } @empty {
                  <li class="text-[13px] text-muted">No games played yet.</li>
                }
              </ol>
            </div>
          </mat-card>

          <mat-card appearance="outlined">
            <div class="flex flex-col gap-1 p-5">
              <h2 class="pb-2 text-base leading-[1.2] font-semibold">Staff</h2>
              <ul class="flex flex-col gap-1">
                @for (u of staff(); track u.name) {
                  <li class="flex min-h-11 items-center gap-3">
                    <span
                      class="grid size-8 flex-none place-items-center rounded-full bg-info-soft text-xs leading-none font-semibold"
                      aria-hidden="true"
                      >{{ initials(u.name) }}</span
                    >
                    <span class="flex min-w-0 flex-1 flex-col gap-0.75">
                      <span class="text-sm leading-[1.2] font-medium">{{ u.name }}</span>
                      <span class="text-xs leading-[1.2] text-muted">{{ u.bills }} bills</span>
                    </span>
                    <span class="text-sm leading-none font-semibold tabular-nums">{{
                      rupees(u.paise)
                    }}</span>
                  </li>
                } @empty {
                  <li class="text-[13px] text-muted">No bills yet.</li>
                }
              </ul>
            </div>
          </mat-card>
        </div>
      </div>
    </div>
    <app-live-pane [today]="today()" [now]="now()" />
  `,
})
export class OverviewPage {
  protected readonly store = inject(OverviewStore);
  private readonly floor = inject(FloorStore);
  protected readonly pricing = inject(PricingStore);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);

  /** `?period=` — today | 7d | 30d | 12m (default today). */
  readonly periodParam = input<string>(undefined, { alias: 'period' });

  protected readonly periods = PERIODS;
  protected readonly rupees = formatRupees;
  protected readonly initials = initials;
  protected readonly now = injectNow();
  protected readonly period = computed(() => asPeriod(this.periodParam()));

  private readonly current = computed(() => totals(this.store.bills()));
  private readonly before = computed(() => totals(this.store.previous()));
  protected readonly takings = computed(() => this.current().takingsPaise);
  protected readonly compare = computed(() => this.store.range()?.compare ?? '');
  protected readonly subtitle = computed(
    () => `${this.store.range()?.label ?? ''} · ${this.arena.current().name}`,
  );
  protected readonly kpis = computed(() => {
    const c = this.current();
    const p = this.before();
    const kpi = (label: string, icon: string, value: string, a: number, b: number) => ({
      label,
      icon,
      value,
      ...((d) => ({ delta: d.label, up: d.up }))(delta(a, b)),
    });
    return [
      kpi('Takings', 'payments', formatRupees(c.takingsPaise), c.takingsPaise, p.takingsPaise),
      kpi('Bills', 'receipt_long', c.bills.toLocaleString('en-IN'), c.bills, p.bills),
      kpi(
        'Hours played',
        'schedule',
        `${Math.round(c.minutes / 60).toLocaleString('en-IN')}h`,
        c.minutes,
        p.minutes,
      ),
      kpi(
        'Average bill',
        'functions',
        formatRupees(c.averagePaise),
        c.averagePaise,
        p.averagePaise,
      ),
    ];
  });

  protected readonly bars = computed(() => {
    const range = this.store.range();
    if (!range) return [];
    return takingsBars(
      this.period(),
      range,
      this.store.bills(),
      this.pricing.hours()?.open ?? null,
      this.now(),
    );
  });
  protected readonly scale = computed(() => chartScale(this.bars()));
  protected readonly chartSub = computed(
    () =>
      `${this.store.range()?.label ?? ''} · ${formatRupees(this.current().takingsPaise)} ${this.compare()} ${formatRupees(this.before().takingsPaise)}`,
  );
  protected readonly chartLabel = computed(
    () =>
      `Takings chart: ${this.bars()
        .map((b) => b.tip)
        .join(', ')}`,
  );

  protected readonly payments = computed(() => paymentRows(this.store.bills()));
  protected readonly upiShare = computed(() => {
    const t = this.takings();
    const upi = this.payments().find((p) => p.method === 'upi')?.paise ?? 0;
    return t > 0 ? Math.round((upi / t) * 100) : 0;
  });
  protected readonly types = computed(() => {
    const by = billedByType(this.store.charges());
    const rows = this.pricing
      .types()
      .filter((t) => t.active || by.has(t.code))
      .map((t) => ({ code: t.code, name: t.name, paise: by.get(t.code) ?? 0 }));
    const max = Math.max(1, ...rows.map((r) => r.paise));
    return rows.map((r) => ({ ...r, share: (r.paise / max) * 100 }));
  });
  protected readonly games = computed(() => topGames(this.store.bills()));
  protected readonly staff = computed(() => byStaff(this.store.bills()));
  /** Today's bills for the Live aside, whatever the period. */
  protected readonly today = computed(() => {
    const start = istDayStart(this.now()).getTime();
    return this.store.bills().filter((b) => Date.parse(b.at) >= start);
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load(this.period());
    });
    effect(() => {
      if (!this.arena.current().id) return;
      void this.floor.load(['stations', 'games', 'plays']);
      void this.pricing.load();
    });
  }

  protected height(paise: number): number {
    const top = this.scale().topPaise;
    return paise ? Math.max(1, (paise / top) * 100) : 0;
  }

  protected pick(period: Period): void {
    void this.router.navigate([], {
      queryParams: { period: period === 'today' ? null : period },
      queryParamsHandling: 'merge',
    });
  }
}
