import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatMenu, MatMenuItem, MatMenuTrigger } from '@angular/material/menu';
import { Router, RouterLink } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { Clock } from '../../core/time/clock';
import { formatDate, formatIsoDate } from '../../shared/time/ist';
import { DetailPane } from '../../shared/list-detail/detail-pane';
import { DetailSection } from '../../shared/list-detail/detail-section';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { DiscountDetail } from './components/discount-detail';
import { COUPON_STATE } from './components/discount-state';
import { HolidaysDetail } from './components/holidays-detail';
import { RuleDetail } from './components/rule-detail';
import { TypeDetail } from './components/type-detail';
import { PricingStore } from './data/pricing-store';
import {
  Discount,
  PricingRule,
  StationType,
  adjustLabel,
  discountState,
  discountValueLabel,
  formatHolidayDay,
  headlinePrice,
  maxPlayers,
  ruleWhen,
  typeIcon,
} from './data/pricing.models';

const HOLIDAYS = 'holidays';
const NEW_RULE = 'new-rule';
const NEW_DISCOUNT = 'new-discount';
const NEW_COUPON = 'new-coupon';

/**
 * Pricing: each station type's prices, the owner's day/time rules that change them (in the order
 * they are tried; happy hours are one of them), holidays, preset discounts and coupons. Station
 * types themselves are managed in Settings. The selection is in the URL (`?id=<type, rule or
 * discount id>`, `holidays`, `new-rule`, `new-discount`, `new-coupon`); on a wide screen the
 * first type shows when none is chosen.
 */
