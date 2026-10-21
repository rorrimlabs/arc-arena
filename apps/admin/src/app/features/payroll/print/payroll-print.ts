import { DOCUMENT } from '@angular/common';
import {
  Component,
  Injector,
  ViewEncapsulation,
  afterNextRender,
  computed,
  effect,
  inject,
  input,
} from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { RouterLink } from '@angular/router';
import { ArenaContext } from '../../../core/arena/arena-context';
import { Clock } from '../../../core/time/clock';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { formatCount, formatHMin } from '../../../shared/staff/staff-format';
import { formatDate, formatTime } from '../../../shared/time/ist';
import { payTypeLabel } from '../data/pay-policy';
import { PayrollStore } from '../data/payroll-store';
import {
  RunLine,
  SalaryAdjustment,
  adjustmentLabel,
  isReversed,
  periodLabel,
  runStatus,
} from '../data/payroll.models';
import { deductionFormula } from '../components/deduction-row';

/**
 * A pay run as a printable summary (docs/STAFF.md S13: the browser's Print → Save as PDF, no PDF
 * library): the period and status, one row per person, totals, then each person's deductions
 * (kept or waived) and adjustments. Opened from the run with `?id=…&auto=1`, which opens the
 * print dialog once the page has drawn. A print stylesheet hides the app's frame.
 */
@Component({
  selector: 'app-payroll-print',
  imports: [MatButton, MatIcon, RouterLink],
  encapsulation: ViewEncapsulation.None,
  styles: `
    .payroll-print table {
      border-collapse: collapse;
      width: 100%;
    }
    .payroll-print th,
    .payroll-print td {
      border-bottom: 1px solid var(--color-border, #ddd);
      padding: 4px 6px;
    }
    @media print {
      @page {
        margin: 12mm;
      }
      #app-nav,
      .no-print,
      app-shell main > p[role='note'] {
        display: none !important;
      }
      app-shell,
      app-shell main {
        display: block !important;
        height: auto !important;
        overflow: visible !important;
      }
      body {
        background: #fff !important;
        color: #000 !important;
      }
      .payroll-print {
        padding: 0 !important;
        max-width: none !important;
        font-size: 11px;
      }
      .payroll-print .person {
        break-inside: avoid;
      }
    }
  `,
  template: `
    <div class="payroll-print flex w-full max-w-[1100px] flex-col gap-5 p-6 text-fg">
      <div class="no-print flex flex-wrap items-center gap-2">
        <a mat-button routerLink="/staff/payroll" [queryParams]="{ id: id() }">
          <mat-icon aria-hidden="true">arrow_back</mat-icon>Back to the run
        </a>
        <button mat-flat-button type="button" [disabled]="!ready()" (click)="print()">
          <mat-icon aria-hidden="true">print</mat-icon>Print / Save as PDF
        </button>
      </div>
      @if (!run()) {
        <p class="text-sm text-muted">{{ store.loadError() || 'Loading…' }}</p>
      } @else {
        @let r = run()!;
        <header class="flex flex-col gap-1">
          <h1 class="font-display text-2xl leading-[1.15] font-bold">
            {{ arena.current().name }} — Pay summary
          </h1>
          <p class="text-sm text-muted">
            {{ period() }} · {{ status() }} · printed {{ printedAt }}
          </p>
        </header>
        @if (!store.detail()) {
          <p class="text-sm text-muted">{{ store.detailError() || 'Loading…' }}</p>
        } @else {
          <table class="text-left text-[12px] leading-[1.3]">
            <caption class="sr-only">
              Pay summary for
              {{
                period()
              }}
            </caption>
            <thead>
              <tr>
                <th scope="col">Staff</th>
                <th scope="col">Pay type</th>
                <th scope="col" class="text-right">Present</th>
                <th scope="col" class="text-right">Absent</th>
                <th scope="col" class="text-right">Paid leave</th>
                <th scope="col" class="text-right">LOP</th>
                <th scope="col" class="text-right">Worked</th>
                <th scope="col" class="text-right">Extra</th>
                <th scope="col" class="text-right">Gross</th>
                <th scope="col" class="text-right">Deductions</th>
                <th scope="col" class="text-right">Adjustments</th>
                <th scope="col" class="text-right">Net</th>
              </tr>
            </thead>
            <tbody>
              @for (l of lines(); track l.staffId) {
                <tr>
                  <th scope="row">{{ l.staffName }}</th>
                  <td>{{ payType(l) }}</td>
                  <td class="text-right">{{ count(l.dayCounts.present) }}</td>
                  <td class="text-right">{{ count(l.dayCounts.absent) }}</td>
                  <td class="text-right">{{ count(l.dayCounts.paidLeave) }}</td>
                  <td class="text-right">{{ count(l.dayCounts.lopLeave) }}</td>
                  <td class="text-right">{{ hm(l.workedMin) }}</td>
                  <td class="text-right">{{ hm(l.extraMin) }}</td>
                  <td class="text-right">{{ money(l.grossPaise) }}</td>
                  <td class="text-right">−{{ money(l.deductionsPaise) }}</td>
                  <td class="text-right">{{ signed(l.adjustmentsPaise) }}</td>
                  <td class="text-right font-semibold">{{ money(l.netPaise) }}</td>
                </tr>
              }
            </tbody>
            <tfoot>
              <tr class="font-semibold">
                <th scope="row" colspan="8">
                  Total · {{ r.staffCount }} {{ r.staffCount === 1 ? 'person' : 'people' }}
                </th>
                <td class="text-right">{{ money(r.grossPaise) }}</td>
                <td class="text-right">−{{ money(r.deductionsPaise) }}</td>
                <td class="text-right">{{ signed(r.adjustmentsPaise) }}</td>
                <td class="text-right">{{ money(r.netPaise) }}</td>
              </tr>
            </tfoot>
          </table>
          @for (l of lines(); track l.staffId) {
            <section class="person flex flex-col gap-1.5" [attr.aria-label]="l.staffName">
              <h2 class="text-base font-semibold">
                {{ l.staffName }} · net {{ money(l.netPaise) }}
              </h2>
              <p class="text-[12px]">
                Base {{ money(l.basePaise) }} · extra hours {{ money(l.extraPaise) }} · gross
                {{ money(l.grossPaise) }}
              </p>
              @for (d of l.deductions; track d.code) {
                <p class="text-[12px]">
                  {{ d.label }}: {{ formula(d) }} — {{ d.applied ? 'kept' : 'waived'
                  }}{{ d.note ? ' (' + d.note + ')' : '' }}
                </p>
              }
              @for (a of adjustmentsOf(l); track a.id) {
                <p class="text-[12px]">
                  {{ kind(a) }} {{ signed(a.amountPaise) }} — {{ a.note
                  }}{{ reversed(a) ? ' (reversed)' : '' }}
                </p>
              }
              @for (n of l.notes; track $index) {
                <p class="text-[12px] italic">{{ n }}</p>
              }
            </section>
          }
        }
      }
    </div>
  `,
})
export class PayrollPrint {
  protected readonly store = inject(PayrollStore);
  protected readonly arena = inject(ArenaContext);
  private readonly document = inject(DOCUMENT);
  private readonly injector = inject(Injector);

