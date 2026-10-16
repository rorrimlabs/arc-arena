import { A11yModule } from '@angular/cdk/a11y';
import { NgTemplateOutlet } from '@angular/common';
import { Component, computed, effect, inject, input } from '@angular/core';
import { MatIconButton } from '@angular/material/button';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router, RouterLink } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { injectNow } from '../../core/time/ticker';
import { DetailRow } from '../../shared/list-detail/detail-row';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatIsoDate } from '../../shared/time/ist';
import { flagLabel, flagTone } from '../attendance/data/attendance.models';
import { CalendarStore } from './data/calendar-store';
import {
  AttendanceDay,
  LEGEND,
  calendarRows,
  cellDate,
  cellLabel,
  entriesLabel,
  extraShort,
  hoursLong,
  monthDays,
  monthLabel,
  shiftMonth,
  statusChip,
  units,
} from './data/calendar.models';

/** The permission this screen needs (the owner holds every permission). */
export const CALENDAR_PERM = 'attendance_review';

/**
 * Staff › Calendar (docs/STAFF.md §6): a month (IST) with one row per tracked staff member and
 * one cell per day showing the day's status (and extra hours), then the month's totals (days
 * not employed are greyed and left out). A cell opens that day's figures beside the grid, with
 * how many clock-ins it has and a link to them in the attendance log.
 * Every figure comes from the server's attendance_days. The month and the picked cell are in
 * the URL (`?month=2026-10&staff=…&day=2026-10-15`).
 */