@Component({
  selector: 'app-pricing-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    TypeDetail,
    HolidaysDetail,
    RuleDetail,
    DiscountDetail,
    DetailPane,
    DetailSection,
    MatButton,
    MatIcon,
    MatMenu,
    MatMenuItem,
    MatMenuTrigger,
    MatProgressBar,
    RouterLink,
  ],
  template: `
    <app-list-detail
      listLabel="Pricing"
      detailLabel="Price details"
      [open]="!!selectedId() || failedWide()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Pricing">
          <div actions class="flex gap-2">
            <button
              mat-flat-button
              type="button"
              [disabled]="!arena.canEdit() || !store.data()"
              [matMenuTriggerFor]="addMenu"
            >
              <mat-icon aria-hidden="true">add</mat-icon>Add
            </button>
            <mat-menu #addMenu="matMenu">
              <button mat-menu-item type="button" (click)="open(newRule)">
                <mat-icon aria-hidden="true">schedule</mat-icon>Time rule
              </button>
              <button mat-menu-item type="button" (click)="open(newDiscount)">
                <mat-icon aria-hidden="true">percent</mat-icon>Discount
              </button>
              <button mat-menu-item type="button" (click)="open(newCoupon)">
                <mat-icon aria-hidden="true">confirmation_number</mat-icon>Coupon
              </button>
            </mat-menu>
          </div>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading prices" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-start gap-3 px-3 pt-3 pb-1">
              <p role="alert" class="text-sm leading-[1.4] text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(true)">Try again</button>
            </div>
          }
          <section aria-labelledby="pricing-types">
            <h2 id="pricing-types" class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle">
              Prices
            </h2>
            <ul class="flex flex-col gap-0.5">
              @for (t of priced(); track t.id) {
                <li>
                  <app-list-row
                    [title]="t.name"
                    [subtitle]="typeSub(t)"
                    [icon]="icon(t)"
                    [selected]="t.id === selectedId()"
                    [queryParams]="{ id: t.id }"
                  >
                    @if (price(t); as p) {
                      <span class="text-sm leading-none font-semibold tabular-nums">{{ p.price }}</span>
                      <span class="text-xs leading-none text-muted">{{ p.per }}</span>
                    } @else {
                      <app-status-pill tone="warning">No price</app-status-pill>
                    }
                  </app-list-row>
                </li>
              } @empty {
                <li class="px-3 py-4 text-sm leading-[1.45] text-muted">
                  @if (store.data()) {
                    No station types yet.
                    <a routerLink="/settings/types">Add them in Settings</a>,
                    then set their prices here.
                  } @else if (!store.loading()) {
                    Not loaded.
                  }
                </li>
              }
            </ul>
          </section>
          @if (store.data()) {
            <section aria-labelledby="pricing-rules">
              <h2 id="pricing-rules" class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle">
                Time rules
              </h2>
              <ul class="flex flex-col gap-0.5">
                @for (r of store.rules(); track r.id; let i = $index) {
                  <li>
                    <app-list-row
                      [title]="i + 1 + '. ' + r.name"
                      [subtitle]="ruleSub(r)"
                      icon="schedule"
                      [selected]="r.id === selectedId()"
                      [queryParams]="{ id: r.id }"
                    >
                      <app-status-pill [tone]="r.active ? 'primary' : 'info'">{{
                        r.active ? adjust(r) : 'Off'
                      }}</app-status-pill>
                    </app-list-row>
                  </li>
                } @empty {
                  <li class="px-3 py-2 text-[13px] leading-[1.45] text-muted">
                    None yet. Rules change prices by day and time.
                  </li>
                }
              </ul>
              <p class="px-3 pt-2 pb-1 text-[13px] leading-[1.45] text-muted">
                Happy hours: add a rule, e.g. Tue–Fri 2–5 PM, 20% lower.
              </p>
            </section>
            <section aria-labelledby="pricing-holidays">
              <h2 id="pricing-holidays" class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle">
                Holidays
              </h2>
              <ul class="flex flex-col gap-0.5">
                <li>
                  <app-list-row
                    title="Holidays"
                    [subtitle]="holidaySummary()"
                    icon="event_busy"
                    [selected]="selectedId() === holidays"
                    [queryParams]="{ id: holidays }"
                  >
                    <app-status-pill [tone]="upcomingHolidays().length ? 'primary' : 'info'">{{
                      upcomingHolidays().length ? upcomingHolidays().length + ' coming up' : 'None'
                    }}</app-status-pill>
                  </app-list-row>
                </li>
              </ul>
            </section>
            @for (group of discountGroups(); track group.key) {
              <section [attr.aria-labelledby]="'pricing-' + group.key">
                <h2
                  [id]="'pricing-' + group.key"
                  class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle"
                >
                  {{ group.title }}
                </h2>
                <ul class="flex flex-col gap-0.5">
                  @for (d of group.items; track d.id) {
                    <li>
                      <app-list-row
                        [title]="d.kind === 'coupon' ? (d.code ?? d.name) : d.name"
                        [subtitle]="discountSub(d)"
                        [icon]="d.kind === 'coupon' ? 'confirmation_number' : 'percent'"
                        [selected]="d.id === selectedId()"
                        [queryParams]="{ id: d.id }"
                      >
                        <app-status-pill [tone]="state(d).tone">{{ state(d).label }}</app-status-pill>
                      </app-list-row>
                    </li>
                  } @empty {
                    <li class="px-3 py-2 text-[13px] leading-[1.45] text-muted">{{ group.empty }}</li>
                  }
                </ul>
              </section>
            }
          } @else if (!store.loading()) {
            <p class="px-3 py-4 text-sm leading-[1.45] text-muted">Not loaded.</p>
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (failedWide()) {
          <app-detail-pane
            crumb="Pricing"
            icon="sell"
            heading="Prices"
            subtitle="Not loaded"
            (closed)="close()"
          >
            <app-detail-section heading="Base price">
              <p role="alert" class="text-[13px] leading-[1.45] text-danger">
                Prices couldn't load: {{ store.loadError() }}
              </p>
            </app-detail-section>
          </app-detail-pane>
        } @else if (selectedId() === holidays && store.data()) {
          <app-holidays-detail (closed)="close()" />
        } @else if (selectedId() === newRule) {
          <app-rule-detail [rule]="null" (closed)="close()" (created)="open($event)" />
        } @else if (selectedRule(); as r) {
          <app-rule-detail [rule]="r" (closed)="close()" />
        } @else if (selectedId() === newDiscount || selectedId() === newCoupon) {
          <app-discount-detail
            [discount]="null"
            [kind]="selectedId() === newCoupon ? 'coupon' : 'preset'"
            (closed)="close()"
            (created)="open($event)"
          />
        } @else if (selectedDiscount(); as d) {
          <app-discount-detail [discount]="d" (closed)="close()" />
        } @else if (selectedType(); as t) {
          <app-type-detail [type]="t" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class PricingPage {
  protected readonly store = inject(PricingStore);
  protected readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly now = inject(Clock).now();

  /** `?id=` — a type, rule or discount id, `holidays` or a `new-…` form. */
  readonly id = input<string>();

  protected readonly holidays = HOLIDAYS;
  protected readonly newRule = NEW_RULE;
  protected readonly newDiscount = NEW_DISCOUNT;
  protected readonly newCoupon = NEW_COUPON;
  protected readonly icon = typeIcon;
  protected readonly adjust = adjustLabel;
  /** Enabled types are priced here; turned-off ones live in Settings. */
  protected readonly priced = computed(() => this.store.types().filter((t) => t.active));
  /** Today in the arena (IST), "2026-10-13". */
  private readonly today = formatIsoDate(this.now);
  protected readonly upcomingHolidays = computed(() =>
    this.store.holidays().filter((h) => h.day >= this.today),
  );
  protected readonly holidaySummary = computed(() => {
    const next = this.upcomingHolidays()[0];
    return next
      ? `Next: ${next.name} · ${formatHolidayDay(next.day)}`
      : 'Special days and closures';
  });
  protected readonly discountGroups = computed(() => [
    {
      key: 'discounts',
      title: 'Discounts',
      empty: 'None yet. Add ones staff can pick at checkout, e.g. Student 10%.',
      items: this.store.discounts().filter((d) => d.kind === 'preset'),
    },
    {
      key: 'coupons',
      title: 'Coupons',
      empty: 'None yet. Add a code customers can bring, with an expiry.',
      items: this.store.discounts().filter((d) => d.kind === 'coupon'),
    },
  ]);
  private readonly ruleById = computed(() => new Map(this.store.rules().map((r) => [r.id, r])));
  private readonly discountById = computed(
    () => new Map(this.store.discounts().map((d) => [d.id, d])),
  );
  protected readonly selectedId = computed<string | undefined>(() => {
    const id = this.id();
    const fixed = [HOLIDAYS, NEW_RULE, NEW_DISCOUNT, NEW_COUPON];
    if (id && (fixed.includes(id) || this.store.byId().has(id) || this.ruleById().has(id) ||
        this.discountById().has(id))) {
      return id;
    }
    if (!this.layout.wideDetail() || !this.store.data()) return undefined;
    return this.priced()[0]?.id ?? HOLIDAYS;
  });
  /** Wide screen, price list failed: the detail side says so. */
  protected readonly failedWide = computed(
    () => !!this.store.loadError() && !this.store.data() && this.layout.wideDetail(),
  );
  protected readonly selectedType = computed(() => {
    const id = this.selectedId();
    return id ? this.store.byId().get(id) : undefined;
  });
  protected readonly selectedRule = computed(() => {
    const id = this.selectedId();
    return id ? this.ruleById().get(id) : undefined;
  });
  protected readonly selectedDiscount = computed(() => {
    const id = this.selectedId();
    return id ? this.discountById().get(id) : undefined;
  });

  constructor() {
    // Load (and reload on an arena switch) the current arena's price list.
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected typeSub(t: StationType): string {
    const stations = `${t.stations} station${t.stations === 1 ? '' : 's'}`;
    const players = maxPlayers(t, this.store.rates());
    return players ? `${stations} · up to ${players} player${players === 1 ? '' : 's'}` : stations;
  }

  protected price(t: StationType) {
    return headlinePrice(t, this.store.rates());
  }

  protected ruleSub(r: PricingRule): string {
    const scope = r.activityCodes.length
      ? r.activityCodes
          .map((c) => this.store.types().find((t) => t.code === c)?.name ?? c)
          .join(', ')
      : 'All types';
    return `${ruleWhen(r)} · ${scope}`;
  }

  protected discountSub(d: Discount): string {
    const until = d.validUntil ? ` · until ${formatDate(d.validUntil)}` : '';
    return d.kind === 'coupon'
      ? `${d.name} · ${discountValueLabel(d)}${until}`
      : `${discountValueLabel(d)}${until}`;
  }

  protected state(d: Discount) {
    return COUPON_STATE[discountState(d, this.now)];
  }

  protected open(id: string): void {
    void this.router.navigate([], { queryParams: { id } });
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }
}
