import { DOCUMENT } from '@angular/common';
import {
  Component,
  computed,
  effect,
  inject,
  input,
  linkedSignal,
  resource,
  signal,
} from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatChipListbox, MatChipListboxChange, MatChipOption } from '@angular/material/chips';
import { MatFormField, MatPrefix } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { formatRupees } from '../../shared/money/rupees.pipe';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatDate, formatTime } from '../../shared/time/ist';
import { BillDetail } from './components/bill-detail';
import { salesCsv } from './components/sales-csv';
import { SalesStore } from './data/sales-store';
import {
  Bill,
  METHOD_FILTERS,
  SALES_RANGES,
  asMethod,
  asRange,
  billState,
  matchesSearch,
  summarize,
  summaryLine,
} from './data/sale.models';

const PAGE = 40;

/**
 * Sales (design: `if (p === 'sales')`): the arena's closed bills for a date range, filtered by
 * payment method and search, with the range's takings summary and a CSV export. The range,
 * method and selected bill are in the URL (`?range=7d&method=upi&id=…`); on a wide screen the
 * first bill is shown when none is chosen, as in the design.
 */
@Component({
  selector: 'app-sales-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    BillDetail,
    MatButton,
    MatChipListbox,
    MatChipOption,
    MatFormField,
    MatPrefix,
    MatIcon,
    MatInput,
    MatProgressBar,
  ],
  template: `
    <app-list-detail listLabel="Bills" detailLabel="Bill" [open]="!!selected()" (closed)="close()">
      <ng-container list>
        <app-list-pane-header title="Sales">
          <mat-form-field class="arena-search">
            <mat-icon matPrefix aria-hidden="true">search</mat-icon>
            <input
              matInput
              type="search"
              aria-label="Search bills"
              placeholder="Bill, member, station or staff"
              [value]="query()"
              (input)="query.set($any($event.target).value)"
            />
          </mat-form-field>
          <div class="flex flex-wrap gap-1.5">
            <mat-chip-listbox
              aria-label="Date range"
              [value]="range()"
              (change)="pickRange($event)"
            >
              @for (r of ranges; track r.key) {
                <mat-chip-option [value]="r.key" [selectable]="r.key !== range()">{{
                  r.label
                }}</mat-chip-option>
              }
            </mat-chip-listbox>
            <mat-chip-listbox
              aria-label="Payment method"
              [value]="method()"
              (change)="pickMethod($event)"
            >
              @for (m of methods; track m.key) {
                <mat-chip-option [value]="m.key">{{ m.label }}</mat-chip-option>
              }
            </mat-chip-listbox>
          </div>
          <div class="flex items-center gap-2">
            <p class="min-w-0 flex-1 text-[13px] leading-[1.3] text-muted" aria-live="polite">
              {{ summary() }}
            </p>
            <div class="arena-compact">
              <button
                mat-button
                type="button"
                [disabled]="!filtered().length"
                (click)="exportCsv()"
              >
                <mat-icon aria-hidden="true">download</mat-icon>CSV
              </button>
            </div>
          </div>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading bills" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(range(), true)">
                Try again
              </button>
            </div>
          } @else if (!store.loading() || store.bills().length) {
            <ul class="flex flex-col gap-0.5" aria-label="Bills">
              @for (b of visible(); track b.id) {
                <li>
                  <app-list-row
                    [title]="b.customer"
                    [subtitle]="subtitle(b)"
                    [selected]="b.id === selected()?.id"
                    [queryParams]="{ id: b.id }"
                    queryParamsHandling="merge"
                  >
                    <span class="text-sm leading-none font-semibold tabular-nums">{{
                      b.voided ? '—' : rupees(b.billedPaise ?? 0)
                    }}</span>
                    @let state = stateOf(b);
                    @if (state.tone) {
                      <app-status-pill [tone]="state.tone">{{ state.label }}</app-status-pill>
                    } @else {
                      <span class="text-xs leading-none text-muted">{{ state.label }}</span>
                    }
                  </app-list-row>
                </li>
              }
            </ul>
            @if (!filtered().length) {
              <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                No bills match these filters.
              </p>
            }
            @if (filtered().length > visible().length) {
              <div class="flex justify-center py-2">
                <button
                  mat-stroked-button
                  type="button"
                  (click)="shownCount.set(shownCount() + page)"
                >
                  Show more · {{ filtered().length - visible().length }} left
                </button>
              </div>
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as bill) {
          <app-bill-detail [bill]="bill" [range]="range()" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class SalesPage {
  protected readonly store = inject(SalesStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly snack = inject(MatSnackBar);
  private readonly document = inject(DOCUMENT);

  /** `?range=` — today | yesterday | 7d | 30d (default today). */
  readonly rangeParam = input<string>(undefined, { alias: 'range' });
  /** `?method=` — upi | cash, or all. */
  readonly methodParam = input<string>(undefined, { alias: 'method' });
  /** `?id=` — the selected bill. */
  readonly id = input<string>();

  protected readonly ranges = SALES_RANGES;
  protected readonly methods = METHOD_FILTERS;
  protected readonly page = PAGE;
  protected readonly rupees = formatRupees;
  protected readonly stateOf = billState;

  protected readonly range = computed(() => asRange(this.rangeParam()));
  protected readonly method = computed(() => asMethod(this.methodParam()));
  protected readonly query = signal('');
  protected readonly shownCount = linkedSignal({
    source: () => [this.range(), this.method(), this.query()],
    computation: () => PAGE,
  });

  protected readonly filtered = computed(() => {
    const method = this.method();
    const q = this.query();
    return this.store
      .bills()
      .filter((b) => (!method || (b.methods[method] ?? 0) > 0) && matchesSearch(b, q));
  });
  protected readonly visible = computed(() => this.filtered().slice(0, this.shownCount()));
  protected readonly summary = computed(() => summaryLine(summarize(this.filtered())));

  /** A bill opened by link that is not in the loaded range. */
  private readonly linked = resource({
    params: () => {
      const id = this.id();
      if (!id || this.store.loading() || this.store.byId().has(id)) return undefined;
      return { id, revision: this.store.revision() };
    },
    loader: ({ params }) => this.store.get(params.id),
  });
  protected readonly selected = computed<Bill | undefined>(() => {
    const id = this.id();
    if (id) {
      const listed = this.store.byId().get(id);
      if (listed) return listed;
      const linked = this.linked.hasValue() ? this.linked.value() : undefined;
      return linked?.id === id ? linked : undefined;
    }
    return this.layout.wideDetail() ? this.visible()[0] : undefined;
  });

  constructor() {
    // Load (and reload on an arena or range switch) the current arena's bills.
    effect(() => {
      if (this.arena.current().id) void this.store.load(this.range());
    });
  }

  protected subtitle(b: Bill): string {
    const when =
      this.range() === 'today' ? formatTime(b.at) : `${formatDate(b.at)}, ${formatTime(b.at)}`;
    return [b.ref, b.stations.join(', '), when].filter(Boolean).join(' · ');
  }

  protected pickRange(event: MatChipListboxChange): void {
    if (!event.value) return;
    void this.router.navigate([], {
      queryParams: { range: event.value === 'today' ? null : event.value },
      queryParamsHandling: 'merge',
    });
  }

  protected pickMethod(event: MatChipListboxChange): void {
    void this.router.navigate([], {
      queryParams: { method: event.value || null },
      queryParamsHandling: 'merge',
    });
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }

  protected exportCsv(): void {
    const bills = this.filtered();
    const csv = salesCsv(bills);
    const slug = this.arena
      .current()
      .name.toLowerCase()
      .replace(/[^a-z0-9]+/g, '-');
    try {
      const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
      const a = this.document.createElement('a');
      a.href = url;
      a.download = `${slug || 'arena'}-sales-${this.range()}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url));
    } catch {
      // Download blocked (e.g. a sandboxed preview): the snackbar still reports the count.
    }
    this.snack.open(`${bills.length} bills exported`, undefined, { duration: 3200 });
  }
}
