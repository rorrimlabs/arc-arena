import { Component, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatCheckbox } from '@angular/material/checkbox';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatRadioButton, MatRadioGroup } from '@angular/material/radio';
import { toAppError } from '../../../core/auth/auth-api';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import {
  DAY_DIVISORS,
  PAY_TYPES,
  PERIOD_KINDS,
  PayPolicy,
  PayType,
  PolicyDraft,
  PolicyField,
  fromPolicyDraft,
  payTypeLabel,
  policyProblems,
  toPolicyDraft,
} from '../../payroll/data/pay-policy';
import { PaySetupStore } from '../data/pay-setup-store';
import { finalisedLimitText, minEffectiveFrom } from '../data/pay-setup.models';

export interface PayPolicyDialogData {
  /** The rules in force now, to start from. */
  readonly current: PayPolicy;
  readonly finalisedEnd: string | null;
  readonly suggestedFrom: string;
  /** Days that already have a rules row (duplicate). */
  readonly taken: readonly string[];
}

interface NumberField {
  readonly key: PolicyField;
  readonly label: string;
  readonly suffix: string;
  readonly hint: string;
  readonly step: string;
}

const DEDUCTIONS: readonly NumberField[] = [
  {
    key: 'absentFactor',
    label: 'Absent day costs',
    suffix: 'days of pay',
    hint: 'A scheduled day not worked and not on leave. 0–3',
    step: '0.5',
  },
  {
    key: 'lopFactor',
    label: 'LOP day costs',
    suffix: 'days of pay',
    hint: 'A leave day the approver marked as loss of pay. 0–3',
    step: '0.5',
  },
  {
    key: 'halfDayFactor',
    label: 'Half-day costs',
    suffix: 'day of pay',
    hint: 'Worked enough for half a day only. 0–1',
    step: '0.1',
  },
];

/**
 * New pay rules from a date (pay_policy.add): rules are never edited; the new ones apply to pay
 * runs whose first day is on or after it. They may not start inside a finalised run. Every field
 * is sent (the server requires the whole object).
 */
