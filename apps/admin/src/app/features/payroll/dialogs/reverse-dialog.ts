import { Component, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { PayrollStore } from '../data/payroll-store';
import { SalaryAdjustment, adjustmentLabel } from '../data/payroll.models';
import { Attempt } from '../../../core/sync/push-ops';

export interface ReverseDialogData {
  readonly runId: string;
  readonly adjustment: SalaryAdjustment;
}

/**
 * Undoes an adjustment with a reversal row (salary_adjustment.reverse): nothing is deleted.
 * Needs a note. Closes with true once reversed.
 */
@Component({
  selector: 'app-reverse-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatInput,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>Reverse {{ label.toLowerCase() }}?</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            {{ label }} of {{ amount }} (“{{ data.adjustment.note }}”) stays in the records and a
            reversal of the same amount is added, so it no longer counts.
          </p>
          <mat-form-field>
            <mat-label>Why</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="500"
              [value]="note()"
              (input)="note.set($any($event.target).value)"
            />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" class="danger-fill" [disabled]="busy()">
          Reverse
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class ReverseDialog {
  protected readonly data = inject<ReverseDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<ReverseDialog, boolean>>(MatDialogRef);
  private readonly store = inject(PayrollStore);

  protected readonly label = adjustmentLabel(this.data.adjustment.kind);
  protected readonly amount = formatPaise(Math.abs(this.data.adjustment.amountPaise));
  protected readonly note = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  /** One Save's ids: a resend after a lost answer replays instead of recording twice. */
  private readonly attempt = new Attempt();

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.note().trim()) {
      this.error.set('Write a note saying why');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.reverse(this.data.runId, this.data.adjustment.id, this.note(), this.attempt);
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