  /** `?id=` — the run. */
  readonly id = input<string>();
  /** `?auto=1` — open the print dialog once drawn. */
  readonly auto = input<string>();

  protected readonly money = formatPaise;
  protected readonly hm = formatHMin;
  protected readonly count = formatCount;
  protected readonly formula = deductionFormula;
  protected readonly printedAt = (() => {
    const now = inject(Clock).now();
    return `${formatDate(now)}, ${formatTime(now)}`;
  })();

  protected readonly run = computed(() => {
    const id = this.id();
    return id ? this.store.byId().get(id) : undefined;
  });
  protected readonly period = computed(() => {
    const r = this.run();
    return r ? periodLabel(r) : '';
  });
  protected readonly status = computed(() => {
    const r = this.run();
    return r ? runStatus(r.status).label : '';
  });
  protected readonly lines = computed(() =>
    [...(this.store.detail()?.lines ?? [])].sort((a, b) => a.staffName.localeCompare(b.staffName)),
  );
  protected readonly ready = computed(() => !!this.run() && !!this.store.detail());
  private printed = false;

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
    effect(() => {
      void this.store.open(this.run()?.id ?? null);
    });
    // Once the run is drawn, open the browser's print dialog (only when asked by ?auto=1).
    effect(() => {
      if (this.ready() && this.auto() === '1' && !this.printed) {
        this.printed = true;
        afterNextRender(() => this.print(), { injector: this.injector });
      }
    });
  }

  protected payType(l: RunLine): string {
    return payTypeLabel(l.payType);
  }

  protected signed(paise: number): string {
    return paise > 0 ? `+${formatPaise(paise)}` : formatPaise(paise);
  }

  protected adjustmentsOf(l: RunLine): SalaryAdjustment[] {
    return (this.store.detail()?.adjustments ?? []).filter((a) => a.staffId === l.staffId);
  }

  protected kind(a: SalaryAdjustment): string {
    return adjustmentLabel(a.kind);
  }

  protected reversed(a: SalaryAdjustment): boolean {
    return isReversed(a, this.store.detail()?.adjustments ?? []);
  }

  protected print(): void {
    try {
      this.document.defaultView?.print();
    } catch {
      // Printing unavailable (a sandboxed preview): the page stays readable.
    }
  }
}
