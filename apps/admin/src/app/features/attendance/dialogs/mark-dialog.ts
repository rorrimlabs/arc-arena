import { Component, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatOption, MatSelect } from '@angular/material/select';
import { toAppError } from '../../../core/auth/auth-api';
import { Clock } from '../../../core/time/clock';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatCount, formatDays } from '../../../shared/staff/staff-format';
import { addDays, formatIsoDate } from '../../../shared/time/ist';
import { LeaveStore } from '../../leave/data/leave-store';
import { ShiftsStore } from '../../shifts/data/shifts-store';
import { coversDay, isDay, toTimeValue } from '../../shifts/data/shifts.models';
import { AttendanceStore } from '../data/attendance-store';
import { StaffMember, correctionProblem, istInstant } from '../data/attendance.models';

export type MarkKind = 'present' | 'paid_leave' | 'unpaid_leave';

export interface MarkDialogData {
  /** Who may be picked (the manager's own profile left out unless they are the owner). */
  readonly staff: readonly StaffMember[];
  readonly staffId?: string | null;
  readonly day?: string | null;
  readonly kind?: MarkKind;
  /** The login may record leave (leave_approve) / add attendance (attendance_review). */
  readonly canLeave: boolean;
  readonly canAttendance: boolean;
}

export interface MarkDialogResult {
  readonly snack: string;
}

/**
 * Mark attendance: someone was at work without clocking in (attendance.correct `add`, kept with
 * who added it and why), or was on paid or unpaid leave (leave.record: approved at once, every
 * day paid from the allowance or every day loss of pay). The server counts the days and applies
 * every rule; this only collects the choice.
 */
