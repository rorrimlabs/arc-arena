import { Component, computed, inject, input, output } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { RouterLink } from '@angular/router';
import { ArenaContext } from '../../../core/arena/arena-context';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatCount, formatDayYear, formatRange } from '../../../shared/staff/staff-format';
import { formatDate } from '../../../shared/time/ist';
import { initials } from '../../users/components/user-format';
import { LeaveStore } from '../data/leave-store';
import {
  LeaveBalance,
  datesLabel,
  rangesOverlapRequest,
  splitLabel,
  statusLabel,
} from '../data/leave.models';
import { AdjustDialogData, LeaveAdjustDialog } from '../dialogs/adjust-dialog';

function signed(n: number): string {
  return n > 0 ? `+${formatCount(n)}` : formatCount(n);
}

/** Opens the Adjust balance dialog; a snackbar confirms. */
function openAdjust(dialog: MatDialog, snack: MatSnackBar, balance: LeaveBalance): void {
  const data: AdjustDialogData = { balance };
  dialog
    .open(LeaveAdjustDialog, { data, width: '440px', autoFocus: 'first-tabbable' })
    .afterClosed()
    .subscribe((done) => {
      if (done)
        snack.open(`${balance.staffName}’s balance adjusted`, undefined, { duration: 3200 });
    });
}

/**
 * Everyone's paid-leave balance in their current leave year (leave_balances): joined on, the
 * year, the allowance, adjustments, paid days used, days waiting and what is left. Each row can
 * be adjusted (leave.adjust) by an approver.
 */
