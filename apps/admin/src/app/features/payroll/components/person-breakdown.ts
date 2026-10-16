import { Component, computed, inject, input, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import {
  formatCount,
  formatDay,
  formatHMin,
  formatRange,
  weekdayOf,
} from '../../../shared/staff/staff-format';
import { formatDate } from '../../../shared/time/ist';
import { payTypeLabel, perLabel } from '../data/pay-policy';
import { PayrollStore } from '../data/payroll-store';
import {
  DayFact,
  RunLine,
  SalaryAdjustment,
  SalaryRun,
  adjustmentLabel,
  dayFlagLabel,
  dayStatus,
  isReversed,
  rateSpans,
} from '../data/payroll.models';
import { AdjustmentDialog, AdjustmentDialogData } from '../dialogs/adjustment-dialog';
import { ReverseDialog, ReverseDialogData } from '../dialogs/reverse-dialog';
import { DeductionDecision, DeductionRow } from './deduction-row';

/**
 * One person's line of a pay run: the day-by-day timesheet the server counted, then the
 * breakdown — base pay with the rate(s) used (a mid-period change shows as two), extra hours
 * pay, each suggested deduction with Keep / Waive and a note, the adjustments (add, reverse),
 * the server's notes and net. Changes only while the run is a draft.
 */
@Component({
  selector: 'app-person-breakdown',
  imports: [DetailSection, DetailRow, DeductionRow, StatusPill, MatButton, MatIcon],
  template: `
    @let l = line();
    <app-detail-section heading="Salary" [subtitle]="countsLine()">
      <app-detail-row [label]="baseLabel()" [value]="money(l.basePaise)" />
      @if (l.extraPaise > 0) {
        <app-detail-row
          [label]="'Extra hours · ' + hm(l.extraMin)"
          [value]="'+' + money(l.extraPaise)"
        />
      }
      @if (l.extraPaise > 0) {
        <app-detail-row label="Gross" [value]="money(l.grossPaise)" [strong]="true" />
      }
    </app-detail-section>

    <app-detail-section
      heading="Deductions"
      subtitle="Suggested by the attendance and leave. Each counts only if you keep it."
    >
      @for (d of l.deductions; track d.code) {
        <app-deduction-row
          [deduction]="d"
          [editable]="editable()"
          [busy]="busy()"
          (decided)="decide(d.code, $event)"
        />
      } @empty {
        <p class="text-[13px] leading-[1.45] text-muted">No deductions suggested.</p>
      }
      <app-detail-row label="Deductions applied" [value]="'−' + money(l.deductionsPaise)" />
    </app-detail-section>

    <app-detail-section
      heading="Adjustments"
      subtitle="Bonuses, advances and deductions, each with a note."
    >
      @for (a of adjustments(); track a.id) {
        <div
          class="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 text-sm leading-[1.3]"
        >
          <span class="flex min-w-0 flex-col gap-0.5">
            <span
              class="font-medium"
              [class.line-through]="reversed(a)"
              [class.text-muted]="reversed(a)"
            >
              {{ kind(a) }} · {{ a.note }}
            </span>
            <span class="text-xs text-muted">
              {{ date(a.createdAt) }} · by {{ store.userName(a.createdBy)
              }}{{ reversed(a) ? ' · reversed' : '' }}
            </span>
          </span>
          <span class="flex items-center gap-2">
            <span class="font-semibold tabular-nums">{{ signed(a.amountPaise) }}</span>
            @if (editable() && a.kind !== 'reversal' && !reversed(a)) {
              <button
                mat-button
                type="button"
                [attr.aria-label]="'Reverse ' + kind(a) + ' ' + a.note"
                (click)="reverse(a)"
              >
                Reverse
              </button>
            }
          </span>
        </div>
      } @empty {
        <p class="text-[13px] leading-[1.45] text-muted">No adjustments.</p>
      }
      @if (editable()) {
        <div>
          <button mat-stroked-button type="button" (click)="addAdjustment()">
            <mat-icon aria-hidden="true">add</mat-icon>Add adjustment
          </button>
        </div>
      }
      <app-detail-row label="Adjustments" [value]="signed(l.adjustmentsPaise)" />
    </app-detail-section>

    @if (l.notes.length) {
      <app-detail-section heading="Notes from the calculation">
        <ul class="flex list-disc flex-col gap-1 pl-5 text-[13px] leading-[1.45]">
          @for (n of l.notes; track $index) {
            <li>{{ n }}</li>
          }
        </ul>
      </app-detail-section>
    }

    <details class="group rounded-card border border-border">
      <summary
        class="flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-medium [&::-webkit-details-marker]:hidden"
      >
        <span
          class="icon text-[20px] text-muted transition-transform group-open:rotate-90"
          aria-hidden="true"
          >chevron_right</span
        >
        Day by day and rates
        <span class="text-[12.5px] font-normal text-muted"
          >Worked {{ hm(l.workedMin) }} · extra {{ hm(l.extraMin) }}</span
        >
      </summary>
      <div class="flex flex-col gap-4 border-t border-border p-4">
        <div class="flex flex-col gap-2.5">
          @for (s of spans(); track s.rate.effectiveFrom) {
            <app-detail-row
              [label]="'Rate · ' + range(s.first, s.last)"
              [value]="money(s.rate.basePaise) + ' ' + per(s.rate.payType) + extraText(s.rate)"
            />
          } @empty {
            <app-detail-row label="Rate" value="No pay rate in this period" [muted]="true" />
          }
        </div>
      <div class="-mx-2 max-h-[420px] overflow-auto">
        <table class="w-full min-w-[560px] border-collapse text-left text-[13px] leading-[1.3]">
          <caption class="sr-only">
            Day by day for
            {{
              l.staffName
            }}
          </caption>
          <thead class="sticky top-0 bg-surface">
            <tr class="border-b border-border text-xs text-muted">
              <th scope="col" class="px-2 py-2 font-medium">Day</th>
              <th scope="col" class="px-2 py-2 font-medium">Status</th>
              <th scope="col" class="px-2 py-2 text-right font-medium">Worked</th>
              <th scope="col" class="px-2 py-2 text-right font-medium">Extra</th>
              <th scope="col" class="px-2 py-2 font-medium">Notes</th>
            </tr>
          </thead>
          <tbody>
            @for (d of l.days; track d.day) {
              <tr class="border-b border-border last:border-b-0">
                <th scope="row" class="px-2 py-1.5 font-medium whitespace-nowrap">
                  {{ weekday(d.day) }} {{ day(d.day) }}
                </th>
                <td class="px-2 py-1.5">
                  <app-status-pill [tone]="status(d).tone">{{ status(d).label }}</app-status-pill>
                </td>
                <td class="px-2 py-1.5 text-right tabular-nums">
                  {{ d.workedMin ? hm(d.workedMin) : '—' }}
                </td>
                <td class="px-2 py-1.5 text-right tabular-nums">
                  {{ d.extraMin ? hm(d.extraMin) : '—' }}
                </td>
                <td class="px-2 py-1.5 text-muted">{{ dayNotes(d) }}</td>
              </tr>
            } @empty {
              <tr>
                <td colspan="5" class="px-2 py-6 text-center text-muted">No days recorded.</td>
              </tr>
            }
          </tbody>
        </table>
      </div>
      </div>
    </details>

    <app-detail-section>
      <app-detail-row label="Calculated pay" [value]="money(l.netPaise)" [strong]="true" />
      @if (error()) {
        <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
      }
    </app-detail-section>
  `,
  host: { class: 'flex flex-col gap-5' },
})
export class PersonBreakdown {
  protected readonly store = inject(PayrollStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly run = input.required<SalaryRun>();
  readonly line = input.required<RunLine>();
  /** The run's adjustments (this person's are shown). */
  readonly allAdjustments = input.required<readonly SalaryAdjustment[]>();
  /** Draft run and the Payroll permission. */
  readonly editable = input(false);

  protected readonly money = formatPaise;
  protected readonly hm = formatHMin;
  protected readonly day = formatDay;
  protected readonly weekday = weekdayOf;
  protected readonly range = formatRange;
  protected readonly date = formatDate;
  protected readonly per = perLabel;
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected readonly payType = computed(() => payTypeLabel(this.line().payType));
  /** "Base salary" for monthly pay, "Days worked" / "Hours worked" pay otherwise. */
  protected readonly baseLabel = computed(() => {
    const t = this.line().payType;
    return t === 'monthly' ? 'Base salary' : t === 'daily' ? 'Pay for days worked' : 'Pay for hours worked';
  });
  protected readonly adjustments = computed(() =>
    this.allAdjustments().filter((a) => a.staffId === this.line().staffId),
  );
  protected readonly spans = computed(() =>
    rateSpans(this.line().rates, this.run().periodStart, this.run().periodEnd),
  );
  protected readonly countsLine = computed(() => {
    const c = this.line().dayCounts;
    const n = formatCount;
    return [
      `${n(c.scheduled)} scheduled`,
      `${n(c.present)} present`,
      c.late ? `${n(c.late)} late` : '',
      c.halfDay ? `${n(c.halfDay)} half-day` : '',
      c.absent ? `${n(c.absent)} absent` : '',
      c.paidLeave ? `${n(c.paidLeave)} paid leave` : '',
      c.lopLeave ? `${n(c.lopLeave)} unpaid leave` : '',
      c.holiday ? `${n(c.holiday)} holiday` : '',
      c.weekOff ? `${n(c.weekOff)} days off` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  });

  protected status(d: DayFact) {
    return dayStatus(d.status);
  }

  protected dayNotes(d: DayFact): string {
    return [
      d.holiday ?? '',
      d.late ? 'Late' : '',
      d.early ? 'Left early' : '',
      d.leavePaid ? `Paid leave ${formatCount(d.leavePaid)}` : '',
      d.leaveLop ? `LOP ${formatCount(d.leaveLop)}` : '',
      ...d.flags.map(dayFlagLabel),
    ]
      .filter(Boolean)
      .join(' · ');
  }

  protected extraText(r: {
    extraHoursPaid: boolean;
    extraHourlyPaise: number | null;
    payType: string;
  }): string {
    if (!r.extraHoursPaid)
      return r.payType === 'hourly'
        ? ' · extra hours at the hourly rate'
        : ' · extra hours not paid';
    return r.extraHourlyPaise !== null
      ? ` · extra hours ${formatPaise(r.extraHourlyPaise)} / h`
      : ' · extra hours paid (derived rate)';
  }

  protected kind(a: SalaryAdjustment): string {
    return adjustmentLabel(a.kind);
  }

  protected reversed(a: SalaryAdjustment): boolean {
    return isReversed(a, this.allAdjustments());
  }

  protected signed(paise: number): string {
    return paise > 0 ? `+${formatPaise(paise)}` : formatPaise(paise);
  }

  protected async decide(
    code: RunLine['deductions'][number]['code'],
    d: DeductionDecision,
  ): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.setDeduction(this.run().id, this.line().staffId, code, d.applied, d.note);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected addAdjustment(): void {
    const data: AdjustmentDialogData = {
      runId: this.run().id,
      staffId: this.line().staffId,
      staffName: this.line().staffName,
    };
    this.dialog
      .open(AdjustmentDialog, { data, width: '460px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((done) => {
        if (done) this.snack.open('Adjustment added', undefined, { duration: 3200 });
      });
  }

  protected reverse(a: SalaryAdjustment): void {
    const data: ReverseDialogData = { runId: this.run().id, adjustment: a };
    this.dialog
      .open(ReverseDialog, { data, width: '440px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((done) => {
        if (done) this.snack.open('Adjustment reversed', undefined, { duration: 3200 });
      });
  }
}
