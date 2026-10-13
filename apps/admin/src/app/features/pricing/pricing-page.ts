import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { HappyHourDetail } from './components/happy-hour-detail';
import { TypeDetail } from './components/type-detail';
import { PricingStore } from './data/pricing-store';
import {
  StationType,
  headlinePrice,
  maxPlayers,
  summarizeWindows,
  typeIcon,
} from './data/pricing.models';
import { TypeDialog, TypeDialogData, TypeDialogResult } from './dialogs/type-dialog';

const HAPPY = 'happy';

/**
 * Pricing (design: `if (p === 'pricing')`) on the engine's model: station types with their
 * prices, and happy hour in place of the design's percentage rules. The selection is in the URL
 * (`?id=<type id>` or `?id=happy`); on a wide screen the first entry shows when none is chosen.
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
    MatButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Pricing"
      detailLabel="Price details"
      [open]="!!selectedId()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Pricing">
          <button actions mat-flat-button type="button" (click)="add()">
            <mat-icon aria-hidden="true">add</mat-icon>Add type
          </button>
          <p class="text-[13px] leading-[1.3] text-muted">
            What staff can start, what it costs, and when happy hour runs.
          </p>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading prices" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(true)">Try again</button>
            </div>
          } @else if (store.data()) {
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
                    No station types yet. Add what staff can start, e.g. PlayStation 5, VR or Pool,
                    then set its prices.
                  </li>
                }
              </ul>
            </section>
            <section aria-labelledby="pricing-happy">
              <h2
                id="pricing-happy"
                class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle"
              >
                Happy hour
              </h2>
              <ul>
                <li>
                  <app-list-row
                    title="Happy hour"
                    [subtitle]="happySummary() || 'Not set'"
                    icon="schedule"
                    [selected]="selectedId() === happy"
                    [queryParams]="{ id: happy }"
                  >
                    <app-status-pill [tone]="happySummary() ? 'primary' : 'info'">{{
                      happySummary() ? 'On' : 'Off'
                    }}</app-status-pill>
                  </app-list-row>
                </li>
              </ul>
            </section>
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selectedId() === happy && store.hours()) {
          <app-happy-hour-detail (closed)="close()" />
        } @else if (selectedType(); as t) {
          <app-type-detail [type]="t" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class PricingPage {
  protected readonly store = inject(PricingStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  /** `?id=` — a type id, or `happy`. */
  readonly id = input<string>();

  protected readonly happy = HAPPY;
  protected readonly icon = typeIcon;
  protected readonly happySummary = computed(() =>
    summarizeWindows(this.store.hours()?.happy ?? {}),
  );
  protected readonly selectedId = computed<string | undefined>(() => {
    const id = this.id();
    if (id === HAPPY || (id && this.store.byId().has(id))) return id;
    if (!this.layout.wideDetail() || !this.store.data()) return undefined;
    return this.store.types()[0]?.id ?? HAPPY;
  });
  protected readonly selectedType = computed(() => {
    const id = this.selectedId();
    return id && id !== HAPPY ? this.store.byId().get(id) : undefined;
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
