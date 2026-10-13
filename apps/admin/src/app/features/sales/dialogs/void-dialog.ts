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
import { MatOption, MatSelect } from '@angular/material/select';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { SalesStore } from '../data/sales-store';
import { Bill, SalesRange, VOID_REASONS } from '../data/sale.models';

export interface VoidDialogData {
  readonly bill: Bill;
  /** The list's range, reloaded after the void. */
  readonly range: SalesRange;
}

/**
 * Design dialog `d.k === 'void'`: pick a reason, void the bill. It stays in the records, marked
 * void, and drops out of takings. A refusal stays in the dialog. Closes with true once voided.
 */
@Component({
  selector: 'app-void-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatSelect,
    MatOption,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>Void {{ data.bill.ref }}?</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            The bill stays in the records, marked void, and drops out of takings.
            @if (data.bill.paidPaise > 0) {
              {{ collected }} was collected on it; voiding does not refund it.
            }
          </p>
          <mat-form-field>
            <mat-label>Reason</mat-label>
            <mat-select [value]="reason()" (selectionChange)="reason.set($event.value)">
              @for (r of reasons; track r) {
                <mat-option [value]="r">{{ r }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" class="danger-fill" [disabled]="busy()">
          Void bill
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class VoidDialog {
  protected readonly data = inject<VoidDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<VoidDialog, boolean>>(MatDialogRef);
  private readonly store = inject(SalesStore);

  protected readonly reasons = VOID_REASONS;
  protected readonly collected = formatRupees(this.data.bill.paidPaise);
  protected readonly reason = signal<string>(VOID_REASONS[0]);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.void(this.data.bill, this.reason(), this.data.range);
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