@Component({
  selector: 'app-leave-balances-table',
  imports: [DetailPane, DetailSection, RouterLink, MatIconButton, MatIcon],
  template: `
    <app-detail-pane
      crumb="Staff / Leave / Balances"
      icon="event_available"
      heading="Leave balances"
      subtitle="Each person’s leave year runs from their joining date. Unused days don’t carry over."
      (closed)="closed.emit()"
    >
      <app-detail-section>
        <div class="-mx-2 overflow-x-auto">
          <table class="w-full min-w-[760px] border-collapse text-left text-[13px] leading-[1.3]">
            <caption class="sr-only">
              Leave balances
            </caption>
            <thead>
              <tr class="border-b border-border text-xs text-muted">
                <th scope="col" class="px-2 py-2 font-medium">Staff</th>
                <th scope="col" class="px-2 py-2 font-medium">Joined on</th>
                <th scope="col" class="px-2 py-2 font-medium">Leave year</th>
                <th scope="col" class="px-2 py-2 text-right font-medium">Allowance</th>
                <th scope="col" class="px-2 py-2 text-right font-medium">Adjustments</th>
                <th scope="col" class="px-2 py-2 text-right font-medium">Used</th>
                <th scope="col" class="px-2 py-2 text-right font-medium">Waiting</th>
                <th scope="col" class="px-2 py-2 text-right font-medium">Balance</th>
                @if (canAdjust()) {
                  <th scope="col" class="px-2 py-2"><span class="sr-only">Adjust</span></th>
                }
              </tr>
            </thead>
            <tbody>
              @for (b of store.balances(); track b.staffId) {
                <tr class="border-b border-border last:border-b-0">
                  <th scope="row" class="px-2 py-2 font-medium">
                    <a
                      [routerLink]="[]"
                      [queryParams]="{ person: b.staffId }"
                      queryParamsHandling="merge"
                      class="text-fg underline-offset-2 hover:underline"
                      >{{ b.staffName }}</a
                    >
                  </th>
                  <td class="px-2 py-2 whitespace-nowrap">{{ day(b.joinedOn) }}</td>
                  <td class="px-2 py-2 whitespace-nowrap">{{ range(b.yearStart, b.yearEnd) }}</td>
                  <td class="px-2 py-2 text-right tabular-nums">{{ count(b.allowance) }}</td>
                  <td class="px-2 py-2 text-right tabular-nums">{{ signed(b.adjustments) }}</td>
                  <td class="px-2 py-2 text-right tabular-nums">{{ count(b.used) }}</td>
                  <td class="px-2 py-2 text-right tabular-nums">{{ count(b.pending) }}</td>
                  <td
                    class="px-2 py-2 text-right font-semibold tabular-nums"
                    [class.text-danger]="b.balance < 0"
                  >
                    {{ count(b.balance) }}
                  </td>
                  @if (canAdjust()) {
                    <td class="arena-compact px-1 py-0.5 text-right">
                      <button
                        mat-icon-button
                        type="button"
                        [attr.aria-label]="'Adjust ' + b.staffName + '’s balance'"
                        (click)="adjust(b)"
                      >
                        <mat-icon aria-hidden="true">tune</mat-icon>
                      </button>
                    </td>
                  }
                </tr>
              } @empty {
                <tr>
                  <td colspan="9" class="px-2 py-6 text-center text-muted">No staff yet.</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class LeaveBalancesTable {
  protected readonly store = inject(LeaveStore);
  private readonly arena = inject(ArenaContext);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly count = formatCount;
  protected readonly signed = signed;
  protected readonly range = formatRange;
  protected readonly day = formatDayYear;
  protected readonly canAdjust = computed(() => this.arena.hasPerm('leave_approve'));

  protected adjust(b: LeaveBalance): void {
    openAdjust(this.dialog, this.snack, b);
  }
}

/**
 * One person's paid leave this leave year: the figures, the adjustments made to it and their
 * requests in the year; Adjust balance.
 */
@Component({
  selector: 'app-leave-balance-detail',
  imports: [DetailPane, DetailSection, DetailRow, StatTile, StatusPill, MatButton, MatIcon],
  template: `
    @let b = balance();
    <app-detail-pane
      [crumb]="'Staff / Leave / Balances / ' + b.staffName"
      [heading]="b.staffName"
      [subtitle]="'Leave year ' + range(b.yearStart, b.yearEnd)"
      [initials]="initialsOf(b.staffName)"
      (closed)="closed.emit()"
    >
      @if (canAdjust()) {
        <button actions mat-stroked-button type="button" (click)="adjust()">
          <mat-icon aria-hidden="true">tune</mat-icon>Adjust balance
        </button>
      }
      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(120px,1fr))] gap-3">
        <app-stat-tile label="Balance" [value]="count(b.balance)" />
        <app-stat-tile label="Used" [value]="count(b.used)" />
        <app-stat-tile label="Waiting" [value]="count(b.pending)" />
      </div>
      <app-detail-section
        heading="This leave year"
        subtitle="The year starts on the joining date. Unused days don’t carry over."
      >
        <app-detail-row label="Joined on" [value]="day(b.joinedOn)" />
        <app-detail-row label="Leave year" [value]="range(b.yearStart, b.yearEnd)" />
        <app-detail-row label="Allowance" [value]="count(b.allowance)" />
        <app-detail-row label="Adjustments" [value]="signed(b.adjustments)" />
        <app-detail-row label="Paid days used" [value]="count(b.used)" />
        <app-detail-row label="Waiting for a decision" [value]="count(b.pending)" />
        <app-detail-row label="Balance" [value]="count(b.balance)" [strong]="true" />
      </app-detail-section>
      <app-detail-section heading="Adjustments">
        @for (a of adjustments(); track a.id) {
          <div class="flex items-baseline justify-between gap-4 text-sm leading-[1.3]">
            <span class="flex min-w-0 flex-col gap-0.5">
              <span class="font-medium">{{ a.reason }}</span>
              <span class="text-xs text-muted"
                >{{ date(a.createdAt) }} · by {{ store.userName(a.createdBy) }}</span
              >
            </span>
            <span class="font-semibold tabular-nums">{{ signed(a.days) }}</span>
          </div>
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">No adjustments this leave year.</p>
        }
      </app-detail-section>
      <app-detail-section heading="Requests this leave year">
        @for (r of requests(); track r.id) {
          <div class="flex items-baseline justify-between gap-4 text-sm leading-[1.3]">
            <span class="flex min-w-0 flex-col gap-0.5">
              <span class="font-medium">{{ dates(r) }}</span>
              <span class="text-xs text-muted">{{ split(r) || count(r.days) + ' days' }}</span>
            </span>
            <app-status-pill [tone]="status(r).tone">{{ status(r).label }}</app-status-pill>
          </div>
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">No requests this leave year.</p>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class LeaveBalanceDetail {
  protected readonly store = inject(LeaveStore);
  private readonly arena = inject(ArenaContext);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly balance = input.required<LeaveBalance>();
  readonly closed = output<void>();

  protected readonly count = formatCount;
  protected readonly signed = signed;
  protected readonly range = formatRange;
  protected readonly day = formatDayYear;
  protected readonly date = formatDate;
  protected readonly dates = datesLabel;
  protected readonly split = splitLabel;
  protected readonly status = (r: { status: Parameters<typeof statusLabel>[0] }) =>
    statusLabel(r.status);
  protected readonly initialsOf = initials;
  protected readonly canAdjust = computed(() => this.arena.hasPerm('leave_approve'));
  protected readonly adjustments = computed(() => {
    const b = this.balance();
    return this.store
      .adjustments()
      .filter((a) => a.staffId === b.staffId && a.yearStart === b.yearStart);
  });
  protected readonly requests = computed(() => {
    const b = this.balance();
    return this.store
      .requests()
      .filter((r) => r.staffId === b.staffId && rangesOverlapRequest(r, b.yearStart, b.yearEnd))
      .sort((x, y) => y.fromDate.localeCompare(x.fromDate));
  });

  protected adjust(): void {
    openAdjust(this.dialog, this.snack, this.balance());
  }
}
