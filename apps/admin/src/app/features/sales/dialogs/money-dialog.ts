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
import { formatTime } from '../../../shared/time/ist';
import { SalesStore } from '../data/sales-store';
import {
  BillDetail,
  BillPayment,
  PAY_METHODS,
  PayMethod,
  duePaise,
  methodName,
  paidMethods,
  parseRupees,
  rupeesText,
} from '../data/sale.models';

export type MoneyMode = 'payment' | 'refund' | 'correct';

export interface MoneyDialogData {
  readonly bill: BillDetail;
  readonly mode: MoneyMode;
}

const REASON_MAX = 500;

/** What is left to move of each payment: its amount minus what corrections already moved. */
export function movable(bill: BillDetail): Map<string, number> {
  const moved = new Map<string, number>();
  for (const h of bill.history) {
    if (h.action !== 'payment_correct') continue;
    const id = String(h.before?.['payment_id'] ?? '');
    moved.set(id, (moved.get(id) ?? 0) + Number(h.after?.['amount_paise'] ?? 0));
  }
  const left = new Map<string, number>();
  for (const p of bill.payments) {
    if (p.refund) continue;
    const rest = p.amountPaise - (moved.get(p.id) ?? 0);
    if (rest > 0) left.set(p.id, rest);
  }
  return left;
}

/**
 * Money on a closed bill, from the owner's dashboard — never an edit of what was recorded:
 *  - payment: money received late (at most what is still due);
 *  - refund: money given back, with a reason (at most what was collected; allowed on a voided
 *    bill, so money taken before a void can be returned and the till reconciles);
 *  - correct: a payment recorded under the wrong method moves, in full or in part, to the right
 *    one (a refund on the old method + a payment on the new one, with a reason).
 * The server checks the same limits and the permission (Bill; Bill + Give discounts for a
 * refund; Money for a correction). A refusal stays in the dialog; closes with true once saved.
 */
