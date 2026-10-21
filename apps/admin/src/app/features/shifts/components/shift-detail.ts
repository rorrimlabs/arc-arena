import { Component, computed, inject, input, output, signal } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatMinutes } from '../../../shared/time/ist';
import { WEEKDAYS } from '../../settings/data/work-hours';
import { ShiftsStore } from '../data/shifts-store';
import {
  Shift,
  ShiftAssignment,
  assignmentDates,
  clockLabel,
  crossesMidnight,
  daysLabel,
  shiftLength,
  shiftTimes,
} from '../data/shifts.models';
import { AssignDialog, AssignDialogData, AssignDialogResult } from '../dialogs/assign-dialog';
import { ShiftDialog, ShiftDialogData, ShiftDialogResult } from '../dialogs/shift-dialog';

/**
 * One shift: its times (a shift ending after midnight says "next day"), paid length, days and
 * break; who is assigned with their effective dates (assign, change dates, remove). Changes
 * need the Settings permission; without it the shift is shown read-only.
 */
@Component({
  selector: 'app-shift-detail',
  imports: [
    DetailPane,
    DetailSection,
    StatTile,
    StatusPill,
    MatButton,
    MatIconButton,
    MatIcon,
  ],
  template: `
    @let s = shift();
    <app-detail-pane
      [crumb]="'Staff / Shifts / ' + s.name"
      icon="schedule"
      [heading]="s.name"
      [subtitle]="times()"
      (closed)="closed.emit()"
    >
      <div actions class="arena-compact flex gap-2">
        <button mat-stroked-button type="button" [disabled]="!canEdit()" (click)="edit()">
          <mat-icon aria-hidden="true">edit</mat-icon>Edit
        </button>
      </div>
      @if (!s.active) {
        <app-status-pill chip tone="warning">Not in use</app-status-pill>
      }
      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
        <app-stat-tile label="Starts" [value]="clock(s.startMin)" />
        <app-stat-tile [label]="overnight() ? 'Ends next day' : 'Ends'" [value]="clock(s.endMin)" />
        <app-stat-tile label="Paid length" [value]="length()" />
        <app-stat-tile label="Unpaid break" [value]="s.breakMin ? minutes(s.breakMin) : 'None'" />
      </div>

      @if (!canEdit()) {
        <p role="note" class="text-[13px] leading-[1.45] text-muted">
          Viewing only: changing shifts needs the Settings permission.
        </p>
      }

      <app-detail-section heading="Days" [subtitle]="days()">
        <ul class="flex flex-wrap gap-1.5" aria-label="Days of the week">
          @for (w of weekdays; track w.value) {
            <li>
              <app-status-pill [tone]="s.days.includes(w.value) ? 'primary' : 'info'">
                <span aria-hidden="true">{{ w.short }}</span>
                <span class="sr-only"
                  >{{ w.label }}: {{ s.days.includes(w.value) ? 'works' : 'off' }}</span
                >
              </app-status-pill>
            </li>
          }
        </ul>
      </app-detail-section>

      <app-detail-section
        heading="Assigned staff"
        subtitle="A day none of a person's shifts covers is their week off."
      >
        <ul class="flex flex-col gap-2" aria-label="Assigned staff">
          @for (a of assigned(); track a.id) {
            <li class="flex items-center gap-2" role="group" [attr.aria-label]="nameOf(a)">
              <span class="flex min-w-0 flex-1 flex-col gap-1">
                <span class="truncate text-[15px] leading-[1.3]">{{ nameOf(a) }}</span>
                <span class="text-[13px] leading-[1.3] text-muted">{{ dates(a) }}</span>
              </span>
              <button
                mat-icon-button
                type="button"
                [attr.aria-label]="'Change dates for ' + nameOf(a)"
                [disabled]="busy() || !canEdit()"
                (click)="changeDates(a)"
              >
                <mat-icon aria-hidden="true">edit_calendar</mat-icon>
              </button>
              <button
                mat-icon-button
                type="button"
                [attr.aria-label]="'End ' + nameOf(a) + ' on ' + s.name"
                [disabled]="busy() || !canEdit()"
                (click)="remove(a)"
              >
                <mat-icon aria-hidden="true">person_remove</mat-icon>
              </button>
            </li>
          } @empty {
            <li class="text-[13px] leading-[1.45] text-muted">Nobody works this shift yet.</li>
          }
        </ul>
        <div>
          <button mat-stroked-button type="button" [disabled]="!canEdit()" (click)="assign()">
            <mat-icon aria-hidden="true">person_add</mat-icon>Assign staff
          </button>
        </div>
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class ShiftDetail {
  protected readonly canEdit = inject(ArenaContext).canEdit;
  private readonly store = inject(ShiftsStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly shift = input.required<Shift>();
  readonly closed = output<void>();

  protected readonly weekdays = WEEKDAYS;
  protected readonly clock = clockLabel;
  protected readonly minutes = formatMinutes;
  protected readonly dates = assignmentDates;
  protected readonly times = computed(() => shiftTimes(this.shift()));
  protected readonly overnight = computed(() => crossesMidnight(this.shift()));
  protected readonly length = computed(() => formatMinutes(shiftLength(this.shift())));
  protected readonly days = computed(() => daysLabel(this.shift().days));
  /** This shift's assignments, by name, then first day. */
  protected readonly assigned = computed(() =>
    this.store
      .assignments()
      .filter((a) => a.shiftId === this.shift().id)
      .sort(
        (a, b) =>
          this.nameOf(a).localeCompare(this.nameOf(b)) ||
          a.effectiveFrom.localeCompare(b.effectiveFrom),
      ),
  );
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected nameOf(a: ShiftAssignment): string {
    return this.store.staffNames().get(a.staffId) ?? 'Former staff';
  }

  protected edit(): void {
    this.dialog
      .open<ShiftDialog, ShiftDialogData, ShiftDialogResult>(ShiftDialog, {
        data: { shift: this.shift() },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => {
        if (r) this.say(r.snack);
      });
  }

  protected assign(): void {
    this.openAssign({ shift: this.shift() });
  }

  protected changeDates(assignment: ShiftAssignment): void {
    this.openAssign({ shift: this.shift(), assignment });
  }

  private openAssign(data: AssignDialogData): void {
    this.dialog
      .open<AssignDialog, AssignDialogData, AssignDialogResult>(AssignDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => {
        if (r) this.say(r.snack);
      });
  }

  /** shift.unassign, after a confirmation. */
  protected remove(a: ShiftAssignment): void {
    const name = this.nameOf(a);
    const data: ConfirmDialogData = {
      title: `End ${name} on ${this.shift().name}?`,
      message: `The assignment (${assignmentDates(a)}) ends yesterday: the days already worked keep this shift, and from today they are week offs unless another shift covers them. One that has not started yet is removed.`,
      confirm: 'End assignment',
      danger: true,
    };
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        this.busy.set(true);
        this.error.set('');
        try {
          await this.store.unassign(a.id);
          this.say(`${name} taken off ${this.shift().name} from today`);
        } catch (e) {
          this.error.set(toAppError(e).message);
        } finally {
          this.busy.set(false);
        }
      });
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
