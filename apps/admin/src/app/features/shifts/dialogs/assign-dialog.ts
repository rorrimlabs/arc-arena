import { Component, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
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
import { formatIsoDate } from '../../../shared/time/ist';
import { ShiftsStore } from '../data/shifts-store';
import {
  SHIFT_MESSAGES,
  Shift,
  ShiftAssignment,
  assignmentDates,
  isDay,
  overlappingAssignment,
  shiftTimes,
} from '../data/shifts.models';

export interface AssignDialogData {
  /** Absent: the shift is picked in the dialog (opened from a person on Team). */
  readonly shift?: Shift;
  /** Absent: assign someone. Present: change this assignment's dates. */
  readonly assignment?: ShiftAssignment;
  /** The person picked to start with (opened from a person on Team). */
  readonly staffId?: string;
}

export interface AssignDialogResult {
  readonly snack: string;
}

/** What is wrong with an assignment as typed, in plain words (null when nothing). */
export function assignmentProblem(
  a: ShiftAssignment,
  all: readonly ShiftAssignment[],
): string | null {
  if (!a.staffId) return 'Pick who works this shift';
  if (!a.shiftId) return 'Pick the shift';
  if (!isDay(a.effectiveFrom)) return 'Pick the first day';
  if (a.effectiveTo !== null && !isDay(a.effectiveTo)) return 'Pick a valid last day, or clear it';
  if (a.effectiveTo !== null && a.effectiveTo < a.effectiveFrom) {
    return 'The last day must be on or after the first day';
  }
  const other = overlappingAssignment(a, all);
  if (other) {
    return `${SHIFT_MESSAGES['assignment_overlap']} (${assignmentDates(other)})`;
  }
  return null;
}

/**
 * Assign a staff member to a shift with effective dates (shift.assign; a new assignment gets a
 * client uuid, a date change keeps its id). The last day is optional (open-ended). A person can
 * hold several shifts at once, but not the same shift twice over the same days.
 */
@Component({
  selector: 'app-assign-dialog',
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
  ],
  template: `
    <h2 mat-dialog-title>
      @if (data.shift) {
        {{ editing ? 'Change dates' : 'Assign staff' }} · {{ data.shift.name }}
      } @else {
        Assign a shift
      }
    </h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <mat-form-field>
            <mat-label>Staff member</mat-label>
            <mat-select
              [disabled]="editing"
              [value]="staffId()"
              (selectionChange)="staffId.set($event.value); error.set('')"
            >
              @for (s of staff(); track s.id) {
                <mat-option [value]="s.id">{{ s.name }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          @if (!data.shift) {
            <mat-form-field>
              <mat-label>Shift</mat-label>
              <mat-select
                [value]="shiftId()"
                (selectionChange)="shiftId.set($event.value); error.set('')"
              >
                @for (s of shifts(); track s.id) {
                  <mat-option [value]="s.id">{{ s.name }} · {{ times(s) }}</mat-option>
                }
              </mat-select>
              <mat-hint>A day with no shift is a day off</mat-hint>
            </mat-form-field>
          }
          <div class="grid grid-cols-2 gap-3">
            <mat-form-field>
              <mat-label>From</mat-label>
              <input
                matInput
                type="date"
                [value]="from()"
                (input)="from.set($any($event.target).value); error.set('')"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>To (optional)</mat-label>
              <input
                matInput
                type="date"
                [value]="to()"
                [min]="from()"
                (input)="to.set($any($event.target).value); error.set('')"
              />
              <mat-hint>Empty: no end date</mat-hint>
            </mat-form-field>
          </div>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save' : 'Assign' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class AssignDialog {
  protected readonly data = inject<AssignDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<AssignDialog, AssignDialogResult>>(MatDialogRef);
  private readonly store = inject(ShiftsStore);

  protected readonly editing = !!this.data.assignment;
  /** Active staff, plus the assigned person when editing (even if switched off since). */
  protected readonly staff = computed(() =>
    this.store.staff().filter((s) => s.active || s.id === this.data.assignment?.staffId),
  );
  protected readonly staffId = signal(this.data.assignment?.staffId ?? this.data.staffId ?? '');
  protected readonly shifts = computed(() => this.store.shifts().filter((s) => s.active));
  protected readonly shiftId = signal(
    this.data.shift?.id ??
      (this.store.shifts().filter((s) => s.active).length === 1
        ? this.store.shifts().find((s) => s.active)!.id
        : ''),
  );
  protected readonly times = shiftTimes;
  protected readonly from = signal(
    this.data.assignment?.effectiveFrom ?? formatIsoDate(inject(Clock).now()),
  );
  protected readonly to = signal(this.data.assignment?.effectiveTo ?? '');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const a: ShiftAssignment = {
      id: this.data.assignment?.id ?? crypto.randomUUID(),
      staffId: this.staffId(),
      shiftId: this.shiftId(),
      effectiveFrom: this.from(),
      effectiveTo: this.to().trim() || null,
    };
    const problem = assignmentProblem(a, this.store.assignments());
    if (problem) {
      this.error.set(problem);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.assign(a);
      const name = this.store.staffNames().get(a.staffId) ?? 'Staff member';
      const shift = this.store.shifts().find((s) => s.id === a.shiftId)?.name ?? 'the shift';
      this.ref.close({
        snack: this.editing ? `${name}'s dates saved` : `${name} assigned to ${shift}`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