@Component({
  selector: 'app-money-dialog',
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
    <h2 mat-dialog-title>{{ title }} · {{ data.bill.ref }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">{{ explanation }}</p>
          @if (data.mode === 'correct') {
            <mat-form-field>
              <mat-label>Payment recorded wrongly</mat-label>
              <mat-select [value]="paymentId()" (selectionChange)="pickPayment($event.value)">
                @for (p of correctable; track p.id) {
                  <mat-option [value]="p.id">{{ paymentLabel(p) }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          }
          <mat-form-field>
            <mat-label>{{ data.mode === 'correct' ? 'Really paid by' : 'Method' }}</mat-label>
            <mat-select [value]="method()" (selectionChange)="method.set($event.value)">
              @for (m of methodChoices(); track m) {
                <mat-option [value]="m">{{ methodName(m) }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Amount (₹)</mat-label>
            <input
              matInput
              inputmode="decimal"
              autocomplete="off"
              [value]="amount()"
              (input)="amount.set($any($event.target).value)"
            />
            <mat-hint>{{ limitHint() }}</mat-hint>
          </mat-form-field>
          @if (data.mode === 'payment') {
            <mat-form-field>
              <mat-label>Note (optional)</mat-label>
              <input
                matInput
                autocomplete="off"
                maxlength="200"
                [value]="note()"
                (input)="note.set($any($event.target).value)"
              />
            </mat-form-field>
          } @else {
            <mat-form-field>
              <mat-label>Reason</mat-label>
              <input
                matInput
                autocomplete="off"
                required
                maxlength="500"
                [placeholder]="
                  data.mode === 'refund' ? 'Why the money was given back' : 'What was keyed wrongly'
                "
                [value]="reason()"
                (input)="reason.set($any($event.target).value)"
              />
            </mat-form-field>
          }
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">{{ action }}</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class MoneyDialog {
  protected readonly data = inject<MoneyDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<MoneyDialog, boolean>>(MatDialogRef);
  private readonly store = inject(SalesStore);

  protected readonly methodName = methodName;
  private readonly left = movable(this.data.bill);
  protected readonly correctable = this.data.bill.payments.filter((p) => this.left.has(p.id));
  private readonly due = duePaise(this.data.bill);

  protected readonly title = {
    payment: 'Record payment',
    refund: 'Record refund',
    correct: 'Correct payment method',
  }[this.data.mode];
  protected readonly action = {
    payment: 'Record payment',
    refund: 'Record refund',
    correct: 'Move payment',
  }[this.data.mode];
  protected readonly explanation = {
    payment: `Money received now for this bill. Still due: ${formatRupees(this.due)}.`,
    refund: this.data.bill.voided
      ? `This bill is void. Record the money given back so the till matches. Collected on it: ${formatRupees(this.data.bill.paidPaise)}.`
      : `Money given back to the customer. It is added to the payments as a refund with your reason; the bill itself does not change. Collected so far: ${formatRupees(this.data.bill.paidPaise)}.`,
    correct:
      'For a payment keyed under the wrong method. The original stays on record; a refund on the old method and a payment on the right one are added, with your reason. What was collected does not change.',
  }[this.data.mode];

  protected readonly paymentId = signal<string>(this.correctable[0]?.id ?? '');
  private readonly payment = computed<BillPayment | undefined>(() =>
    this.correctable.find((p) => p.id === this.paymentId()),
  );
  protected readonly methodChoices = computed<readonly PayMethod[]>(() => {
    const from = this.data.mode === 'correct' ? this.payment()?.method : undefined;
    return PAY_METHODS.filter((m) => m !== from);
  });
  protected readonly method = signal<PayMethod>(this.firstMethod());
  protected readonly amount = signal(rupeesText(this.defaultAmount()));
  protected readonly note = signal('');
  protected readonly reason = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  /** The most this action may move, in paise (the server holds the same limit). */
  protected readonly limit = computed(() => {
    switch (this.data.mode) {
      case 'payment':
        return this.due;
      case 'refund':
        return Math.max(0, this.data.bill.paidPaise);
      case 'correct':
        return this.left.get(this.paymentId()) ?? 0;
    }
  });
  protected readonly limitHint = computed(() => {
    const max = formatRupees(this.limit());
    return {
      payment: `At most ${max} (what is due)`,
      refund: `At most ${max} (what was collected)`,
      correct: `At most ${max} of this payment`,
    }[this.data.mode];
  });

  protected paymentLabel(p: BillPayment): string {
    const left = this.left.get(p.id) ?? 0;
    const part = left < p.amountPaise ? ` (${formatRupees(left)} left)` : '';
    return `${methodName(p.method)} ${formatRupees(p.amountPaise)}${part} · ${formatTime(p.at)}${p.by ? ` · ${p.by}` : ''}`;
  }

  protected pickPayment(id: string): void {
    this.paymentId.set(id);
    if (this.method() === this.payment()?.method) this.method.set(this.methodChoices()[0]);
    this.amount.set(rupeesText(this.left.get(id) ?? 0));
  }

  /** One Save's ids: a resend after a lost answer replays instead of recording twice. */
  private readonly attempt = new Attempt();

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const paise = parseRupees(this.amount());
    if (paise === null) {
      this.error.set('Enter an amount in rupees, like 120 or 120.50');
      return;
    }
    if (paise > this.limit()) {
      this.error.set(`That is more than ${formatRupees(this.limit())}`);
      return;
    }
    const reason = this.reason().trim();
    if (this.data.mode !== 'payment' && !reason) {
      this.error.set('Give a reason');
      return;
    }
    if (reason.length > REASON_MAX) {
      this.error.set('Keep the reason under 500 characters');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    const bill = this.data.bill;
    try {
      switch (this.data.mode) {
        case 'payment':
          await this.store.recordPayment(bill, {
            amountPaise: paise,
            method: this.method(),
            note: this.note().trim() || null,
            attempt: this.attempt,
          });
          break;
        case 'refund':
          await this.store.refund(bill, {
            amountPaise: paise,
            method: this.method(),
            reason,
            attempt: this.attempt,
          });
          break;
        case 'correct':
          await this.store.correct(bill, {
            paymentId: this.paymentId(),
            method: this.method(),
            amountPaise: paise,
            reason,
            attempt: this.attempt,
          });
          break;
      }
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  private firstMethod(): PayMethod {
    const bill = this.data.bill;
    if (this.data.mode === 'refund') return paidMethods(bill)[0] ?? 'cash';
    if (this.data.mode === 'correct') {
      const from = this.correctable[0]?.method;
      return PAY_METHODS.find((m) => m !== from) ?? 'upi';
    }
    return 'cash';
  }

  private defaultAmount(): number {
    switch (this.data.mode) {
      case 'payment':
        return this.due;
      case 'refund':
        return Math.max(0, this.data.bill.paidPaise);
      case 'correct':
        return this.left.get(this.correctable[0]?.id ?? '') ?? 0;
    }
  }
}
