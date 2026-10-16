import { Component, computed, inject, input, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatCount, formatDays, formatRange } from '../../../shared/staff/staff-format';
import { formatDate, formatTime } from '../../../shared/time/ist';
import { initials } from '../../users/components/user-format';
import { LeaveStore } from '../data/leave-store';
import {
  LeaveRequest,
  alsoOff,
  datesLabel,
  halfDayLabel,
  kindLabel,
  requestHistory,
  splitLabel,
  statusLabel,
} from '../data/leave.models';
import { DecideDialogData, DecideMode, LeaveDecideDialog } from '../dialogs/decide-dialog';

const DONE: Readonly<Record<DecideMode, string>> = {
  approve: 'Leave approved',
  reject: 'Leave rejected',
  cancel: 'Cancellation approved · the leave is cancelled',
  keep: 'Leave kept as approved',
};

/**
 * One leave request: who, planned or unplanned, the dates (and half), the working days the
 * server counted, the reason, what happened so far, the person's balance this leave year, and
 * who else is off on those days (information only). Approve (with the paid / LOP split) or
 * reject a new request; approve a cancellation or keep the leave. Nobody but the owner decides
 * their own request.
 */
@Component({
  selector: 'app-leave-request-detail',
  imports: [DetailPane, DetailSection, DetailRow, StatTile, StatusPill, MatButton, MatIcon],
  template: `
    @let r = request();
    <app-detail-pane
      [crumb]="'Staff / Leave / ' + name()"
      [heading]="name()"
      [subtitle]="dates()"
      [initials]="initialsOf(name())"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="status().tone">{{ status().label }}</app-status-pill>
      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
        <app-stat-tile label="Working days" [value]="count(r.days)" />
        <app-stat-tile label="Kind" [value]="kind()" />
        @if (balance(); as b) {
          <app-stat-tile label="Balance now" [value]="count(b.balance)" />
        }
      </div>

      @if (r.status === 'pending' || r.status === 'cancel_pending') {
        <app-detail-section
          [heading]="r.status === 'pending' ? 'Decide' : 'Cancellation requested'"
          [subtitle]="
            r.status === 'pending'
              ? 'Approve with how many days are paid, or reject.'
              : 'They asked to cancel this approved leave.'
          "
        >
          @if (mayDecide()) {
            <div class="flex flex-wrap gap-2">
              @if (r.status === 'pending') {
                <button mat-flat-button type="button" (click)="decide('approve')">
                  <mat-icon aria-hidden="true">check</mat-icon>Approve…
                </button>
                <button mat-stroked-button type="button" (click)="decide('reject')">
                  <mat-icon aria-hidden="true">close</mat-icon>Reject…
                </button>
              } @else {
                <button mat-flat-button type="button" (click)="decide('cancel')">
                  Approve cancellation
                </button>
                <button mat-stroked-button type="button" (click)="decide('keep')">
                  Keep the leave
                </button>
              }
            </div>
          } @else {
            <p role="note" class="text-[13px] leading-[1.45] text-muted">
              This is your own request: another approver (or the owner) decides it.
            </p>
          }
        </app-detail-section>
      }

      <app-detail-section heading="Request">
        <app-detail-row label="Kind" [value]="kind()" />
        <app-detail-row label="Dates" [value]="range()" />
        @if (half()) {
          <app-detail-row label="Half day" [value]="half()" />
        }
        <app-detail-row label="Working days counted" [value]="daysText()" />
        @if (split()) {
          <app-detail-row label="Paid / LOP" [value]="split()" />
        }
        <app-detail-row label="Reason" [value]="r.reason || '—'" [muted]="!r.reason" />
      </app-detail-section>

      <app-detail-section heading="History">
        <ol class="flex flex-col gap-3" aria-label="History">
          @for (h of history(); track $index) {
            <li class="flex flex-col gap-0.5 text-sm leading-[1.35]">
              <span class="font-medium">{{ h.text }}</span>
              <span class="text-xs text-muted">{{ when(h.at) }}</span>
              @if (h.note) {
                <span class="text-[13px] text-muted">“{{ h.note }}”</span>
              }
            </li>
          }
        </ol>
      </app-detail-section>

      @if (balance(); as b) {
        <app-detail-section
          heading="Balance"
          [subtitle]="'Leave year ' + yearRange() + ' (from the joining date)'"
        >
          <app-detail-row label="Allowance" [value]="count(b.allowance)" />
          <app-detail-row label="Adjustments" [value]="signed(b.adjustments)" />
          <app-detail-row label="Paid days used" [value]="count(b.used)" />
          <app-detail-row label="Waiting for a decision" [value]="count(b.pending)" />
          <app-detail-row label="Balance" [value]="count(b.balance)" [strong]="true" />
        </app-detail-section>
      }

      <app-detail-section
        heading="Also off then"
        subtitle="Other people with approved or waiting leave on any of these days. For information only."
      >
        @for (o of others(); track o.id) {
          <div class="flex items-baseline justify-between gap-4 text-sm leading-[1.3]">
            <span class="font-medium">{{ store.nameOfStaff().get(o.staffId) ?? 'Someone' }}</span>
            <span class="text-right text-muted">{{ datesOf(o) }} · {{ statusOf(o) }}</span>
          </div>
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">Nobody else is off on these days.</p>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class LeaveRequestDetail {
  protected readonly store = inject(LeaveStore);
  private readonly arena = inject(ArenaContext);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly request = input.required<LeaveRequest>();
  readonly closed = output<void>();

  protected readonly count = formatCount;
  protected readonly initialsOf = initials;
  protected readonly datesOf = datesLabel;
  protected readonly name = computed(
    () => this.store.nameOfStaff().get(this.request().staffId) ?? 'Someone',
  );
  protected readonly status = computed(() => statusLabel(this.request().status));
  protected readonly kind = computed(() => kindLabel(this.request().kind));
  protected readonly dates = computed(() => datesLabel(this.request()));
  protected readonly range = computed(() =>
    formatRange(this.request().fromDate, this.request().toDate),
  );
  protected readonly half = computed(() => halfDayLabel(this.request().halfDay));
  protected readonly daysText = computed(() => formatDays(this.request().days));
  protected readonly split = computed(() => splitLabel(this.request()));
  protected readonly balance = computed(() => this.store.balanceOf().get(this.request().staffId));
  protected readonly yearRange = computed(() => {
    const b = this.balance();
    return b ? formatRange(b.yearStart, b.yearEnd) : '';
  });
  protected readonly history = computed(() =>
    requestHistory(this.request(), (id) => this.store.userName(id)),
  );
  protected readonly others = computed(() => alsoOff(this.request(), this.store.requests()));
  protected readonly mayDecide = computed(
    () => this.arena.hasPerm('leave_approve') && this.store.canDecide(this.request()),
  );

  protected statusOf(r: LeaveRequest): string {
    return statusLabel(r.status).label.toLowerCase();
  }

  protected signed(n: number): string {
    return n > 0 ? `+${formatCount(n)}` : formatCount(n);
  }

  protected when(iso: string): string {
    return `${formatDate(iso)}, ${formatTime(iso)}`;
  }

  protected decide(mode: DecideMode): void {
    const data: DecideDialogData = {
      request: this.request(),
      staffName: this.name(),
      balance: this.balance() ?? null,
      mode,
    };
    this.dialog
      .open(LeaveDecideDialog, { data, width: '480px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((done) => {
        if (done) this.snack.open(DONE[mode], undefined, { duration: 3200 });
      });
  }
}
