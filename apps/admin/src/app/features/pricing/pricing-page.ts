import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { Clock } from '../../core/time/clock';
import { formatIsoDate } from '../../shared/time/ist';
import { DetailPane } from '../../shared/list-detail/detail-pane';
import { DetailSection } from '../../shared/list-detail/detail-section';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { NotConnected } from '../../shared/not-connected/not-connected';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { HappyHourDetail } from './components/happy-hour-detail';
import { HolidaysDetail } from './components/holidays-detail';
import { TypeDetail } from './components/type-detail';
import { PricingStore } from './data/pricing-store';
import {
  StationType,
  formatHolidayDay,
  headlinePrice,
  maxPlayers,
  summarizeWindows,
  typeIcon,
} from './data/pricing.models';
import { TypeDialog, TypeDialogData, TypeDialogResult } from './dialogs/type-dialog';

const HAPPY = 'happy';
const HOLIDAYS = 'holidays';

/**
 * Pricing (design: `if (p === 'pricing')`) on the engine's model: station types with their
 * prices, and happy hour and holidays in place of the design's percentage rules. The selection is
 * in the URL (`?id=<type id>`, `?id=happy` or `?id=holidays`); on a wide screen the first entry
 * shows when none is chosen.
 */
@Component({
  selector: 'app-pricing-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    TypeDetail,
    HappyHourDetail,
    HolidaysDetail,
    NotConnected,
    DetailPane,
    DetailSection,
    MatButton,
    MatIcon,
    MatProgressBar,
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
            <button mat-stroked-button type="button" [disabled]="!arena.canEdit()" (click)="add()">
              <mat-icon aria-hidden="true">add</mat-icon>Type
            </button>
            <button
              mat-flat-button
              type="button"
              disabled
              aria-describedby="pricing-rules-note"
              title="Pricing rules aren't connected yet"
            >
              <mat-icon aria-hidden="true">add</mat-icon>Rule
            </button>
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
            <h2
              id="pricing-types"
              class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle"
            >
              Station types
            </h2>
            <ul class="flex flex-col gap-0.5">
              @for (t of store.types(); track t.id) {
                <li>
                  <app-list-row
                    [title]="t.name"
                    [subtitle]="typeSub(t)"
                    [icon]="icon(t)"
                    [selected]="t.id === selectedId()"
                    [queryParams]="{ id: t.id }"
                  >
                    @if (price(t); as p) {
                      <span class="text-sm leading-none font-semibold tabular-nums">{{
                        p.price
                      }}</span>
                      <span class="text-xs leading-none text-muted">{{ p.per }}</span>
                    } @else {
                      <app-status-pill tone="warning">No price</app-status-pill>
                    }
                  </app-list-row>
                </li>
              } @empty {
                <li class="px-3 py-4 text-sm leading-[1.45] text-muted">
                  @if (store.data()) {
                    No station types yet. Add what staff can start, e.g. PlayStation 5, VR or Pool,
                    then set its prices.
                  } @else if (!store.loading()) {
                    Not loaded.
                  }
                </li>
              }
            </ul>
          </section>
          <section aria-labelledby="pricing-rules">
            <h2
              id="pricing-rules"
              class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle"
            >
              Pricing rules
            </h2>
            <ul class="flex flex-col gap-0.5">
              @if (store.data()) {
                <li>
                  <app-list-row
                    title="Happy hour"
                    [subtitle]="happySummary() || 'Not set'"
                    icon="trending_down"
                    [selected]="selectedId() === happy"
                    [queryParams]="{ id: happy }"
                  >
                    <app-status-pill [tone]="happySummary() ? 'primary' : 'info'">{{
                      happySummary() ? 'On' : 'Off'
                    }}</app-status-pill>
                  </app-list-row>
                </li>
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
              } @else if (!store.loading()) {
                <li class="px-3 py-4 text-sm leading-[1.45] text-muted">Not loaded.</li>
              }
            </ul>
            <div class="px-3 py-3">
              <app-not-connected id="pricing-rules-note"
                >Percentage and flat-rate rules (weekends, holidays) can't be saved
                yet.</app-not-connected
              >
            </div>
          </section>
        </div>
      </ng-container>
      <ng-container detail>
        @if (failedWide()) {
          <!-- The design's type detail, with nothing in it: the price list did not load. -->
          <app-detail-pane
            crumb="Pricing"
            icon="sell"
            heading="Station type"
            subtitle="Not loaded"
            (closed)="close()"
          >
            <app-detail-section heading="Base rate">
              <p role="alert" class="text-[13px] leading-[1.45] text-danger">
                Prices couldn't load: {{ store.loadError() }}
              </p>
            </app-detail-section>
            <app-detail-section heading="With rules applied">
              <p class="text-[13px] leading-[1.45] text-muted">Not loaded.</p>
            </app-detail-section>
          </app-detail-pane>
        } @else if (selectedId() === happy && store.hours()) {
          <app-happy-hour-detail (closed)="close()" />
        } @else if (selectedId() === holidays && store.data()) {
          <app-holidays-detail (closed)="close()" />
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
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  /** `?id=` — a type id, `happy` or `holidays`. */
  readonly id = input<string>();

  protected readonly happy = HAPPY;
  protected readonly holidays = HOLIDAYS;
  protected readonly icon = typeIcon;
  protected readonly happySummary = computed(() =>
    summarizeWindows(this.store.hours()?.happy ?? {}),
  );
  /** Today in the arena (IST), "2026-10-13". */
  private readonly today = formatIsoDate(inject(Clock).now());
  protected readonly upcomingHolidays = computed(() =>
    this.store.holidays().filter((h) => h.day >= this.today),
  );
  protected readonly holidaySummary = computed(() => {
    const next = this.upcomingHolidays()[0];
    return next
      ? `Next: ${next.name} · ${formatHolidayDay(next.day)}`
      : 'No happy hour on these days';
  });
  protected readonly selectedId = computed<string | undefined>(() => {
    const id = this.id();
    if (id === HAPPY || id === HOLIDAYS || (id && this.store.byId().has(id))) return id;
    if (!this.layout.wideDetail() || !this.store.data()) return undefined;
    return this.store.types()[0]?.id ?? HAPPY;
  });
  /** Wide screen, price list failed: the detail side shows the empty type detail. */
  protected readonly failedWide = computed(
    () => !!this.store.loadError() && !this.store.data() && this.layout.wideDetail(),
  );
  protected readonly selectedType = computed(() => {
    const id = this.selectedId();
    return id && id !== HAPPY && id !== HOLIDAYS ? this.store.byId().get(id) : undefined;
  });

  constructor() {
    // Load (and reload on an arena switch) the current arena's price list.
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected typeSub(t: StationType): string {
    if (!t.active) return 'Off';
    const stations = `${t.stations} station${t.stations === 1 ? '' : 's'}`;
    const players = maxPlayers(t, this.store.rates());
    return players ? `${stations} · up to ${players} player${players === 1 ? '' : 's'}` : stations;
  }

  protected price(t: StationType) {
    return headlinePrice(t, this.store.rates());
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }

  protected add(): void {
    this.dialog
      .open<TypeDialog, TypeDialogData, TypeDialogResult>(TypeDialog, {
        data: {},
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        void this.router.navigate([], { queryParams: { id: result.id } });
      });
  }
}
