import { Component, computed, inject, input, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { Router, RouterLink } from '@angular/router';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatMinutes, formatTime } from '../../../shared/time/ist';
import { cellDate, units } from '../../calendar/data/calendar.models';
import { initials } from '../../users/components/user-format';
import { LogRow, flagLabel, flagTone } from '../data/attendance.models';
import { EntryActions } from '../data/entry-actions';
import { DayRow, reviewReason, visibleFlags } from '../data/today.models';

/**
 * One person's day: the status in plain words, clock-in, clock-out and worked hours (all from
 * the server), each stretch they clocked with why it needs review and the actions it allows
 * (accept, correct, void), and marking them present or on leave. The day's figures (scheduled,
 * regular and extra hours, late, units) and each entry's evidence stay one click away.
 */
@Component({
  selector: 'app-day-detail',
  imports: [DetailPane, DetailRow, StatTile, StatusPill, MatButton, MatIcon, RouterLink],
  template: `
    @let r = row();
    @let d = r.day;
    <app-detail-pane
      [crumb]="'Staff / Attendance / ' + r.staffName"
      [heading]="r.staffName"
      [subtitle]="date()"
      [initials]="initialsOf(r.staffName)"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="r.label.tone">{{ r.label.label }}</app-status-pill>
      @if (r.label.note) {
        <app-status-pill chip tone="info">{{ r.label.note }}</app-status-pill>
      }
      <div stats class="grid grid-cols-3 gap-3">
        <app-stat-tile label="Clock-in" [value]="r.firstIn ? time(r.firstIn) : '—'" />
        <app-stat-tile
          label="Clock-out"
          [value]="d.open ? 'Working' : r.lastOut ? time(r.lastOut) : '—'"
        />
        <app-stat-tile [label]="d.open ? 'So far' : 'Hours'" [value]="hours(d.workedMin)" />
      </div>

      @if (canMark()) {
        <div class="flex flex-wrap gap-2">
          @if (canAttendance() && !r.entries.length) {
            <button mat-flat-button type="button" (click)="mark.emit('present')">
              <mat-icon aria-hidden="true">how_to_reg</mat-icon>Mark present
            </button>
          } @else if (canAttendance()) {
            <button mat-stroked-button type="button" (click)="mark.emit('present')">
              <mat-icon aria-hidden="true">more_time</mat-icon>Add hours
            </button>
          }
          @if (canLeave() && r.label.word !== 'on_leave' && r.label.word !== 'day_off') {
            <button mat-stroked-button type="button" (click)="mark.emit('paid_leave')">
              <mat-icon aria-hidden="true">event_available</mat-icon>Record leave
            </button>
          }
        </div>
      }
      @if (ownRecord()) {
        <p role="note" class="text-[13px] leading-[1.45] text-muted">
          This is your own attendance: someone else with Review attendance changes it.
        </p>
      }

      @if (r.entries.length) {
        <ul class="flex flex-col gap-2" aria-label="Clock-ins">
          @for (e of r.entries; track e.entry.id) {
            <li class="flex flex-col gap-2.5 rounded-card border border-border p-4">
              <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span class="text-sm font-semibold tabular-nums">{{ span(e) }}</span>
                @if (e.entry.source === 'manual') {
                  <span class="text-[12.5px] text-muted">Added by hand</span>
                }
                <a
                  class="ml-auto text-[13px] font-medium text-primary-text"
                  [routerLink]="[]"
                  [queryParams]="{ id: e.entry.id }"
                  queryParamsHandling="merge"
                  >Details</a
                >
              </div>
              @if (e.entry.review === 'pending') {
                <p class="text-[13px] leading-[1.4] font-medium text-warning">
                  {{ reasonOf(e) }}
                </p>
              }
              @if (flagsOf(e).length) {
                <div class="flex flex-wrap gap-1.5">
                  @for (f of flagsOf(e); track f) {
                    <app-status-pill [tone]="flagTone(f)">{{ flagLabel(f) }}</app-status-pill>
                  }
                </div>
              }
              @if (canAttendance() && !ownRecord()) {
                <div class="arena-compact -ml-2 flex flex-wrap gap-1">
                  @if (e.entry.review === 'pending') {
                    <button mat-button type="button" (click)="actions.accept(e)">
                      <mat-icon aria-hidden="true">check</mat-icon>Accept
                    </button>
                  }
                  <button mat-button type="button" (click)="correct(e)">
                    <mat-icon aria-hidden="true">edit_calendar</mat-icon>Correct
                  </button>
                  <button
                    mat-button
                    type="button"
                    class="danger-action"
                    (click)="actions.voidEntry(e)"
                  >
                    <mat-icon aria-hidden="true">block</mat-icon>Void
                  </button>
                </div>
              }
            </li>
          }
        </ul>
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
          How this day counts
        </summary>
        <div class="flex flex-col gap-2.5 border-t border-border p-4">
          <app-detail-row label="Scheduled" [value]="hours(d.schedMin)" [muted]="!d.schedMin" />
          <app-detail-row label="Regular" [value]="hours(d.regularMin)" />
          <app-detail-row label="Extra hours" [value]="hours(d.extraMin)" [muted]="!d.extraMin" />
          <app-detail-row label="Late" [value]="d.late ? 'Yes' : 'No'" [muted]="!d.late" />
          <app-detail-row label="Left early" [value]="d.early ? 'Yes' : 'No'" [muted]="!d.early" />
          <app-detail-row label="Present" [value]="units(d.presentUnits) + ' day'" />
          <app-detail-row
            label="Absent"
            [value]="units(d.absentUnits) + ' day'"
            [muted]="!d.absentUnits"
          />
          <app-detail-row
            label="Paid leave"
            [value]="units(d.leavePaid) + ' day'"
            [muted]="!d.leavePaid"
          />
          <app-detail-row
            label="Unpaid leave"
            [value]="units(d.leaveLop) + ' day'"
            [muted]="!d.leaveLop"
          />
          <p class="text-[12.5px] leading-[1.4] text-muted">
            Worked out by the server with the venue's working-hour rules; payroll uses the same
            figures.
          </p>
        </div>
      </details>
    </app-detail-pane>
  `,
})
export class DayDetail {
  protected readonly actions = inject(EntryActions);
  private readonly router = inject(Router);

