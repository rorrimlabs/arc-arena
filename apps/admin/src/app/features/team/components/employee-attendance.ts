import { Component, computed, effect, inject, input, signal } from '@angular/core';
import { MatIconButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { Router, RouterLink } from '@angular/router';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Clock } from '../../../core/time/clock';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { formatIsoDate } from '../../../shared/time/ist';
import { PersonMonth } from '../../attendance/components/person-month';
import { CalendarApi } from '../../calendar/data/calendar-api';
import {
  AttendanceDay,
  monthDays,
  monthLabel,
  shiftMonth,
} from '../../calendar/data/calendar.models';

/**
 * One employee's attendance on Team: a month at a time from the server's attendance_days for
 * that person (the same figures as Attendance and payroll). A day opens on Attendance, where
 * it can be corrected.
 */
@Component({
  selector: 'app-employee-attendance',
  imports: [DetailSection, PersonMonth, MatIconButton, MatIcon, RouterLink],
  template: `
    <app-detail-section>
      <div class="-my-1 flex items-center gap-1">
        <button
          mat-icon-button
          type="button"
          aria-label="Previous month"
          (click)="month.set(shift(month(), -1))"
        >
          <mat-icon aria-hidden="true">chevron_left</mat-icon>
        </button>
        <span class="flex-1 text-center text-sm font-medium" aria-live="polite">{{
          title()
        }}</span>
        <button
          mat-icon-button
          type="button"
          aria-label="Next month"
          [disabled]="month() >= today.slice(0, 7)"
          (click)="month.set(shift(month(), 1))"
        >
          <mat-icon aria-hidden="true">chevron_right</mat-icon>
        </button>
      </div>
      @if (error()) {
        <p role="alert" class="text-[13px] text-danger">{{ error() }}</p>
      } @else if (cells()) {
        <app-person-month
          [days]="days()"
          [cells]="cells()!"
          [name]="name()"
          [monthName]="title()"
          [today]="today"
          (pick)="open($event)"
        />
      } @else {
        <p class="text-[13px] text-muted">Loading…</p>
      }
      <a
        class="text-sm font-medium text-primary-text"
        routerLink="/staff/attendance"
        [queryParams]="{ view: 'calendar', month: month(), staff: staffId() }"
        >Open in Attendance</a
      >
    </app-detail-section>
  `,
})
export class EmployeeAttendance {
  private readonly api = inject(CalendarApi);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);

  readonly staffId = input.required<string>();
  readonly name = input.required<string>();

  protected readonly today = formatIsoDate(inject(Clock).now());
  protected readonly shift = shiftMonth;
  protected readonly month = signal(this.today.slice(0, 7));
  protected readonly days = computed(() => monthDays(this.month()) ?? []);
  protected readonly title = computed(() => monthLabel(this.month()));
  private readonly loaded = signal<readonly AttendanceDay[] | null>(null);
  protected readonly error = signal('');
  protected readonly cells = computed(() => {
    const rows = this.loaded();
    if (!rows) return null;
    const byDay = new Map(rows.map((d) => [d.workDate, d]));
    return this.days().map((d) => byDay.get(d) ?? null);
  });
  private latest = 0;

  constructor() {
    effect(() => {
      const days = this.days();
      const staff = this.staffId();
      const arena = this.arena.current().id;
      if (!arena || !days.length) return;
      const call = ++this.latest;
      this.loaded.set(null);
      this.error.set('');
      this.api.days(arena, days[0], days[days.length - 1], staff).then(
        (rows) => call === this.latest && this.loaded.set(rows),
        (e) => call === this.latest && this.error.set(toAppError(e).message),
      );
    });
  }

  protected open(day: string): void {
    void this.router.navigate(['/staff/attendance'], {
      queryParams: { view: 'calendar', month: this.month(), staff: this.staffId(), day },
    });
  }
}
