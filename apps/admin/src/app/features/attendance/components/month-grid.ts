import { NgTemplateOutlet } from '@angular/common';
import { Component, input, output } from '@angular/core';
import { RouterLink } from '@angular/router';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatMinutes } from '../../../shared/time/ist';
import {
  AttendanceDay,
  CalendarRow,
  LEGEND,
  cellDate,
  cellLabel,
  statusChip,
  units,
} from '../../calendar/data/calendar.models';

/**
 * Everyone's month of attendance (server figures from attendance_days, never recomputed): one
 * row per person and one cell per day with the month's totals. Shown beside the list on a wide
 * screen; a narrower one opens each person's own calendar instead. A cell opens that person's
 * day (`?staff=…&day=…`).
 */
@Component({
  selector: 'app-month-grid',
  imports: [NgTemplateOutlet, DetailPane, StatusPill, RouterLink],
  template: `
    <app-detail-pane
      crumb="Staff / Attendance / Calendar"
      icon="calendar_month"
      [heading]="monthName()"
      subtitle="Everyone's month. Pick a day to see it, or a person in the list for their calendar."
      (closed)="closed.emit()"
    >
    <ul class="flex flex-wrap gap-x-3 gap-y-1.5" aria-label="Legend">
      @for (l of legend; track l.status) {
        <li class="flex items-center gap-1.5 text-[12.5px] leading-none text-muted">
          <app-status-pill [tone]="l.tone"
            ><span aria-hidden="true">{{ l.mark }}</span></app-status-pill
          >
          {{ l.label }}
        </li>
      }
    </ul>
    @if (!rows().length) {
      <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
        Nobody's attendance is tracked yet. Staff appear here once they are on the team.
      </p>
    } @else {
      <div class="-mx-2 overflow-x-auto">
        <table class="border-separate border-spacing-0 text-[13px] leading-none">
          <caption class="sr-only">
            One row per person, one column per day, then the month's totals
          </caption>
          <thead>
            <tr>
              <th
                scope="col"
                class="sticky left-0 z-[2] bg-bg px-2 py-2 text-left font-medium text-muted"
              >
                Employee
              </th>
              @for (d of days(); track d) {
                <th
                  scope="col"
                  class="px-0.5 py-2 text-center font-medium"
                  [class.text-primary-text]="d === today()"
                  [attr.aria-label]="dateOf(d)"
                >
                  <span class="block text-[11px] text-muted">{{ weekdayLetter(d) }}</span>
                  <span class="block pt-1">{{ dayNumber(d) }}</span>
                </th>
              }
              @for (c of totalColumns; track c) {
                <th scope="col" class="px-2 py-2 text-right font-medium text-muted">{{ c }}</th>
              }
            </tr>
          </thead>
          <tbody>
            @for (r of rows(); track r.staffId) {
              <tr>
                <th
                  scope="row"
                  class="sticky left-0 z-[1] border-t border-border bg-bg px-2 py-1.5 text-left font-semibold whitespace-nowrap"
                >
                  {{ r.staffName }}
                </th>
                @for (cell of r.cells; track $index) {
                  @let d = days()[$index];
                  <td class="border-t border-border px-0.5 py-1 text-center">
                    <ng-container
                      *ngTemplateOutlet="dayCell; context: { r: r, d: d, cell: cell }"
                    />
                  </td>
                }
                <td class="border-t border-border px-2 text-right tabular-nums">
                  {{ units(r.totals.present) }}
                </td>
                <td class="border-t border-border px-2 text-right tabular-nums">
                  {{ units(r.totals.absent) }}
                </td>
                <td class="border-t border-border px-2 text-right tabular-nums">
                  {{ units(r.totals.leave) }}
                </td>
                <td class="border-t border-border px-2 text-right whitespace-nowrap tabular-nums">
                  {{ hours(r.totals.workedMin) }}
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    }
    </app-detail-pane>

    <ng-template #dayCell let-r="r" let-d="d" let-cell="cell">
      <a
        class="flex min-h-9 min-w-8 flex-col items-center justify-center gap-0.5 rounded-card no-underline hover:bg-info-soft"
        [class.bg-surface]="cell?.status === 'not_employed'"
        [class.ring-2]="isPicked(r.staffId, d)"
        [class.ring-primary]="isPicked(r.staffId, d)"
        [routerLink]="[]"
        [queryParams]="{ staff: r.staffId, day: d, id: null }"
        queryParamsHandling="merge"
        [attr.aria-label]="label(r.staffName, d, cell)"
        [attr.aria-current]="isPicked(r.staffId, d) ? 'true' : null"
      >
        @if (cell && markOf(cell)) {
          <app-status-pill [tone]="chipOf(cell).tone" aria-hidden="true">{{
            markOf(cell)
          }}</app-status-pill>
        }
      </a>
    </ng-template>
  `,
})
export class MonthGrid {
  readonly rows = input.required<readonly CalendarRow[]>();
  readonly days = input.required<readonly string[]>();
  readonly today = input.required<string>();
  /** The open cell, if any. */
  readonly staffId = input<string | null>(null);
  readonly day = input<string | null>(null);
  /** "October 2026". */
  readonly monthName = input('');
  readonly closed = output<void>();

  protected readonly legend = LEGEND.filter((l) => l.status !== 'upcoming');
  protected readonly totalColumns = ['Present', 'Absent', 'Leave', 'Hours'];
  protected readonly units = units;
  protected readonly label = cellLabel;
  protected readonly dateOf = cellDate;
  protected readonly chipOf = (d: AttendanceDay) => statusChip(d.status);


  protected hours(min: number): string {
    return min > 0 ? formatMinutes(min) : '0h';
  }

  /** The cell's mark; days still to come stay blank. */
  protected markOf(d: AttendanceDay): string {
    return d.status === 'upcoming' && !d.open ? '' : statusChip(d.status).mark;
  }

  protected isPicked(staffId: string, day: string): boolean {
    return this.staffId() === staffId && this.day() === day;
  }

  protected weekdayLetter(day: string): string {
    return cellDate(day).charAt(0);
  }

  protected dayNumber(day: string): string {
    return String(Number(day.slice(8)));
  }
}
