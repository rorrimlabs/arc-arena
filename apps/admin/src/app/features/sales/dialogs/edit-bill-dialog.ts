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
 * Edit bill: the bill's start, end and price at a glance. The times and the amount are edited
 * separately: changing a time never changes the amount (a corrected time is noted in History). Saving sets the bill to the amount and collected to match it,
 * the difference recorded as paid or given back by the method picked (bill.adjust; Money
 * permission, checked by the server). The priced lines stay as recorded; History keeps the change.
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
          <div class="grid grid-cols-2 gap-x-4">
            <mat-form-field>
              <mat-label>Start</mat-label>
              <input
                matInput
                type="time"
                [readonly]="!single"
                [value]="start()"
                (change)="setStart($any($event.target).value)"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>End</mat-label>
              <input
                matInput
                type="time"
                [readonly]="!single"
                [value]="end()"
                (change)="setEnd($any($event.target).value)"
              />
            </mat-form-field>
          </div>
          <p class="-mt-3 text-sm leading-[1.4]">
            Price: <span class="font-medium tabular-nums">{{ rupees(was) }}</span>
          </p>
          <mat-form-field>
            <mat-label>Bill amount (₹)</mat-label>
            <input
              matInput
              inputmode="decimal"
              autocomplete="off"
              [value]="amount()"
              (input)="amount.set($any($event.target).value)"
            />
            <mat-hint>Collected so far: {{ rupees(data.bill.paidPaise) }}</mat-hint>
          </mat-form-field>
          @if (diff() !== 0) {
            <mat-form-field>
              <mat-label>{{ diff() > 0 ? 'Extra paid by' : 'Given back by' }}</mat-label>
              <mat-select [value]="method()" (selectionChange)="method.set($event.value)">
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
  /** Time can be fixed on a single session (a group's players end separately). */
  protected readonly single = this.data.bill.kind === 'single' && !!this.data.bill.endedAt;

  protected readonly start = signal(formatHm(this.data.bill.startedAt));
  protected readonly end = signal(this.data.bill.endedAt ? formatHm(this.data.bill.endedAt) : '');
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

  protected setStart(hm: string): void {
    this.start.set(hm);
  }

  protected setEnd(hm: string): void {
    this.end.set(hm);
  }

  /** One Save's ids: a resend after a lost answer replays instead of recording twice. */
  private readonly attempt = new Attempt();

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const paise = this.paise();
    if (paise === null) {
      this.error.set('Enter the bill amount in rupees, like 120 or 120.50');
      return;
    }
    // History says why; a changed time is noted with it.
    const b = this.data.bill;
    const timesChanged =
      this.start() !== formatHm(b.startedAt) || (!!b.endedAt && this.end() !== formatHm(b.endedAt));
    const timeNote = timesChanged ? ` (${this.start()}–${this.end()})` : '';
    const reason = (this.reason().trim() || 'Bill edited') + timeNote;
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
