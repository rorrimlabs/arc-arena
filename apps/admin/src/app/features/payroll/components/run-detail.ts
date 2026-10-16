import { DOCUMENT } from '@angular/common';
import { Component, computed, inject, input, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatMenu, MatMenuItem, MatMenuTrigger } from '@angular/material/menu';
import { MatSnackBar } from '@angular/material/snack-bar';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Session } from '../../../core/auth/session';
import { Clock } from '../../../core/time/clock';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatCount, formatHMin } from '../../../shared/staff/staff-format';
import { formatDate, formatTime } from '../../../shared/time/ist';
import { payTypeLabel } from '../data/pay-policy';
import { PayrollStore } from '../data/payroll-store';
import {
  RunLine,
  SalaryRun,
  negativeNetNames,
  periodLabel,
  runStatus,
} from '../data/payroll.models';
import { PersonBreakdown } from './person-breakdown';
import { PayrollReportMeta, summaryCsv, timesheetCsv } from './payroll-csv';

/** The permission that finalises or discards a run. */
export const FINALISE_PERM = 'payroll_finalise';

/**
 * A pay run: what each employee is to be paid (days worked, leave, calculated pay), with the
 * full month-end timesheet (days by status, hours, money) folded below, and a person's
 * breakdown and day-by-day timesheet one click away. Recalculate,
 * Finalise (locks the period's attendance and leave) and Discard while it is a draft; exports
 * (timesheet and summary CSV) and a print view at any time. Finalised runs are read-only.
 */
