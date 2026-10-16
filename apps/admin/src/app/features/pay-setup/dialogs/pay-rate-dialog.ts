import { Component, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import {
  MatFormField,
  MatHint,
  MatLabel,
  MatPrefix,
  MatSuffix,
} from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatRadioButton, MatRadioGroup } from '@angular/material/radio';
import { toAppError } from '../../../core/auth/auth-api';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { parseRupees } from '../../sales/data/sale.models';
import { PAY_TYPES, PayType, payTypeLabel, perLabel } from '../../payroll/data/pay-policy';
import { PaySetupStore } from '../data/pay-setup-store';
import {
  PayRate,
  RateDraft,
  derivedHourlyPaise,
  finalisedLimitText,
  minEffectiveFrom,
  rateProblems,
} from '../data/pay-setup.models';

export interface PayRateDialogData {
  readonly staffId: string;
  readonly staffName: string;
  readonly existing: readonly PayRate[];
  readonly finalisedEnd: string | null;
  /** The person's standard day (for the derived extra-hours estimate). */
  readonly standardDayMin: number;
  readonly multiplier: number;
  /** The suggested first day (today, or the first day allowed). */
  readonly suggestedFrom: string;
  /** The current rate, to start from. */
  readonly current: PayRate | null;
}

const UNIT: Readonly<Record<PayType, string>> = {
  monthly: 'per month',
  daily: 'per day',
  hourly: 'per hour',
};

/**
 * A new pay rate from a date (pay_rate.add): rates are never edited, a new one takes over from
 * its effective date. It may not start inside a finalised pay run. The amount is typed in
 * rupees and sent as integer paise.
 */
@Component({
  selector: 'app-pay-rate-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatPrefix,
    MatSuffix,
    MatInput,
    MatRadioGroup,
    MatRadioButton,
    MatButton,
    ToggleRow,
  ],
  template: `
    <h2 mat-dialog-title>New rate for {{ data.staffName }}</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <mat-form-field class="max-w-60">
            <mat-label>Effective from</mat-label>
            <input
              matInput
              type="date"
              aria-describedby="rate-from-help"
              [min]="minDay ?? ''"
              [attr.aria-invalid]="tried() && !!problems().effectiveFrom"
              [value]="draft().effectiveFrom"
              (change)="set({ effectiveFrom: $any($event.target).value })"
            />
          </mat-form-field>
          <p id="rate-from-help" class="-mt-3 text-[13px] leading-[1.4] text-muted">
            {{
              limitText || 'The new rate applies from this day on; earlier days keep the old rate.'
            }}
          </p>
          @if (tried() && problems().effectiveFrom; as p) {
            <p role="alert" class="text-[13px] leading-[1.4] text-danger">{{ p }}</p>
          }
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-label="Pay type"
            [value]="draft().payType"
            (change)="set({ payType: $event.value })"
          >
            @for (t of payTypes; track t) {
              <mat-radio-button [value]="t">{{ typeLabel(t) }}</mat-radio-button>
            }
          </mat-radio-group>
          <mat-form-field class="max-w-60">
            <mat-label>Amount</mat-label>
            <span matTextPrefix>₹&nbsp;</span>
            <input
              matInput
              inputmode="decimal"
              autocomplete="off"
              [attr.aria-invalid]="tried() && !!problems().amount"
              [value]="draft().amount"
              (input)="set({ amount: $any($event.target).value })"
            />
            <span matTextSuffix>{{ unit() }}</span>
          </mat-form-field>
          @if (tried() && problems().amount; as p) {
            <p role="alert" class="text-[13px] leading-[1.4] text-danger">{{ p }}</p>
          }
          <app-toggle-row
            label="Pay for extra hours"
            [sub]="extraSub()"
            [checked]="draft().extraHoursPaid"
            (changed)="set({ extraHoursPaid: $event.checked })"
          />
          @if (draft().extraHoursPaid) {
            <mat-form-field class="max-w-60">
              <mat-label>Own extra-hours rate (optional)</mat-label>
              <span matTextPrefix>₹&nbsp;</span>
              <input
                matInput
                inputmode="decimal"
                autocomplete="off"
                [attr.aria-invalid]="tried() && !!problems().extraRate"
                [value]="draft().extraRate"
                (input)="set({ extraRate: $any($event.target).value })"
              />
              <span matTextSuffix>/ h</span>
              <mat-hint>Empty: derived from the pay</mat-hint>
            </mat-form-field>
            @if (tried() && problems().extraRate; as p) {
              <p role="alert" class="text-[13px] leading-[1.4] text-danger">{{ p }}</p>
            }
          }
          <mat-form-field>
            <mat-label>Note (optional)</mat-label>
            <input
              matInput
              autocomplete="off"
              maxlength="500"
              [value]="draft().note"
              (input)="set({ note: $any($event.target).value })"
            />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">Add rate</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class PayRateDialog {
  protected readonly data = inject<PayRateDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<PayRateDialog, boolean>>(MatDialogRef);
  private readonly store = inject(PaySetupStore);

  protected readonly payTypes = PAY_TYPES;
  protected readonly typeLabel = payTypeLabel;
  protected readonly minDay = minEffectiveFrom(this.data.finalisedEnd);
  protected readonly limitText = finalisedLimitText(this.data.finalisedEnd);
  protected readonly draft = signal<RateDraft>({
    effectiveFrom: this.data.suggestedFrom,
    payType: this.data.current?.payType ?? 'monthly',
    amount: '',
    extraHoursPaid: this.data.current?.extraHoursPaid ?? false,
    extraRate: '',
    note: '',
  });
  protected readonly problems = computed(() =>
    rateProblems(this.draft(), this.data.existing, this.data.finalisedEnd),
  );
  protected readonly unit = computed(() => UNIT[this.draft().payType]);
  /** docs/STAFF.md S3, in words, with an estimate for the amount typed. */
  protected readonly extraSub = computed(() => {
    const d = this.draft();
    const h = this.data.standardDayMin / 60;
    const how =
      d.payType === 'monthly'
        ? `salary ÷ days in the pay period ÷ ${h} h`
        : d.payType === 'daily'
          ? `day rate ÷ ${h} h`
          : 'the hourly rate';
    const paise = parseRupees(d.amount);
    const estimate =
      paise === null
        ? ''
        : ` (${d.payType === 'monthly' ? '≈ ' : ''}${formatPaise(derivedHourlyPaise({ payType: d.payType, basePaise: paise }, this.data.standardDayMin))}/h${d.payType === 'monthly' ? ' in a 30-day month' : ''})`;
    return `Minutes beyond the standard day (${h} h), and all work on holidays and week offs. Without an own rate it is ${how}${estimate}, × ${this.data.multiplier} (Pay rules).`;
  });
  protected readonly tried = signal(false);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected set(change: Partial<RateDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    this.tried.set(true);
    if (Object.keys(this.problems()).length) {
      this.error.set('Fix the values marked above');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.addRate(this.data.staffId, this.draft());
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}

/** "₹18,000.00 / month" */
export function rateShort(r: PayRate): string {
  return `${formatPaise(r.basePaise)} ${perLabel(r.payType)}`;
}
