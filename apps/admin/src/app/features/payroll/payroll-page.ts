import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Clock } from '../../core/time/clock';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { formatPaise } from '../../shared/money/rupees.pipe';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatDate, formatIsoDate } from '../../shared/time/ist';
import { RunDetail } from './components/run-detail';
import { policyOn } from './data/pay-policy';
import { PayrollStore } from './data/payroll-store';
import { SalaryRun, periodLabel, runStatus, suggestNextPeriod } from './data/payroll.models';
import { NewRunDialog, NewRunDialogData } from './dialogs/new-run-dialog';

/** The permission this screen needs (the owner holds every permission). */
export const PAYROLL_PERM = 'payroll';

/**
 * Staff › Payroll (docs/STAFF.md §6): the pay runs (draft, finalised, discarded) and a new draft
 * for the next period, which opens on the month-end timesheet. The run and the person opened
 * are in the URL (`?id=…&staff=…`).
 */
@Component({
  selector: 'app-payroll-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    RunDetail,
    MatButton,
    MatIconButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Pay runs"
      detailLabel="Pay run"
      emptyText="Pick a pay run to see its timesheet"
      [open]="!!selected()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Payroll">
          @if (canPayroll()) {
            <button
              actions
              mat-flat-button
              type="button"
              [disabled]="!store.overview()"
              (click)="newRun()"
            >
              <mat-icon aria-hidden="true">calculate</mat-icon>Calculate pay
            </button>
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
          <mat-progress-bar mode="indeterminate" aria-label="Loading pay runs" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(true)">Try again</button>
            </div>
          } @else if (store.overview()) {
            <ul class="flex flex-col gap-0.5" aria-label="Pay runs">
              @for (r of store.runs(); track r.id) {
                <li>
                  <app-list-row
                    [title]="period(r)"
                    [subtitle]="rowSub(r)"
                    icon="payments"
                    [selected]="r.id === selected()?.id"
                    [queryParams]="{ id: r.id }"
                  >
                    <app-status-pill [tone]="status(r).tone">{{ status(r).label }}</app-status-pill>
                    <span class="text-sm font-semibold tabular-nums">{{ money(r.netPaise) }}</span>
                  </app-list-row>
                </li>
              } @empty {
                <li class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                  No pay calculated yet. Calculate pay for the last month: you can review and adjust
                  it before you finalise.
                </li>
              }
            </ul>
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as r) {
          <app-run-detail [run]="r" [staffId]="staffParam() ?? null" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class PayrollPage {
  protected readonly store = inject(PayrollStore);
  private readonly arena = inject(ArenaContext);
  private readonly clock = inject(Clock);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly router = inject(Router);

  /** `?id=` — the selected run. */
  readonly id = input<string>();
  /** `?staff=` — the person opened inside it. */
  readonly staffParam = input<string>(undefined, { alias: 'staff' });

  protected readonly money = formatPaise;
  protected readonly period = periodLabel;
  protected readonly canPayroll = computed(() => this.arena.hasPerm(PAYROLL_PERM));
  protected readonly selected = computed(() => {
    const id = this.id();
    return id ? this.store.byId().get(id) : undefined;
  });
  protected readonly summary = computed(() => {
    const runs = this.store.runs();
    const drafts = runs.filter((r) => r.status === 'draft').length;
    return [
      `${runs.length} run${runs.length === 1 ? '' : 's'}`,
      drafts ? `${drafts} draft${drafts === 1 ? '' : 's'}` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
    // Read the opened run's lines (again when another run is picked).
    effect(() => {
      const run = this.selected();
      void this.store.open(run ? run.id : null);
    });
    effect(() => {
      if (this.arena.loaded() && this.arena.current().id && !this.arena.hasPerm(PAYROLL_PERM)) {
        void this.router.navigateByUrl('/overview');
      }
    });
  }

  protected status(r: SalaryRun) {
    return runStatus(r.status);
  }

  protected rowSub(r: SalaryRun): string {
    const people = `${r.staffCount} ${r.staffCount === 1 ? 'person' : 'people'}`;
    if (r.status === 'finalised' && r.finalisedAt) {
      return `${people} · finalised ${formatDate(r.finalisedAt)} by ${this.store.userName(r.finalisedBy)}`;
    }
    return people;
  }

  protected newRun(): void {
    const o = this.store.overview();
    if (!o) return;
    const today = formatIsoDate(this.clock.now());
    const policy = policyOn(o.policies, today);
    const data: NewRunDialogData = {
      suggested: suggestNextPeriod(policy, o.runs, o.weekStart, today),
      kind: policy.periodKind,
      runs: o.runs,
    };
    this.dialog
      .open(NewRunDialog, { data, width: '480px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((id) => {
        if (!id) return;
        this.snack.open('Pay calculated · review it, then finalise', undefined, { duration: 3200 });
        void this.router.navigate([], { queryParams: { id, staff: null } });
      });
  }

  protected close(): void {
    void this.router.navigate([], {
      queryParams: { id: null, staff: null },
      queryParamsHandling: 'merge',
    });
  }
}