@Component({
  selector: 'app-run-detail',
  imports: [
    DetailPane,
    DetailSection,
    StatTile,
    StatusPill,
    PersonBreakdown,
    MatButton,
    MatIcon,
    MatMenu,
    MatMenuItem,
    MatMenuTrigger,
    RouterLink,
  ],
  template: `
    @let r = run();
    <app-detail-pane
      [crumb]="'Staff / Payroll / ' + period()"
      icon="payments"
      [heading]="person()?.staffName ?? period()"
      [subtitle]="person() ? period() : subtitle()"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="status().tone">{{ status().label }}</app-status-pill>
      <div stats class="flex flex-col gap-3">
        @if (person()) {
          <div>
            <a
              mat-button
              [routerLink]="[]"
              [queryParams]="{ staff: null }"
              queryParamsHandling="merge"
            >
              <mat-icon aria-hidden="true">arrow_back</mat-icon>Everyone
            </a>
          </div>
        } @else {
          <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-3">
            <app-stat-tile label="Employees" [value]="count(r.staffCount)" />
            <app-stat-tile label="Total to pay" [value]="money(r.netPaise)" />
          </div>
        }
      </div>
      @if (person(); as l) {
        <app-person-breakdown
          [run]="r"
          [line]="l"
          [allAdjustments]="store.detail()?.adjustments ?? []"
          [editable]="editable()"
        />
      } @else {
        <app-detail-section
          [heading]="r.status === 'draft' ? 'Draft' : status().label"
          [subtitle]="stateText()"
        >
          <div class="flex flex-wrap gap-2">
            @if (r.status === 'draft' && canPayroll()) {
              <button mat-stroked-button type="button" [disabled]="busy()" (click)="recalculate()">
                <mat-icon aria-hidden="true">refresh</mat-icon>Recalculate
              </button>
            }
            @if (r.status === 'draft' && canFinalise()) {
              <button mat-flat-button type="button" [disabled]="busy()" (click)="finalise()">
                <mat-icon aria-hidden="true">lock</mat-icon>Finalise…
              </button>
              <button mat-stroked-button type="button" [disabled]="busy()" (click)="discard()">
                Discard draft…
              </button>
            }
            <button mat-button type="button" [matMenuTriggerFor]="exports">
              <mat-icon aria-hidden="true">download</mat-icon>Export
            </button>
            <mat-menu #exports="matMenu">
              <button
                mat-menu-item
                type="button"
                [disabled]="!lines().length"
                (click)="exportTimesheet()"
              >
                Timesheet (CSV)
              </button>
              <button
                mat-menu-item
                type="button"
                [disabled]="!lines().length"
                (click)="exportSummary()"
              >
                Pay summary (CSV)
              </button>
              <a mat-menu-item routerLink="/staff/payroll/print" [queryParams]="{ id: r.id, auto: 1 }"
                >Print / Save as PDF</a
              >
            </mat-menu>
          </div>
          @if (r.status === 'draft' && !canFinalise()) {
            <p role="note" class="text-[13px] leading-[1.45] text-muted">
              Finalising or discarding needs the Finalise pay permission.
            </p>
          }
          @if (error()) {
            <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
          }
        </app-detail-section>

        <app-detail-section
          heading="Pay for each employee"
          subtitle="Calculated from attendance, leave and salaries. Open someone to see how, keep or waive deductions and add adjustments."
        >
          @if (store.detailError(); as e) {
            <p role="alert" class="text-[13px] text-danger">The lines couldn't load: {{ e }}</p>
          } @else if (!store.detail()) {
            <p class="text-[13px] text-muted">Loading…</p>
          } @else {
            <div class="-mx-2 overflow-x-auto">
              <table class="w-full min-w-[420px] border-collapse text-left text-sm leading-[1.3]">
                <caption class="sr-only">
                  Pay for {{ period() }}
                </caption>
                <thead>
                  <tr class="border-b border-border text-xs text-muted">
                    <th scope="col" class="px-2 py-2 font-medium">Employee</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Days worked</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Leave</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Calculated pay</th>
                  </tr>
                </thead>
                <tbody>
                  @for (l of lines(); track l.staffId) {
                    <tr class="border-b border-border last:border-b-0">
                      <th scope="row" class="px-2 py-2.5 font-medium">
                        <a
                          [routerLink]="[]"
                          [queryParams]="{ staff: l.staffId }"
                          queryParamsHandling="merge"
                          class="text-fg underline-offset-2 hover:underline"
                          >{{ l.staffName }}</a
                        >
                        @if (l.notes.length || hasDeductions(l)) {
                          <span class="block pt-0.5 text-xs font-normal text-muted">{{
                            lineHint(l)
                          }}</span>
                        }
                      </th>
                      <td class="px-2 py-2.5 text-right tabular-nums">
                        {{ count(l.dayCounts.present) }}
                      </td>
                      <td class="px-2 py-2.5 text-right tabular-nums">
                        {{ count(l.dayCounts.paidLeave + l.dayCounts.lopLeave) }}
                      </td>
                      <td
                        class="px-2 py-2.5 text-right font-semibold whitespace-nowrap tabular-nums"
                        [class.text-danger]="l.netPaise < 0"
                      >
                        {{ money(l.netPaise) }}
                      </td>
                    </tr>
                  } @empty {
                    <tr>
                      <td colspan="4" class="px-2 py-6 text-center text-muted">
                        Nobody in this run: only staff with a salary in force by its last day are
                        included. Set salaries on Team.
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }
        </app-detail-section>

        @if (store.detail() && lines().length) {
        <details class="group rounded-card border border-border">
          <summary
            class="flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-medium [&::-webkit-details-marker]:hidden"
          >
            <span
              class="icon text-[20px] text-muted transition-transform group-open:rotate-90"
              aria-hidden="true"
              >chevron_right</span
            >
            Full timesheet
            <span class="text-[12.5px] font-normal text-muted"
              >Days by status, hours, gross, deductions</span
            >
          </summary>
          <div class="border-t border-border p-4">
            <div class="-mx-2 overflow-x-auto">
              <table
                class="w-full min-w-[1100px] border-collapse text-left text-[13px] leading-[1.3]"
              >
                <caption class="sr-only">
                  Timesheet for
                  {{
                    period()
                  }}
                </caption>
                <thead>
                  <tr class="border-b border-border text-xs text-muted">
                    <th scope="col" class="px-2 py-2 font-medium">Staff</th>
                    <th scope="col" class="px-2 py-2 font-medium">Pay type</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium" title="Scheduled days">
                      Sched.
                    </th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Present</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Late</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Half</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Absent</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Paid leave</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">LOP</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Holiday</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Week off</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Worked</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Extra</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Gross</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Deductions</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Adjustments</th>
                    <th scope="col" class="px-2 py-2 text-right font-medium">Net</th>
                  </tr>
                </thead>
                <tbody>
                  @for (l of lines(); track l.staffId) {
                    @let c = l.dayCounts;
                    <tr
                      class="border-b border-border last:border-b-0"
                      [attr.data-staff]="l.staffId"
                    >
                      <th scope="row" class="px-2 py-2 font-medium whitespace-nowrap">
                        <a
                          [routerLink]="[]"
                          [queryParams]="{ staff: l.staffId }"
                          queryParamsHandling="merge"
                          class="text-fg underline-offset-2 hover:underline"
                          >{{ l.staffName }}</a
                        >
                      </th>
                      <td class="px-2 py-2 whitespace-nowrap">{{ payType(l) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.scheduled) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.present) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.late) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.halfDay) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.absent) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.paidLeave) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.lopLeave) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.holiday) }}</td>
                      <td class="px-2 py-2 text-right tabular-nums">{{ count(c.weekOff) }}</td>
                      <td class="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                        {{ hm(l.workedMin) }}
                      </td>
                      <td class="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                        {{ hm(l.extraMin) }}
                      </td>
                      <td class="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                        {{ money(l.grossPaise) }}
                      </td>
                      <td class="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                        −{{ money(l.deductionsPaise) }}
                      </td>
                      <td class="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                        {{ signed(l.adjustmentsPaise) }}
                      </td>
                      <td
                        class="px-2 py-2 text-right font-semibold whitespace-nowrap tabular-nums"
                        [class.text-danger]="l.netPaise < 0"
                      >
                        {{ money(l.netPaise) }}
                      </td>
                    </tr>
                  } @empty {
                    <tr>
                      <td colspan="17" class="px-2 py-6 text-center text-muted">
                        Nobody in this run: only staff with a pay rate in force by its last day are
                        included.
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </div>
        </details>
        }
      }
    </app-detail-pane>
  `,
})
export class RunDetail {
  protected readonly store = inject(PayrollStore);
  private readonly arena = inject(ArenaContext);
  private readonly session = inject(Session);
  private readonly clock = inject(Clock);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly document = inject(DOCUMENT);