@Component({
  selector: 'app-calendar-page',
  imports: [
    A11yModule,
    NgTemplateOutlet,
    ListPaneHeader,
    StatusPill,
    DetailRow,
    RouterLink,
    MatIconButton,
    MatIcon,
    MatFormField,
    MatLabel,
    MatInput,
    MatProgressBar,
  ],
  host: { class: 'flex h-dvh min-w-0' },
  template: `
    <section class="flex h-dvh min-w-0 flex-1 flex-col bg-bg" aria-label="Attendance calendar">
      <app-list-pane-header title="Calendar">
        <div class="flex flex-wrap items-center gap-2">
          <button
            mat-icon-button
            type="button"
            aria-label="Previous month"
            (click)="setParams({ month: shiftMonth(month(), -1), staff: null, day: null })"
          >
            <mat-icon aria-hidden="true">chevron_left</mat-icon>
          </button>
          <mat-form-field class="arena-dense w-48">
            <mat-label>Month</mat-label>
            <input
              matInput
              type="month"
              [value]="month()"
              (change)="pickMonth($any($event.target).value)"
            />
          </mat-form-field>
          <button
            mat-icon-button
            type="button"
            aria-label="Next month"
            (click)="setParams({ month: shiftMonth(month(), 1), staff: null, day: null })"
          >
            <mat-icon aria-hidden="true">chevron_right</mat-icon>
          </button>
          <span class="text-sm leading-none font-medium" aria-live="polite">{{ title() }}</span>
          <button
            mat-icon-button
            type="button"
            class="ml-auto"
            aria-label="Refresh"
            [disabled]="store.loading()"
            (click)="store.refresh()"
          >
            <mat-icon aria-hidden="true">refresh</mat-icon>
          </button>
        </div>
        <ul class="flex flex-wrap gap-x-3 gap-y-1.5" aria-label="Legend">
          @for (l of legend; track l.status) {
            <li class="flex items-center gap-1.5 text-[12.5px] leading-none text-muted">
              <app-status-pill [tone]="l.tone"
                ><span aria-hidden="true">{{ l.mark }}</span></app-status-pill
              >
              {{ l.label }}
            </li>
          }
          <li class="flex items-center gap-1.5 text-[12.5px] leading-none text-muted">
            <span class="text-[11px] font-semibold text-primary-text" aria-hidden="true">+1h</span>
            extra hours
          </li>
        </ul>
      </app-list-pane-header>
      @if (store.loading()) {
        <mat-progress-bar mode="indeterminate" aria-label="Loading the calendar" />
      }
      <div class="min-h-0 flex-1 overflow-auto p-4">
        @if (store.loadError(); as error) {
          <p role="alert" class="px-4 py-12 text-center text-sm text-danger">{{ error }}</p>
        } @else if (store.days()) {
          @if (rows().length) {
            <table class="border-separate border-spacing-0 text-[13px] leading-none">
              <caption class="sr-only">
                Attendance for {{ title() }}: one row per person, one column per day, then the
                month's totals
              </caption>
              <thead>
                <tr>
                  <th
                    scope="col"
                    class="sticky left-0 z-[2] bg-bg px-2 py-2 text-left font-medium text-muted"
                  >
                    Staff
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
                    <th scope="col" class="px-2 py-2 text-right font-medium text-muted">
                      {{ c }}
                    </th>
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
                        <a
                          class="flex min-h-10 min-w-9 flex-col items-center justify-center gap-0.5 rounded-card no-underline hover:bg-info-soft"
                          [class.bg-surface]="cell?.status === 'not_employed'"
                          [class.ring-2]="isPicked(r.staffId, d)"
                          [class.ring-primary]="isPicked(r.staffId, d)"
                          [routerLink]="[]"
                          [queryParams]="{ staff: r.staffId, day: d }"
                          queryParamsHandling="merge"
                          [attr.aria-label]="label(r.staffName, d, cell)"
                          [attr.aria-current]="isPicked(r.staffId, d) ? 'true' : null"
                        >
                          @if (cell) {
                            @let chip = chipOf(cell);
                            @if (chip.mark) {
                              <app-status-pill [tone]="chip.tone" aria-hidden="true">{{
                                chip.mark
                              }}</app-status-pill>
                            }
                            @if (cell.extraMin > 0) {
                              <span
                                class="text-[11px] font-semibold text-primary-text"
                                aria-hidden="true"
                                >+{{ extra(cell.extraMin) }}</span
                              >
                            }
                          }
                        </a>
                      </td>
                    }
                    <td class="border-t border-border px-2 text-right tabular-nums">
                      {{ units(r.totals.present) }}
                    </td>
                    <td class="border-t border-border px-2 text-right tabular-nums">
                      {{ r.totals.late }}
                    </td>
                    <td class="border-t border-border px-2 text-right tabular-nums">
                      {{ r.totals.halfDay }}
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
                    <td class="border-t border-border px-2 text-right whitespace-nowrap tabular-nums">
                      {{ hours(r.totals.extraMin) }}
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          } @else {
            <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
              Nobody's attendance is tracked yet. Staff appear here once they are on the team.
            </p>
          }
        }
      </div>
    </section>

    @if (picked(); as p) {
      @if (layout.wideDetail()) {
        <aside
          class="flex h-dvh w-[360px] flex-none flex-col overflow-y-auto border-l border-border bg-bg"
          aria-label="Day details"
        >
          <ng-container [ngTemplateOutlet]="panel" />
        </aside>
      } @else {
        @if (!layout.compact()) {
          <div
            class="fixed inset-0 z-[44] animate-fade bg-overlay"
            aria-hidden="true"
            (click)="closePanel()"
          ></div>
        }
        <section
          role="dialog"
          aria-modal="true"
          aria-label="Day details"
          class="fixed inset-y-0 right-0 z-[45] flex flex-col overflow-y-auto border-l border-border bg-bg shadow-raised"
          [class.w-screen]="layout.compact()"
          [class.w-[min(420px,92vw)]]="!layout.compact()"
          cdkTrapFocus
          [cdkTrapFocusAutoCapture]="true"
          (keydown.escape)="closePanel()"
        >
          <ng-container [ngTemplateOutlet]="panel" />
        </section>
      }
      <ng-template #panel>
        <div
          class="sticky top-0 z-[5] flex h-topbar flex-none items-center gap-2 border-b border-border bg-bg pr-2 pl-5"
        >
          <span class="min-w-0 flex-1 truncate text-sm leading-none font-medium text-muted"
            >Staff / Calendar / {{ p.name }}</span
          >
          <button mat-icon-button type="button" aria-label="Close" (click)="closePanel()">
            <mat-icon aria-hidden="true">close</mat-icon>
          </button>
        </div>
        <div class="flex flex-col gap-4 p-5">
          <div class="flex flex-col gap-2">
            <h2 class="font-display text-[22px] leading-[1.1] font-bold">{{ p.name }}</h2>
            <div class="flex flex-wrap items-center gap-2">
              @if (p.cell) {
                <app-status-pill [tone]="chipOf(p.cell).tone">{{
                  statusWords(p.cell)
                }}</app-status-pill>
              }
              <span class="text-sm leading-[1.3] text-muted">{{ dateOf(p.day) }}</span>
            </div>
          </div>
          @if (p.cell?.status === 'not_employed') {
            <p class="text-[13px] leading-[1.45] text-muted">
              Not employed on this day: before they joined or after they left. It counts for
              nothing in the totals.
            </p>
          } @else if (p.cell; as c) {
            <div class="flex flex-col gap-2.5">
              <app-detail-row label="Scheduled" [value]="hours(c.schedMin)" [muted]="!c.schedMin" />
              <app-detail-row
                [label]="c.open ? 'Worked so far' : 'Worked'"
                [value]="hours(c.workedMin)"
              />
              <app-detail-row label="Regular" [value]="hours(c.regularMin)" />
              <app-detail-row label="Extra" [value]="hours(c.extraMin)" [muted]="!c.extraMin" />
              <app-detail-row label="Late" [value]="c.late ? 'Yes' : 'No'" [muted]="!c.late" />
              <app-detail-row
                label="Left early"
                [value]="c.early ? 'Yes' : 'No'"
                [muted]="!c.early"
              />
              <app-detail-row
                label="Half day"
                [value]="c.halfDay ? 'Yes' : 'No'"
                [muted]="!c.halfDay"
              />
              <app-detail-row label="Present" [value]="units(c.presentUnits) + ' day'" />
              <app-detail-row
                label="Absent"
                [value]="units(c.absentUnits) + ' day'"
                [muted]="!c.absentUnits"
              />
              <app-detail-row
                label="Paid leave"
                [value]="units(c.leavePaid) + ' day'"
                [muted]="!c.leavePaid"
              />
              <app-detail-row
                label="Unpaid leave"
                [value]="units(c.leaveLop) + ' day'"
                [muted]="!c.leaveLop"
              />
              @if (c.holidayName) {
                <app-detail-row label="Holiday" [value]="c.holidayName" />
              }
            </div>
            @if (c.flags.length) {
              <div class="flex flex-wrap gap-1.5" aria-label="Flags">
                @for (f of c.flags; track f) {
                  <app-status-pill [tone]="flagTone(f)">{{ flagLabel(f) }}</app-status-pill>
                }
              </div>
            }
            <app-detail-row
              label="Clock-ins"
              [value]="entriesLabel(c.entries) + (c.open ? ' · on the clock' : '')"
              [muted]="!c.entries"
            />
          } @else {
            <p class="text-[13px] leading-[1.45] text-muted">No figures for this day.</p>
          }
          <a
            class="text-sm font-medium text-primary-text"
            routerLink="/staff/attendance"
            [queryParams]="{ range: 'custom', from: p.day, to: p.day, staff: p.staffId }"
            >Open in the attendance log</a
          >
        </div>
      </ng-template>
    }
  `,
})
export class CalendarPage {
  protected readonly store = inject(CalendarStore);
  protected readonly layout = inject(Layout);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);

  /** `?month=2026-10` (default: this IST month). */
  readonly monthParam = input<string>(undefined, { alias: 'month' });
  /** `?staff=` and `?day=` — the picked cell. */
  readonly staffParam = input<string>(undefined, { alias: 'staff' });
  readonly dayParam = input<string>(undefined, { alias: 'day' });

  protected readonly legend = LEGEND;
  protected readonly totalColumns = [
    'Present',
    'Late',
    'Half-day',
    'Absent',
    'Leave',
    'Worked',
    'Extra',
  ];
  protected readonly units = units;
  protected readonly hours = hoursLong;
  protected readonly extra = extraShort;
  protected readonly chipOf = (d: AttendanceDay) => statusChip(d.status);
  protected readonly label = cellLabel;
  protected readonly dateOf = cellDate;
  protected readonly flagLabel = flagLabel;
  protected readonly flagTone = flagTone;
  protected readonly entriesLabel = entriesLabel;
  protected readonly shiftMonth = shiftMonth;

  private readonly now = injectNow(60_000);
  protected readonly today = computed(() => formatIsoDate(this.now()));
  protected readonly month = computed(() => {
    const m = this.monthParam();
    return m && monthDays(m) ? m : this.today().slice(0, 7);
  });
  protected readonly days = computed(() => monthDays(this.month()) ?? []);
  protected readonly title = computed(() => monthLabel(this.month()));
  protected readonly rows = computed(() => calendarRows(this.store.days() ?? [], this.days()));
  protected readonly picked = computed(() => {
    const staffId = this.staffParam();
    const day = this.dayParam();
    if (!staffId || !day || !this.days().includes(day)) return null;
    const row = this.rows().find((r) => r.staffId === staffId);
    if (!row) return null;
    return { staffId, day, name: row.staffName, cell: row.cells[this.days().indexOf(day)] };
  });

  constructor() {
    effect(() => {
      const days = this.days();
      if (this.arena.current().id && days.length) {
        void this.store.load(days[0], days[days.length - 1]);
      }
    });
    // The permission taken away live (or another arena picked without it): leave.
    effect(() => {
      if (this.arena.loaded() && this.arena.current().id && !this.arena.hasPerm(CALENDAR_PERM)) {
        void this.router.navigateByUrl('/overview');
      }
    });
  }

  protected isPicked(staffId: string, day: string): boolean {
    const p = this.picked();
    return !!p && p.staffId === staffId && p.day === day;
  }

  /** "Thu 15 Oct" → "T". */
  protected weekdayLetter(day: string): string {
    return cellDate(day).charAt(0);
  }

  protected dayNumber(day: string): string {
    return String(Number(day.slice(8)));
  }

  protected statusWords(d: AttendanceDay): string {
    const words = statusChip(d.status).label;
    return words.charAt(0).toUpperCase() + words.slice(1);
  }

  protected pickMonth(value: string): void {
    if (monthDays(value)) this.setParams({ month: value, staff: null, day: null });
  }

  protected closePanel(): void {
    this.setParams({ staff: null, day: null });
  }

  protected setParams(params: Record<string, string | null>): void {
    void this.router.navigate([], { queryParams: params, queryParamsHandling: 'merge' });
  }
}