@Component({
  selector: 'app-pay-policy-dialog',
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
    MatRadioGroup,
    MatRadioButton,
    MatCheckbox,
    MatButton,
    ToggleRow,
  ],
  template: `
    <h2 mat-dialog-title>Change pay rules</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        @let d = draft();
        @let p = shown();
        <div class="flex flex-col gap-5 pt-1">
          <mat-form-field class="max-w-60">
            <mat-label>Effective from</mat-label>
            <input
              matInput
              type="date"
              aria-describedby="policy-from-help"
              [min]="minDay ?? ''"
              [value]="from()"
              (change)="from.set($any($event.target).value)"
            />
          </mat-form-field>
          <p id="policy-from-help" class="-mt-3 text-[13px] leading-[1.4] text-muted">
            A pay run uses the rules in force on its first day.
            {{ limitText }}
          </p>
          @if (tried() && fromProblem(); as fp) {
            <p role="alert" class="text-[13px] leading-[1.4] text-danger">{{ fp }}</p>
          }

          <h3 class="text-base font-semibold">Pay period</h3>
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-label="Pay period"
            [value]="d.periodKind"
            (change)="set({ periodKind: $event.value })"
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
          @if (d.periodKind === 'monthly') {
            <mat-form-field class="max-w-60">
              <mat-label>Cycle starts on day</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                min="1"
                max="28"
                [attr.aria-invalid]="!!p.cycleStartDay"
                [value]="d.cycleStartDay"
                (input)="set({ cycleStartDay: $any($event.target).value })"
              />
              <mat-hint>1–28. Day 1 = calendar months; 26 = 26th to 25th</mat-hint>
            </mat-form-field>
          }

          <h3 class="text-base font-semibold">Day rate of a monthly salary</h3>
          <mat-radio-group
            class="flex flex-col gap-3"
            aria-label="Day rate of a monthly salary"
            [value]="d.dayDivisor"
            (change)="set({ dayDivisor: $event.value })"
          >
            @for (v of divisors; track v.value) {
              <mat-radio-button [value]="v.value">
                <span class="flex flex-col gap-0.5">
                  <span class="text-[15px] leading-[1.3]">{{ v.label }}</span>
                  <span class="text-[13px] leading-[1.3] text-muted">{{ v.sub }}</span>
                </span>
              </mat-radio-button>
            }
          </mat-radio-group>

          <h3 class="text-base font-semibold">Suggested deductions</h3>
          <p class="-mt-3 text-[13px] leading-[1.4] text-muted">
            Only suggestions: on every pay run you keep or waive each one per person.
          </p>
          @for (f of deductionFields; track f.key) {
            <mat-form-field class="max-w-72">
              <mat-label>{{ f.label }}</mat-label>
              <input
                matInput
                type="number"
                inputmode="decimal"
                [step]="f.step"
                [attr.aria-invalid]="!!p[f.key]"
                [value]="d[f.key]"
                (input)="setField(f.key, $any($event.target).value)"
              />
              <span matTextSuffix>{{ f.suffix }}</span>
              <mat-hint>{{ f.hint }}</mat-hint>
            </mat-form-field>
          }

          <h3 class="text-base font-semibold">Late rule</h3>
          <div class="flex flex-wrap items-start gap-3">
            <mat-form-field class="w-40">
              <mat-label>Every</mat-label>
              <input
                matInput
                type="number"
                inputmode="numeric"
                min="0"
                max="31"
                [attr.aria-invalid]="!!p.lateEvery"
                [value]="d.lateEvery"
                (input)="set({ lateEvery: $any($event.target).value })"
              />
              <span matTextSuffix>lates</span>
              <mat-hint>0 = no late rule</mat-hint>
            </mat-form-field>
            <mat-form-field class="w-48">
              <mat-label>Cost</mat-label>
              <input
                matInput
                type="number"
                inputmode="decimal"
                step="0.5"
                min="0"
                max="1"
                [attr.aria-invalid]="!!p.latePenaltyDays"
                [value]="d.latePenaltyDays"
                (input)="set({ latePenaltyDays: $any($event.target).value })"
              />
              <span matTextSuffix>day of pay</span>
              <mat-hint>0–1</mat-hint>
            </mat-form-field>
          </div>
          <div class="flex flex-col gap-1" role="group" aria-labelledby="policy-late-applies">
            <span id="policy-late-applies" class="text-[15px] leading-[1.3]">Applies to</span>
            @for (t of payTypes; track t) {
              <mat-checkbox
                [checked]="d.lateAppliesTo.includes(t)"
                (change)="toggleType(t, $event.checked)"
              >
                {{ typeLabel(t) }}
              </mat-checkbox>
            }
            <span class="text-[13px] leading-[1.3] text-muted">
              Hourly staff already lose the late minutes, so they are usually left out.
            </span>
          </div>
          <app-toggle-row
            label="Early leave counts as late"
            sub="Leaving before the shift end (past the early-leave margin in Working hours) adds a late mark"
            [checked]="d.earlyLeaveCountsAsLate"
            (changed)="set({ earlyLeaveCountsAsLate: $event.checked })"
          />

          <h3 class="text-base font-semibold">Extra hours and holidays</h3>
          <mat-form-field class="max-w-60">
            <mat-label>Extra-hours multiplier</mat-label>
            <input
              matInput
              type="number"
              inputmode="decimal"
              step="0.25"
              min="1"
              max="5"
              [attr.aria-invalid]="!!p.extraMultiplier"
              [value]="d.extraMultiplier"
              (input)="set({ extraMultiplier: $any($event.target).value })"
            />
            <span matTextSuffix>×</span>
            <mat-hint>1–5. Extra hours pay = hours × hourly rate × this</mat-hint>
          </mat-form-field>
          <app-toggle-row
            label="Pay daily staff on holidays"
            sub="Daily-paid staff get a day's pay on a paid staff holiday"
            [checked]="d.dailyPaidHolidays"
            (changed)="set({ dailyPaidHolidays: $event.checked })"
          />

          @if (problemList().length) {
            <ul
              role="alert"
              class="flex list-disc flex-col gap-1 pl-5 text-[13px] leading-[1.4] text-danger"
            >
              @for (m of problemList(); track m) {
                <li>{{ m }}</li>
              }
            </ul>
          }
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">Save new rules</button>
      </mat-dialog-actions>
    </form>
  `,
})
export class PayPolicyDialog {
  protected readonly data = inject<PayPolicyDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<PayPolicyDialog, boolean>>(MatDialogRef);
  private readonly store = inject(PaySetupStore);

  protected readonly kinds = PERIOD_KINDS;
  protected readonly divisors = DAY_DIVISORS;
  protected readonly payTypes = PAY_TYPES;
  protected readonly typeLabel = payTypeLabel;
  protected readonly deductionFields = DEDUCTIONS;
  protected readonly minDay = minEffectiveFrom(this.data.finalisedEnd);
  protected readonly limitText = finalisedLimitText(this.data.finalisedEnd);

  protected readonly from = signal(this.data.suggestedFrom);
  protected readonly draft = signal<PolicyDraft>(toPolicyDraft(this.data.current));
  private readonly problems = computed(() => policyProblems(this.draft()));
  protected readonly tried = signal(false);
  /** Problems show once typed wrong (aria-invalid) and are listed after a save attempt. */
  protected readonly shown = computed(() => this.problems());
  protected readonly problemList = computed(() =>
    this.tried() ? Object.values(this.problems()).filter((m): m is string => !!m) : [],
  );
  protected readonly fromProblem = computed(() => {
    const f = this.from();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(f)) return 'Pick the first day the new rules apply';
    if (this.minDay && f < this.minDay) return this.limitText;
    if (this.data.taken.includes(f)) return 'Rules already start on that day: pick another day';
    return null;
  });
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected set(change: Partial<PolicyDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  protected setField(key: PolicyField, value: string): void {
    this.set({ [key]: value } as Partial<PolicyDraft>);
  }

  protected toggleType(t: PayType, on: boolean): void {
    const now = this.draft().lateAppliesTo;
    this.set({ lateAppliesTo: on ? [...now, t] : now.filter((x) => x !== t) });
  }

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    this.tried.set(true);
    const policy = fromPolicyDraft(this.draft());
    if (this.fromProblem() || !policy) {
      this.error.set('Fix the values marked above');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.addPolicy(this.from(), policy);
      this.ref.close(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