  readonly run = input.required<SalaryRun>();
  /** The person opened (`?staff=`), or null for the timesheet. */
  readonly staffId = input<string | null>(null);
  readonly closed = output<void>();

  protected readonly money = formatPaise;
  protected readonly hm = formatHMin;
  protected readonly count = formatCount;
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected readonly canPayroll = computed(() => this.arena.hasPerm('payroll'));
  protected readonly canFinalise = computed(() => this.arena.hasPerm(FINALISE_PERM));
  protected readonly editable = computed(() => this.run().status === 'draft' && this.canPayroll());
  protected readonly status = computed(() => runStatus(this.run().status));
  protected readonly period = computed(() => periodLabel(this.run()));
  protected readonly lines = computed<readonly RunLine[]>(() =>
    [...(this.store.detail()?.lines ?? [])].sort((a, b) => a.staffName.localeCompare(b.staffName)),
  );
  protected readonly person = computed(() => {
    const id = this.staffId();
    return id ? this.lines().find((l) => l.staffId === id) : undefined;
  });
  protected readonly subtitle = computed(() => {
    const n = this.run().staffCount;
    return `${n} ${n === 1 ? 'person' : 'people'} · net ${formatPaise(this.run().netPaise)}`;
  });
  protected readonly stateText = computed(() => {
    const r = this.run();
    if (r.status === 'finalised') {
      return `Finalised by ${this.store.userName(r.finalisedBy)}${
        r.finalisedAt ? ` on ${formatDate(r.finalisedAt)}, ${formatTime(r.finalisedAt)}` : ''
      }. Read-only: anything missed goes into the next run as an adjustment.`;
    }
    if (r.status === 'discarded') return 'Discarded. Kept for the record only.';
    return `Calculated ${r.computedAt ? `${formatDate(r.computedAt)}, ${formatTime(r.computedAt)}` : 'just now'} from live attendance, leave and rates. Keep or waive each suggested deduction, add adjustments, then finalise.`;
  });