@Component({
  selector: 'app-mark-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatSelect,
    MatOption,
    MatButton,
    MatButtonToggleGroup,
    MatButtonToggle,
  ],
  template: `
    <h2 mat-dialog-title>Mark attendance</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <mat-form-field>
            <mat-label>Employee</mat-label>
            <mat-select
              [value]="staffId()"
              (selectionChange)="pickStaff($event.value)"
            >
              @for (s of data.staff; track s.id) {
                <mat-option [value]="s.id">{{ s.name }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          @if (kinds().length > 1) {
            <mat-button-toggle-group
              aria-label="What happened"
              hideSingleSelectionIndicator
              [value]="kind()"
              (change)="kind.set($event.value); error.set('')"
            >
              @for (k of kinds(); track k.value) {
                <mat-button-toggle [value]="k.value">{{ k.label }}</mat-button-toggle>
              }
            </mat-button-toggle-group>
          }
          @if (kind() === 'present') {
            <mat-form-field>
              <mat-label>Date</mat-label>
              <input
                matInput
                type="date"
                [max]="today"
                [value]="day()"
                (input)="pickDay($any($event.target).value)"
              />
            </mat-form-field>
            <div class="grid grid-cols-2 gap-3">
              <mat-form-field>
                <mat-label>Clock-in</mat-label>
                <input
                  matInput
                  type="time"
                  [value]="inTime()"
                  (input)="inTime.set($any($event.target).value); error.set('')"
                />
              </mat-form-field>
              <mat-form-field>
                <mat-label>Clock-out</mat-label>
                <input
                  matInput
                  type="time"
                  [value]="outTime()"
                  (input)="outTime.set($any($event.target).value); error.set('')"
                />
                @if (overnight()) {
                  <mat-hint>Next day</mat-hint>
                }
              </mat-form-field>
            </div>
          } @else {
            <div class="grid grid-cols-2 gap-3">
              <mat-form-field>
                <mat-label>From</mat-label>
                <input
                  matInput
                  type="date"
                  [value]="day()"
                  (input)="pickDay($any($event.target).value)"
                />
              </mat-form-field>
              <mat-form-field>
                <mat-label>To</mat-label>
                <input
                  matInput
                  type="date"
                  [min]="day()"
                  [value]="to()"
                  (input)="to.set($any($event.target).value); error.set('')"
                />
              </mat-form-field>
            </div>
            @if (balanceText(); as b) {
              <p class="-mt-2 text-[13px] leading-[1.4] text-muted">{{ b }}</p>
            }
          }
          <mat-form-field>
            <mat-label>Note (optional)</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="500"
              [value]="note()"
              (input)="note.set($any($event.target).value); error.set('')"
            />
            <mat-hint>Kept with the record, with your name</mat-hint>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">Save</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class MarkDialog {
  protected readonly data = inject<MarkDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<MarkDialog, MarkDialogResult>>(MatDialogRef);
  private readonly attendance = inject(AttendanceStore);
  private readonly leave = inject(LeaveStore);
  private readonly shifts = inject(ShiftsStore);
  private readonly clock = inject(Clock);

  protected readonly today = formatIsoDate(this.clock.now());
  protected readonly kinds = computed(() => [
    ...(this.data.canAttendance ? [{ value: 'present' as const, label: 'Present' }] : []),
    ...(this.data.canLeave
      ? [
          { value: 'paid_leave' as const, label: 'Paid leave' },
          { value: 'unpaid_leave' as const, label: 'Unpaid leave' },
        ]
      : []),
  ]);
  protected readonly kind = signal<MarkKind>(
    this.data.kind ?? (this.data.canAttendance ? 'present' : 'paid_leave'),
  );
  protected readonly staffId = signal(this.data.staffId ?? '');
  protected readonly day = signal(this.data.day ?? this.today);
  protected readonly to = signal(this.data.day ?? this.today);
  protected readonly inTime = signal('');
  protected readonly outTime = signal('');
  protected readonly note = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  /** A clock-out at or before the clock-in ends the next day (as a shift does). */
  protected readonly overnight = computed(
    () => !!this.inTime() && !!this.outTime() && this.outTime() <= this.inTime(),
  );
  protected readonly balanceText = computed(() => {
    if (this.kind() !== 'paid_leave') return null;
    const b = this.leave.balanceOf().get(this.staffId());
    if (!b) return null;
    return b.balance > 0
      ? `${formatDays(b.balance)} of paid leave left this year (${formatCount(b.allowance)} a year)`
      : 'No paid leave left this year: these days would take the balance below zero';
  });

  constructor() {
    this.fillShiftTimes();
  }

  protected pickStaff(id: string): void {
    this.staffId.set(id);
    this.error.set('');
    this.fillShiftTimes();
  }

  protected pickDay(day: string): void {
    this.day.set(day);
    if (!this.to() || this.to() < day) this.to.set(day);
    this.error.set('');
    this.fillShiftTimes();
  }

  /**
   * Suggest the person's shift times that day: only when exactly one shift covers it (with a
   * split shift, or none, the times are left for the manager to type).
   */
  private fillShiftTimes(): void {
    const day = this.day();
    const covering = this.shifts
      .assignments()
      .filter((x) => x.staffId === this.staffId() && isDay(day) && coversDay(x, day));
    const shift =
      covering.length === 1
        ? this.shifts.shifts().find((s) => s.id === covering[0].shiftId)
        : undefined;
    this.inTime.set(shift ? toTimeValue(shift.startMin) : '');
    this.outTime.set(shift ? toTimeValue(shift.endMin) : '');
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const name = this.data.staff.find((s) => s.id === this.staffId())?.name;
    if (!this.staffId() || !name) {
      this.error.set('Pick the employee');
      return;
    }
    if (!isDay(this.day())) {
      this.error.set('Pick the date');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      if (this.kind() === 'present') {
        const inAt = istInstant(this.day(), this.inTime());
        const outAt = istInstant(
          this.overnight() ? addDays(this.day(), 1) : this.day(),
          this.outTime(),
        );
        const reason = this.note().trim() || 'Marked present from the dashboard';
        const problem = correctionProblem(
          { inAt, outAt, reason, outRequired: true },
          this.clock.now(),
        );
        if (problem || !inAt || !outAt) {
          this.error.set(problem ?? 'Pick the clock-in and clock-out times');
          return;
        }
        await this.attendance.correct({
          action: 'add',
          staff_id: this.staffId(),
          in_at: inAt,
          out_at: outAt,
          reason,
        });
        this.ref.close({ snack: `${name} marked present` });
      } else {
        const to = isDay(this.to()) && this.to() >= this.day() ? this.to() : this.day();
        const paid = this.kind() === 'paid_leave';
        await this.leave.record({
          id: crypto.randomUUID(),
          staffId: this.staffId(),
          fromDate: this.day(),
          toDate: to,
          halfDay: 'none',
          paid,
          reason: this.note(),
        });
        this.ref.close({ snack: `${paid ? 'Paid' : 'Unpaid'} leave recorded for ${name}` });
      }
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