  readonly row = input.required<DayRow>();
  /** The login may add and correct attendance (attendance_review). */
  readonly canAttendance = input(false);
  /** The login may record leave (leave_approve). */
  readonly canLeave = input(false);
  /** This is the login's own record and they are not the owner. */
  readonly ownRecord = input(false);
  readonly locationChecked = input(true);
  readonly closed = output<void>();
  /** Mark present / record leave for this person and day. */
  readonly mark = output<'present' | 'paid_leave'>();

  protected readonly initialsOf = initials;
  protected readonly time = formatTime;
  protected readonly units = units;
  protected readonly flagLabel = flagLabel;
  protected readonly flagTone = flagTone;
  protected readonly date = computed(() => cellDate(this.row().day.workDate));
  protected readonly canMark = computed(
    () => !this.ownRecord() && (this.canAttendance() || this.canLeave()),
  );

  protected hours(min: number): string {
    return min > 0 ? formatMinutes(min) : '—';
  }

  protected span(e: LogRow): string {
    const out = e.entry.outAt ? formatTime(e.entry.outAt) : 'now';
    return `${formatTime(e.entry.inAt)} – ${out}`;
  }

  protected reasonOf(e: LogRow): string {
    return reviewReason(e.entry, this.locationChecked());
  }

  protected flagsOf(e: LogRow): string[] {
    return visibleFlags(e.entry.flags, this.locationChecked()).filter(
      (f) => f !== 'manual' && f !== 'auto_out',
    );
  }

  protected async correct(e: LogRow): Promise<void> {
    await this.actions.correct(e);
  }
}
