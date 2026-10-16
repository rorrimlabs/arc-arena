import { Component, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel, MatPrefix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatRadioButton, MatRadioGroup } from '@angular/material/radio';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { parseRupees } from '../../sales/data/sale.models';
import { PayrollStore } from '../data/payroll-store';
import { NEW_ADJUSTMENT_KINDS, NewAdjustmentKind } from '../data/payroll.models';

export interface AdjustmentDialogData {
  readonly runId: string;
  readonly staffId: string;
  readonly staffName: string;
}

/**
 * Adds a bonus, an advance or a deduction to a person's pay in a draft run
 * (salary_adjustment.add). The amount is typed in rupees and sent as positive paise; the server
 * signs it by kind. A note is required. Adjustments can't be edited: Reverse undoes one.
 */
@Component({
  selector: 'app-adjustment-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatPrefix,
    MatInput,
    MatRadioGroup,
    MatRadioButton,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>Add adjustment · {{ data.staffName }}</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-label="Kind"
            [value]="kind()"
            (change)="kind.set($event.value)"
          >
            @for (k of kinds; track k.value) {
              <mat-radio-button [value]="k.value">
                <span class="flex flex-col gap-0.5">
                  <span class="text-[15px] leading-[1.3]">{{ k.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ k.sub }}</span>
                </span>
              </mat-radio-button>
            }
          </mat-radio-group>
          <mat-form-field class="max-w-60">
            <mat-label>Amount</mat-label>
            <span matTextPrefix>₹&nbsp;</span>
            <input
              matInput
              inputmode="decimal"
              autocomplete="off"
              [attr.aria-invalid]="tried() && paise() === null"
              [value]="amount()"
              (input)="amount.set($any($event.target).value)"
            />
            <mat-hint>{{ effect() }}</mat-hint>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Note</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="500"
              [attr.aria-invalid]="tried() && !note().trim()"
              [value]="note()"
              (input)="note.set($any($event.target).value)"
            />
            <mat-hint>What it is for, e.g. “Diwali” or “Oct 10 advance”</mat-hint>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">Add</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class AdjustmentDialog {
  protected readonly data = inject<AdjustmentDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<AdjustmentDialog, boolean>>(MatDialogRef);
  private readonly store = inject(PayrollStore);

  protected readonly kinds = NEW_ADJUSTMENT_KINDS;
  protected readonly kind = signal<NewAdjustmentKind>('bonus');
  protected readonly amount = signal('');
  protected readonly paise = computed(() => parseRupees(this.amount()));
  protected readonly effect = computed(() => {
    const p = this.paise();
    if (p === null) return 'Rupees, up to two decimals';
    return this.kind() === 'bonus'
      ? `Adds ${formatPaise(p)} to pay`
      : `Takes ${formatPaise(p)} off pay`;
  });
  protected readonly note = signal('');
  protected readonly tried = signal(false);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    this.tried.set(true);
    const paise = this.paise();
    if (paise === null) {
      this.error.set('Enter an amount in rupees, more than zero');
      return;
    }
    if (!this.note().trim()) {
      this.error.set('Write a note saying what this is for');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.addAdjustment(
        this.data.runId,
        this.data.staffId,
        this.kind(),
        paise,
        this.note(),
      );
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