  protected hasDeductions(l: RunLine): boolean {
    return l.deductions.some((d) => d.applied && d.amountPaise > 0);
  }

  /** The line's short note under the name: deductions kept, or the calculation's first note. */
  protected lineHint(l: RunLine): string {
    const kept = l.deductions.filter((d) => d.applied && d.amountPaise > 0);
    if (kept.length) {
      return `Deductions: ${kept.map((d) => d.label.toLowerCase()).join(', ')}`;
    }
    return l.notes[0] ?? '';
  }

  protected payType(l: RunLine): string {
    return payTypeLabel(l.payType);
  }

  protected signed(paise: number): string {
    return paise > 0 ? `+${formatPaise(paise)}` : formatPaise(paise);
  }

  protected async recalculate(): Promise<void> {
    await this.act(() => this.store.recalculate(this.run().id), 'Recalculated from live data');
  }

  protected async finalise(): Promise<void> {
    const ok = await this.confirm({
      title: `Finalise pay for ${this.period()}?`,
      message:
        'The lines are recalculated one last time and then locked, with your keep / waive decisions and adjustments. Attendance and leave on these dates can no longer change; anything missed goes into the next run as an adjustment.',
      confirm: 'Finalise',
    });
    if (!ok) return;
    await this.act(() => this.store.finalise(this.run().id), 'Pay run finalised');
  }

  protected async discard(): Promise<void> {
    const ok = await this.confirm({
      title: `Discard the draft for ${this.period()}?`,
      message:
        'The draft is kept for the record but no longer counts, and its dates are free for a new run. Your decisions and adjustments on it are not carried over.',
      confirm: 'Discard draft',
      danger: true,
    });
    if (!ok) return;
    await this.act(() => this.store.discard(this.run().id), 'Draft discarded');
  }

  private async confirm(data: ConfirmDialogData): Promise<boolean> {
    const ref = this.dialog.open(ConfirmDialog, { data, width: '460px' });
    return (await firstValueFrom(ref.afterClosed())) === true;
  }

  private async act(work: () => Promise<void>, done: string): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      await work();
      this.snack.open(done, undefined, { duration: 3200 });
    } catch (e) {
      const err = toAppError(e);
      if (err.code === 'net_negative') {
        const names = negativeNetNames(this.lines());
        this.error.set(
          names.length
            ? `Net pay would be below zero for ${names.join(', ')}. Waive a deduction or reverse an adjustment first.`
            : err.message,
        );
      } else {
        this.error.set(err.message);
      }
    } finally {
      this.busy.set(false);
    }
  }

  private meta(): PayrollReportMeta {
    const user = this.session.user();
    return {
      arena: this.arena.current().name,
      run: this.run(),
      generatedAt: this.clock.now(),
      generatedBy: user ? `${user.name} <${user.email}>` : null,
    };
  }

  protected exportTimesheet(): void {
    this.download(timesheetCsv(this.lines(), this.meta()), 'timesheet');
  }

  protected exportSummary(): void {
    this.download(
      summaryCsv(this.lines(), this.store.detail()?.adjustments ?? [], this.meta()),
      'pay-summary',
    );
  }

  private download(csv: string, what: string): void {
    const r = this.run();
    const slug = this.arena
      .current()
      .name.toLowerCase()
      .replace(/[^a-z0-9]+/g, '-');
    try {
      // A byte-order mark so spreadsheet apps read names as UTF-8.
      const url = URL.createObjectURL(new Blob(['﻿', csv], { type: 'text/csv' }));
      const a = this.document.createElement('a');
      a.href = url;
      a.download = `${slug || 'arena'}-${what}-${r.periodStart}_to_${r.periodEnd}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url));
    } catch {
      // Download blocked (e.g. a sandboxed preview): the snackbar still reports it.
    }
    this.snack.open(`${what === 'timesheet' ? 'Timesheet' : 'Summary'} exported`, undefined, {
      duration: 3200,
    });
  }
}
