import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatOption, MatSelect } from '@angular/material/select';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatDays, formatRange } from '../../shared/staff/staff-format';
import { initials } from '../users/components/user-format';
import { LeaveBalanceDetail, LeaveBalancesTable } from './components/balances';
import { LeaveRequestDetail } from './components/request-detail';
import { LeaveStore } from './data/leave-store';
import {
  LEAVE_STATUSES,
  LeaveRequest,
  asStatus,
  balanceShort,
  datesLabel,
  filterRequests,
  kindLabel,
  openRequests,
  statusLabel,
} from './data/leave.models';

/** The permission this screen needs (the owner holds every permission). */
export const LEAVE_PERM = 'leave_approve';

type Tab = 'requests' | 'all' | 'balances';

/**
 * Staff › Leave (docs/STAFF.md §6): requests waiting for a decision (cancellations first), all
 * requests with filters, and everyone's balance. A request opens with its balance and who else is
 * off then; approve with the paid / LOP split, reject, approve or refuse a cancellation; adjust
 * a balance. The tab, filters and selection are in the URL
 * (`?tab=all&staff=…&status=…&from=…&to=…&id=…`, `?tab=balances&person=…`).
 */
@Component({
  selector: 'app-leave-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    LeaveRequestDetail,
    LeaveBalancesTable,
    LeaveBalanceDetail,
    MatButton,
    MatIconButton,
    MatButtonToggleGroup,
    MatButtonToggle,
    MatFormField,
    MatLabel,
    MatInput,
    MatSelect,
    MatOption,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Leave"
      [detailLabel]="selected() ? 'Leave request' : 'Leave balances'"
      emptyText="Pick a request to decide it"
      [open]="open()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Leave" back="/staff/attendance" backLabel="Back to attendance">
          <mat-button-toggle-group
            aria-label="Show"
            hideSingleSelectionIndicator
            [value]="tab()"
            (change)="pickTab($event.value)"
          >
            <mat-button-toggle value="requests">Requests</mat-button-toggle>
            <mat-button-toggle value="all">All requests</mat-button-toggle>
            <mat-button-toggle value="balances">Balances</mat-button-toggle>
          </mat-button-toggle-group>
          @if (tab() === 'all') {
            <div class="grid grid-cols-2 gap-2">
              <mat-form-field class="arena-dense">
                <mat-label>Staff</mat-label>
                <mat-select
                  [value]="staffParam() ?? ''"
                  (selectionChange)="setParams({ staff: $event.value || null })"
                >
                  <mat-option value="">Everyone</mat-option>
                  @for (s of store.staff(); track s.id) {
                    <mat-option [value]="s.id">{{ s.name }}</mat-option>
                  }
                </mat-select>
              </mat-form-field>
              <mat-form-field class="arena-dense">
                <mat-label>Status</mat-label>
                <mat-select
                  [value]="status() ?? ''"
                  (selectionChange)="setParams({ status: $event.value || null })"
                >
                  <mat-option value="">Any</mat-option>
                  @for (s of statuses; track s) {
                    <mat-option [value]="s">{{ statusText(s) }}</mat-option>
                  }
                </mat-select>
              </mat-form-field>
              <mat-form-field class="arena-dense">
                <mat-label>From</mat-label>
                <input
                  matInput
                  type="date"
                  [value]="fromParam() ?? ''"
                  (change)="setParams({ from: $any($event.target).value || null })"
                />
              </mat-form-field>
              <mat-form-field class="arena-dense">
                <mat-label>To</mat-label>
                <input
                  matInput
                  type="date"
                  [value]="toParam() ?? ''"
                  (change)="setParams({ to: $any($event.target).value || null })"
                />
              </mat-form-field>
            </div>
          }
          <div class="flex items-center gap-2">
            <p class="min-w-0 flex-1 text-[13px] leading-[1.3] text-muted" aria-live="polite">
              {{ summary() }}
            </p>
            <button
              mat-icon-button
              type="button"
              class="arena-compact"
              aria-label="Refresh"
              [disabled]="store.loading()"
              (click)="store.refresh()"
            >
              <mat-icon aria-hidden="true">refresh</mat-icon>
            </button>
          </div>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading leave" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(true)">Try again</button>
            </div>
          } @else if (store.data()) {
            @if (tab() === 'balances') {
              <ul class="flex flex-col gap-0.5" aria-label="Balances">
                @for (b of store.balances(); track b.staffId) {
                  <li>
                    <app-list-row
                      [title]="b.staffName"
                      [subtitle]="'Year ' + range(b.yearStart, b.yearEnd)"
                      [initials]="initialsOf(b.staffName)"
                      [selected]="b.staffId === person()?.staffId"
                      [queryParams]="{ person: b.staffId }"
                      queryParamsHandling="merge"
                    >
                      <span
                        class="text-sm font-semibold tabular-nums"
                        [class.text-danger]="b.balance < 0"
                        >{{ short(b) }}</span
                      >
                    </app-list-row>
                  </li>
                }
              </ul>
            } @else {
              <ul class="flex flex-col gap-0.5" aria-label="Requests">
                @for (r of list(); track r.id) {
                  <li>
                    <app-list-row
                      [title]="nameOf(r)"
                      [subtitle]="rowSub(r)"
                      [initials]="initialsOf(nameOf(r))"
                      [selected]="r.id === selected()?.id"
                      [queryParams]="{ id: r.id }"
                      queryParamsHandling="merge"
                    >
                      <app-status-pill [tone]="statusOf(r).tone">{{
                        statusOf(r).label
                      }}</app-status-pill>
                    </app-list-row>
                  </li>
                }
              </ul>
              @if (!list().length) {
                <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                  {{
                    tab() === 'requests'
                      ? 'Nothing waiting for a decision.'
                      : 'No requests match these filters.'
                  }}
                </p>
              }
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as r) {
          <app-leave-request-detail [request]="r" (closed)="close()" />
        } @else if (person(); as b) {
          <app-leave-balance-detail [balance]="b" (closed)="close()" />
        } @else if (tab() === 'balances') {
          <app-leave-balances-table (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class LeavePage {
  protected readonly store = inject(LeaveStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);

  readonly tabParam = input<string>(undefined, { alias: 'tab' });
  readonly staffParam = input<string>(undefined, { alias: 'staff' });
  readonly statusParam = input<string>(undefined, { alias: 'status' });
  readonly fromParam = input<string>(undefined, { alias: 'from' });
  readonly toParam = input<string>(undefined, { alias: 'to' });
  /** `?id=` — the selected request. */
  readonly id = input<string>();
  /** `?person=` — the selected balance (Balances tab). */
  readonly personParam = input<string>(undefined, { alias: 'person' });

  protected readonly statuses = LEAVE_STATUSES;
  protected readonly range = formatRange;
  protected readonly initialsOf = initials;
  protected readonly short = balanceShort;

  protected readonly tab = computed<Tab>(() => {
    const t = this.tabParam();
    return t === 'all' || t === 'balances' ? t : 'requests';
  });
  protected readonly status = computed(() => asStatus(this.statusParam()));
  protected readonly list = computed<LeaveRequest[]>(() =>
    this.tab() === 'all'
      ? filterRequests(this.store.requests(), {
          staffId: this.staffParam() || null,
          status: this.status(),
          first: this.fromParam() || null,
          last: this.toParam() || null,
        })
      : openRequests(this.store.requests()),
  );
  protected readonly selected = computed(() => {
    const id = this.id();
    return id ? this.store.byId().get(id) : undefined;
  });
  protected readonly person = computed(() => {
    const id = this.personParam();
    return id && this.tab() === 'balances' ? this.store.balanceOf().get(id) : undefined;
  });
  protected readonly open = computed(
    () =>
      !!this.selected() ||
      !!this.person() ||
      (this.tab() === 'balances' && this.layout.wideDetail()),
  );
  protected readonly summary = computed(() => {
    const waiting = this.store.openCount();
    const head = waiting ? `${waiting} waiting for a decision` : 'Nothing waiting';
    if (this.tab() === 'all') {
      const n = this.list().length;
      return `${n} request${n === 1 ? '' : 's'} · ${head.toLowerCase()}`;
    }
    if (this.tab() === 'balances') {
      const n = this.store.balances().length;
      return `${n} ${n === 1 ? 'person' : 'people'} · ${head.toLowerCase()}`;
    }
    return head;
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
    // The permission taken away live (or another arena picked without it): leave.
    effect(() => {
      if (this.arena.loaded() && this.arena.current().id && !this.arena.hasPerm(LEAVE_PERM)) {
        void this.router.navigateByUrl('/overview');
      }
    });
  }

  protected nameOf(r: LeaveRequest): string {
    return this.store.nameOfStaff().get(r.staffId) ?? 'Someone';
  }

  protected rowSub(r: LeaveRequest): string {
    return `${datesLabel(r)} · ${formatDays(r.days)} · ${kindLabel(r.kind)}`;
  }

  protected statusOf(r: LeaveRequest) {
    return statusLabel(r.status);
  }

  protected statusText(s: (typeof LEAVE_STATUSES)[number]): string {
    return statusLabel(s).label;
  }

  protected setParams(params: Record<string, string | null>): void {
    void this.router.navigate([], { queryParams: params, queryParamsHandling: 'merge' });
  }

  protected pickTab(tab: Tab): void {
    this.setParams({ tab: tab === 'requests' ? null : tab, id: null, person: null });
  }

  protected close(): void {
    this.setParams({ id: null, person: null });
  }
}
