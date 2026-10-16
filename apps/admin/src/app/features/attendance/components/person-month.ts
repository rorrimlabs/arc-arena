import { Component, computed, input, output } from '@angular/core';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { isoWeekday } from '../../../shared/staff/staff-format';
import { formatMinutes } from '../../../shared/time/ist';
import {
  AttendanceDay,
  LEGEND,
  cellLabel,
  staffTotals,
  statusChip,
  units,
} from '../../calendar/data/calendar.models';

/**
 * One person's month as a small calendar (Monday first), each day marked with the server's
 * status, then the month's totals. Picking a day emits it; days still to come stay blank.
 */
@Component({
  selector: 'app-person-month',
  imports: [StatusPill],
  host: { class: 'flex flex-col gap-4' },
  template: `
    <div
      class="grid max-w-md grid-cols-7 gap-1 text-[13px]"
      role="group"
      [attr.aria-label]="name() + ', ' + monthName()"
    >
      @for (w of weekLetters; track $index) {
        <span class="py-1 text-center text-[11px] font-medium text-muted" aria-hidden="true">{{
          w
        }}</span>
      }
      @for (pad of padding(); track $index) {
        <span aria-hidden="true"></span>
      }
      @for (d of days(); track d; let i = $index) {
        @let cell = cells()[i];
        <button
          type="button"
          class="flex min-h-12 flex-col items-center justify-center gap-0.5 rounded-card hover:bg-info-soft"
          [class.bg-surface]="cell?.status === 'not_employed'"
          [class.ring-2]="d === picked()"
          [class.ring-primary]="d === picked()"
          [attr.aria-label]="label(name(), d, cell)"
          [attr.aria-pressed]="d === picked()"
          (click)="pick.emit(d)"
        >
          <span class="text-[11px] text-muted" [class.font-bold]="d === today()">{{
            dayNumber(d)
          }}</span>
          @if (cell && markOf(cell)) {
            <app-status-pill [tone]="chip(cell).tone" aria-hidden="true">{{
              markOf(cell)
            }}</app-status-pill>
          }
        </button>
      }
    </div>
    <dl class="grid max-w-md grid-cols-4 gap-2 text-center">
      @for (t of totals(); track t.label) {
        <div class="rounded-card bg-surface px-2 py-2.5">
          <dt class="text-[11.5px] text-muted">{{ t.label }}</dt>
          <dd class="pt-1 text-sm font-semibold tabular-nums">{{ t.value }}</dd>
        </div>
      }
    </dl>
    <ul class="flex flex-wrap gap-x-3 gap-y-1.5" aria-label="Legend">
      @for (l of legend; track l.status) {
        <li class="flex items-center gap-1.5 text-[12px] leading-none text-muted">
          <app-status-pill [tone]="l.tone"
            ><span aria-hidden="true">{{ l.mark }}</span></app-status-pill
          >
          {{ l.label }}
        </li>
      }
    </ul>
  `,
})
export class PersonMonth {
  /** The month's IST days, in order, and the person's day for each (null: no figures). */
  readonly days = input.required<readonly string[]>();
  readonly cells = input.required<readonly (AttendanceDay | null)[]>();
  readonly name = input.required<string>();
  readonly monthName = input('');
  readonly today = input.required<string>();
  readonly picked = input<string | null>(null);
  readonly pick = output<string>();

  protected readonly legend = LEGEND.filter(
    (l) => l.status !== 'upcoming' && l.status !== 'half_leave',
  );
  protected readonly weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  protected readonly label = cellLabel;
  protected readonly chip = (d: AttendanceDay) => statusChip(d.status);
  protected readonly padding = computed(() => {
    const first = this.days()[0];
    return first ? Array.from({ length: isoWeekday(first) - 1 }) : [];
  });
  protected readonly totals = computed(() => {
    const t = staffTotals(this.cells().filter((c): c is AttendanceDay => !!c));
    return [
      { label: 'Present', value: units(t.present) },
      { label: 'Absent', value: units(t.absent) },
      { label: 'Leave', value: units(t.leave) },
      { label: 'Hours', value: t.workedMin > 0 ? formatMinutes(t.workedMin) : '0h' },
    ];
  });

  protected markOf(d: AttendanceDay): string {
    return d.status === 'upcoming' && !d.open ? '' : statusChip(d.status).mark;
  }

  protected dayNumber(day: string): string {
    return String(Number(day.slice(8)));
  }
}
