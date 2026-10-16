import { Component, computed, inject, input, output } from '@angular/core';
import { MatIconButton } from '@angular/material/button';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatInput } from '@angular/material/input';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { addDays } from '../../../shared/time/ist';
import { ShiftsStore } from '../data/shifts-store';
import { formatDay, formatWeekday, isDay, rosterRows, weekOf } from '../data/shifts.models';

/**
 * The weekly roster (read-only): Monday to Sunday of the week containing `day`, one row per
 * staff member, each cell listing the shifts they work that day from their assignments and the
 * shifts' days. An empty cell is a week off. Staff holidays are named in the column heading.
 */
@Component({
  selector: 'app-roster-view',
  imports: [DetailPane, DetailSection, MatFormField, MatLabel, MatInput, MatIconButton, MatIcon],
  template: `
    <app-detail-pane
      crumb="Staff / Shifts / Weekly roster"
      icon="calendar_view_week"
      heading="Weekly roster"
      [subtitle]="range()"
      (closed)="closed.emit()"
    >
      <div class="flex flex-wrap items-center gap-2">
        <button
          mat-icon-button
          type="button"
          aria-label="Previous week"
          (click)="dayChange.emit(shift(-7))"
        >
          <mat-icon aria-hidden="true">chevron_left</mat-icon>
        </button>
        <mat-form-field class="arena-dense w-48">
          <mat-label>Week of</mat-label>
          <input
            matInput
            type="date"
            [value]="day()"
            (change)="pick($any($event.target).value)"
          />
        </mat-form-field>
        <button
          mat-icon-button
          type="button"
          aria-label="Next week"
          (click)="dayChange.emit(shift(7))"
        >
          <mat-icon aria-hidden="true">chevron_right</mat-icon>
        </button>
      </div>
      <app-detail-section>
        <div class="overflow-x-auto">
          <table class="w-full min-w-[640px] border-collapse text-sm leading-[1.3]">
            <caption class="sr-only">
              Shifts worked each day, {{ range() }}
            </caption>
            <thead>
              <tr>
                <th scope="col" class="px-2 py-2 text-left font-medium text-muted">Staff</th>
                @for (c of columns(); track c.day) {
                  <th scope="col" class="px-2 py-2 text-left align-top font-medium">
                    <span class="block">{{ c.label }}</span>
                    @if (c.holiday) {
                      <span class="block text-[12px] font-normal text-warning">{{ c.holiday }}</span>
                    }
                  </th>
                }
              </tr>
            </thead>
            <tbody>
              @for (r of rows(); track r.staff.id) {
                <tr class="border-t border-border">
                  <th scope="row" class="px-2 py-2 text-left font-semibold whitespace-nowrap">
                    {{ r.staff.name }}
                  </th>
                  @for (cell of r.cells; track $index) {
                    <td class="px-2 py-2 align-top">
                      @for (name of cell; track name) {
                        <span class="block">{{ name }}</span>
                      } @empty {
                        <span class="text-subtle">Week off</span>
                      }
                    </td>
                  }
                </tr>
              } @empty {
                <tr>
                  <td colspan="8" class="px-2 py-6 text-center text-muted">No staff yet.</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class RosterView {
  private readonly store = inject(ShiftsStore);

  /** Any IST date of the week to show. */
  readonly day = input.required<string>();
  readonly dayChange = output<string>();
  readonly closed = output<void>();

  protected readonly days = computed(() => weekOf(this.day()));
  protected readonly range = computed(() => {
    const d = this.days();
    return `${formatDay(d[0])} – ${formatDay(d[6])}`;
  });
  protected readonly columns = computed(() => {
    const holidays = new Map(this.store.holidays().map((h) => [h.day, h.name]));
    return this.days().map((day) => ({
      day,
      label: formatWeekday(day),
      holiday: holidays.get(day) ?? '',
    }));
  });
  protected readonly rows = computed(() => {
    const data = this.store.data();
    return data ? rosterRows(data, this.days()) : [];
  });

  protected shift(days: number): string {
    return addDays(this.day(), days);
  }

  protected pick(value: string): void {
    if (isDay(value)) this.dayChange.emit(value);
  }
}
