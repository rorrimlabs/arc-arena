import { Component, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatCount } from '../../../shared/staff/staff-format';
import { LeaveStore } from '../data/leave-store';
import { LeaveBalance, parseAdjustDays, yearLabel } from '../data/leave.models';

export interface AdjustDialogData {
  readonly balance: LeaveBalance;
}

/**
 * Adds or takes away paid-leave days in the person's current leave year (leave.adjust): an
 * opening balance, a day given for working a holiday, a correction. Needs a reason; it is kept
 * in the history and can't be edited (another adjustment undoes it).
 */
@Component({
  selector: 'app-leave-adjust-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatSuffix,
    MatInput,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>Adjust {{ data.balance.staffName }}’s balance</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            Counts in the current leave year ({{ year }}). Now {{ count(data.balance.balance) }}
            days left.
          </p>
          <mat-form-field class="max-w-60">
            <mat-label>Days to add or take away</mat-label>
            <input
              matInput
              inputmode="decimal"
              autocomplete="off"
              [attr.aria-invalid]="tried() && days() === null"
              [value]="daysText()"
              (input)="daysText.set($any($event.target).value)"
            />
            <span matTextSuffix>days</span>
            <mat-hint>e.g. 1, -0.5 (half days allowed)</mat-hint>
          </mat-form-field>
          @if (days() !== null) {
            <p class="text-sm leading-[1.4] font-medium" aria-live="polite">
              New balance: {{ count(data.balance.balance + (days() ?? 0)) }} days
            </p>
          }
          <mat-form-field>
            <mat-label>Reason</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="500"
              [attr.aria-invalid]="tried() && !reason().trim()"
              [value]="reason()"
              (input)="reason.set($any($event.target).value)"
            />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">Adjust balance</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class LeaveAdjustDialog {
  protected readonly data = inject<AdjustDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<LeaveAdjustDialog, boolean>>(MatDialogRef);
  private readonly store = inject(LeaveStore);

  protected readonly year = yearLabel(this.data.balance);
  protected readonly count = formatCount;
  protected readonly daysText = signal('');
  protected readonly days = computed(() => parseAdjustDays(this.daysText()));
  protected readonly reason = signal('');
  protected readonly tried = signal(false);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    this.tried.set(true);
    const days = this.days();
    if (days === null) {
      this.error.set('Enter the days to add (e.g. 1) or take away (e.g. -0.5), not 0');
      return;
    }
    if (!this.reason().trim()) {
      this.error.set('Give a reason');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.adjust(this.data.balance.staffId, days, this.reason());
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
