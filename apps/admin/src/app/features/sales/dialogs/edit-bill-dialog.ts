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
import { Attempt } from '../../../core/sync/push-ops';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { formatHm } from '../../../shared/time/ist';
import { SalesStore } from '../data/sales-store';
import {
  BillDetail,
  PAY_METHODS,
  PayMethod,
  methodName,
  paidMethods,
  parseRupees,
  rupeesText,
} from '../data/sale.models';

export interface EditBillDialogData {
  readonly bill: BillDetail;
}

/**
 * Edit bill: the bill's times and price at a glance (times are not edited here). Saving sets the
 * bill to the amount and collected to match it, the difference recorded as paid or given back by
 * the method picked (bill.adjust; Money permission, checked by the server, which refuses it as
 * stale if the bill changed since it was loaded). The priced lines stay as recorded; History
 * keeps the change.
 */
@Component({
  selector: 'app-edit-bill-dialog',
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
    <h2 mat-dialog-title>Edit bill · {{ data.bill.ref }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4]">
            Played <span class="font-medium tabular-nums">{{ start }}–{{ end || '…' }}</span> ·
            Price: <span class="font-medium tabular-nums">{{ rupees(was) }}</span>
          </p>
          <mat-form-field>
            <mat-label>Bill amount (₹)</mat-label>
            <input
              matInput
              inputmode="decimal"
              autocomplete="off"
              [value]="amount()"
              (input)="amount.set($any($event.target).value); changed()"
            />
            <mat-hint>Collected so far: {{ rupees(data.bill.paidPaise) }}</mat-hint>
          </mat-form-field>
          @if (diff() !== 0) {
            <mat-form-field>
              <mat-label>{{ diff() > 0 ? 'Extra paid by' : 'Given back by' }}</mat-label>
              <mat-select [value]="method()" (selectionChange)="method.set($event.value); changed()">
                @for (m of methods; track m) {
                  <mat-option [value]="m">{{ methodName(m) }}</mat-option>
                }
              </mat-select>
              <mat-hint>{{ rupees(diff() > 0 ? diff() : -diff()) }} recorded so collected matches the bill</mat-hint>
            </mat-form-field>
          }
          <mat-form-field>
            <mat-label>Reason (optional)</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="200"
              [value]="reason()"
              (input)="reason.set($any($event.target).value); changed()"
            />
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
export class EditBillDialog {
  protected readonly data = inject<EditBillDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<EditBillDialog, boolean>>(MatDialogRef);
  private readonly store = inject(SalesStore);

  protected readonly rupees = formatRupees;
  protected readonly methodName = methodName;
  protected readonly methods = PAY_METHODS;
  protected readonly start = formatHm(this.data.bill.startedAt);
  protected readonly end = this.data.bill.endedAt ? formatHm(this.data.bill.endedAt) : '';
  protected readonly was = this.data.bill.billedPaise ?? 0;
  protected readonly amount = signal(rupeesText(this.data.bill.billedPaise ?? 0));
  protected readonly method = signal<PayMethod>(paidMethods(this.data.bill)[0] ?? 'cash');
  protected readonly reason = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);
  /** Typed amount (0 allowed), or null while it is not an amount. */
  private readonly paise = computed(() => {
    const t = this.amount().trim();
    return /^0+(\.0{1,2})?$/.test(t) ? 0 : parseRupees(t);
  });
  /** New amount minus what was collected: recorded as paid (+) or given back (−). */
  protected readonly diff = computed(() => {
    const p = this.paise();
    return p == null ? 0 : p - this.data.bill.paidPaise;
  });

  /**
   * One Save's ids: a resend after a lost answer replays instead of recording twice. Changing
   * the amount, method or reason makes the next Save a new edit, never a replay of the old one.
   */
  private attempt = new Attempt();

  protected changed(): void {
    this.attempt = new Attempt();
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const paise = this.paise();
    if (paise === null) {
      this.error.set('Enter the bill amount in rupees, like 120 or 120.50');
      return;
    }
    const reason = this.reason().trim() || 'Bill edited';
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.edit(this.data.bill, {
        billedPaise: paise,
        method: this.method(),
        reason,
        attempt: this.attempt,
      });
      this.ref.close(true);
    } catch (e) {
      this.attempt.settle(e);
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
