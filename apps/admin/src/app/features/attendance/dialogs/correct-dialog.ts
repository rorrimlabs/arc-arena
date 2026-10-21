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
import { AttendanceStore } from '../data/attendance-store';
import {
  AttendanceEntry,
  CorrectionPayload,
  StaffMember,
  correctionProblem,
  istInstant,
  istParts,
} from '../data/attendance.models';
import { Attempt } from '../../../core/sync/push-ops';

export interface CorrectDialogData {
  /** Present: correct this entry's times. Absent: add a missing entry for someone. */
  readonly entry?: AttendanceEntry;
  /** Edit: the person's name. */
  readonly staffName?: string;
  /** Add: who may be picked (the reviewer's own profile left out unless they are the owner). */
  readonly staff?: readonly StaffMember[];
  /** Add: the person picked to start with (the list's staff filter). */
  readonly staffId?: string | null;
}

/** Closes with the resulting entry's id and the snackbar text; undefined when cancelled. */
export interface CorrectDialogResult {
  readonly id: string;
  readonly snack: string;
}

/**
 * Correct an entry's times, or add a missing entry (attendance.correct `edit` / `add`): clock-in
 * and clock-out as IST date + time (clock-out may stay empty for an entry still open; adding
 * needs both) and a required reason. The original row is kept as superseded; nothing is deleted.
 */
@Component({
  selector: 'app-correct-dialog',
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
    <h2 mat-dialog-title>{{ editing ? 'Correct times · ' + data.staffName : 'Add missing entry' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            {{
              editing
                ? 'The current entry is kept as superseded and this one replaces it. Times are the arena’s (IST).'
                : 'For a shift someone worked without clocking in. Times are the arena’s (IST).'
            }}
          </p>
          @if (!editing) {
            <mat-form-field>
              <mat-label>Staff member</mat-label>
              <mat-select
                [value]="staffId()"
                (selectionChange)="staffId.set($event.value); error.set('')"
              >
                @for (s of data.staff ?? []; track s.id) {
                  <mat-option [value]="s.id">{{ s.name }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          }
          <fieldset>
            <legend class="pb-2 text-[15px] leading-[1.3]">Clock-in</legend>
            <div class="grid grid-cols-2 gap-3">
            <mat-form-field>
              <mat-label>Date</mat-label>
              <input
                matInput
                type="date"
                aria-label="Clock-in date"
                [max]="today"
                [value]="inDate()"
                (input)="inDate.set($any($event.target).value); error.set('')"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>Time</mat-label>
              <input
                matInput
                type="time"
                aria-label="Clock-in time"
                [value]="inTime()"
                (input)="inTime.set($any($event.target).value); error.set('')"
              />
            </mat-form-field>
            </div>
          </fieldset>
          <fieldset>
            <legend class="pb-2 text-[15px] leading-[1.3]">
              Clock-out{{ outOptional ? ' (optional)' : '' }}
            </legend>
            <div class="grid grid-cols-2 gap-3">
            <mat-form-field>
              <mat-label>Date</mat-label>
              <input
                matInput
                type="date"
                aria-label="Clock-out date"
                [max]="today"
                [value]="outDate()"
                (input)="outDate.set($any($event.target).value); error.set('')"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>Time</mat-label>
              <input
                matInput
                type="time"
                aria-label="Clock-out time"
                [value]="outTime()"
                (input)="outTime.set($any($event.target).value); error.set('')"
              />
              @if (outOptional) {
                <mat-hint>Empty: still on the clock</mat-hint>
              }
            </mat-form-field>
            </div>
          </fieldset>
          <mat-form-field>
            <mat-label>Reason</mat-label>
            <textarea
              matInput
              rows="2"
              maxlength="500"
              [value]="reason()"
              (input)="reason.set($any($event.target).value); error.set('')"
            ></textarea>
            <mat-hint>Required · kept with the entry's history</mat-hint>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save correction' : 'Add entry' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class CorrectDialog {
  protected readonly data = inject<CorrectDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<CorrectDialog, CorrectDialogResult>>(MatDialogRef);
  private readonly store = inject(AttendanceStore);
  private readonly clock = inject(Clock);

  protected readonly editing = !!this.data.entry;
  /** Only an entry that is still open may stay without a clock-out. */
  protected readonly outOptional = this.editing && !this.data.entry?.outAt;
  protected readonly today = formatIsoDate(this.clock.now());

  private readonly inStart = this.data.entry ? istParts(this.data.entry.inAt) : null;
  private readonly outStart = this.data.entry?.outAt ? istParts(this.data.entry.outAt) : null;
  protected readonly staffId = signal(this.data.staffId ?? '');
  protected readonly inDate = signal(this.inStart?.date ?? this.today);
  protected readonly inTime = signal(this.inStart?.time ?? '');
  protected readonly outDate = signal(this.outStart?.date ?? this.inStart?.date ?? this.today);
  protected readonly outTime = signal(this.outStart?.time ?? '');
  protected readonly reason = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  private readonly outAt = computed(() =>
    this.outTime().trim() ? istInstant(this.outDate(), this.outTime()) : null,
  );

  /** One Save's ids: a resend after a lost answer replays instead of recording twice. */
  private readonly attempt = new Attempt();

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.editing && !this.staffId()) {
      this.error.set('Pick who the entry is for');
      return;
    }
    const inAt = istInstant(this.inDate(), this.inTime());
    if (this.outTime().trim() && !this.outAt()) {
      this.error.set('Pick a valid clock-out date and time, or clear the time');
      return;
    }
    const problem = correctionProblem(
      { inAt, outAt: this.outAt(), reason: this.reason(), outRequired: !this.outOptional },
      this.clock.now(),
    );
    if (problem || !inAt) {
      this.error.set(problem ?? 'Pick the clock-in date and time');
      return;
    }
    const reason = this.reason().trim();
    const entry = this.data.entry;
    const payload: CorrectionPayload = entry
      ? { action: 'edit', entry_id: entry.id, in_at: inAt, out_at: this.outAt(), reason }
      : {
          action: 'add',
          staff_id: this.staffId(),
          in_at: inAt,
          out_at: this.outAt() as string,
          reason,
        };
    this.busy.set(true);
    this.error.set('');
    try {
      const id = await this.store.correct(payload, this.attempt);
      const name = entry
        ? this.data.staffName
        : this.data.staff?.find((s) => s.id === this.staffId())?.name;
      this.ref.close({
        id,
        snack: entry ? `${name}'s entry corrected` : `Entry added for ${name ?? 'them'}`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
