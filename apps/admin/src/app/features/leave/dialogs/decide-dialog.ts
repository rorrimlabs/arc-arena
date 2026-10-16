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
import { formatCount, formatDays } from '../../../shared/staff/staff-format';
import { LeaveStore } from '../data/leave-store';
import {
  LeaveBalance,
  LeaveRequest,
  datesLabel,
  defaultPaidDays,
  paidDaysProblem,
  splitSentence,
} from '../data/leave.models';

/**
 * - approve: a new request, with the paid / LOP split;
 * - reject: a new request;
 * - cancel: approve the staff member's cancellation of approved leave;
 * - keep: refuse that cancellation (the leave stays approved).
 */
export type DecideMode = 'approve' | 'reject' | 'cancel' | 'keep';

export interface DecideDialogData {
  readonly request: LeaveRequest;
  readonly staffName: string;
  readonly balance: LeaveBalance | null;
  readonly mode: DecideMode;
}

const TITLES: Readonly<Record<DecideMode, string>> = {
  approve: 'Approve leave',
  reject: 'Reject leave',
  cancel: 'Approve cancellation',
  keep: 'Keep the leave',
};

const CONFIRM: Readonly<Record<DecideMode, string>> = {
  approve: 'Approve',
  reject: 'Reject',
  cancel: 'Approve cancellation',
  keep: 'Keep the leave',
};

/**
 * Decides a leave request (leave.decide). Approving sets how many days are paid (0…days in
 * half days, pre-filled with min(days, balance)); the rest is loss of pay, deducted from salary
 * on the pay run. The note is optional and shown to the staff member. A refusal stays in the
 * dialog; closes with true once decided.
 */
@Component({
  selector: 'app-leave-decide-dialog',
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
    <h2 mat-dialog-title>{{ title }}</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            {{ data.staffName }} · {{ dates }} · {{ daysText }}
          </p>
          @switch (data.mode) {
            @case ('approve') {
              <p class="text-sm leading-[1.4]">
                @if (data.balance; as b) {
                  Balance: {{ count(b.balance) }} of {{ count(b.allowance + b.adjustments) }}
                  days left this leave year.
                } @else {
                  Their balance couldn't be read.
                }
                Days beyond the balance are usually loss of pay (LOP).
              </p>
              <mat-form-field class="max-w-60">
                <mat-label>Paid days</mat-label>
                <input
                  matInput
                  type="number"
                  inputmode="decimal"
                  min="0"
                  step="0.5"
                  [max]="data.request.days"
                  aria-describedby="decide-split"
                  [attr.aria-invalid]="!!problem()"
                  [value]="paidText()"
                  (input)="paidText.set($any($event.target).value)"
                />
                <span matTextSuffix>of {{ count(data.request.days) }}</span>
                <mat-hint>Whole or half days</mat-hint>
              </mat-form-field>
              <p
                id="decide-split"
                class="text-sm leading-[1.4] font-medium"
                [class.text-danger]="!!problem()"
                aria-live="polite"
              >
                {{ problem() ?? sentence() }}
              </p>
            }
            @case ('cancel') {
              <p class="text-sm leading-[1.4] text-muted">
                The leave is cancelled and its paid days go back to their balance.
                @if (data.request.cancelReason) {
                  Their reason: “{{ data.request.cancelReason }}”.
                }
              </p>
            }
            @case ('keep') {
              <p class="text-sm leading-[1.4] text-muted">
                The leave stays approved as it is ({{ split }}).
              </p>
            }
          }
          <mat-form-field>
            <mat-label>Note for {{ data.staffName }} (optional)</mat-label>
            <textarea
              matInput
              rows="2"
              maxlength="500"
              [value]="note()"
              (input)="note.set($any($event.target).value)"
            ></textarea>
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button
          mat-flat-button
          type="submit"
          [class.danger-fill]="data.mode === 'reject'"
          [disabled]="busy()"
        >
          {{ confirmLabel }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class LeaveDecideDialog {
  protected readonly data = inject<DecideDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<LeaveDecideDialog, boolean>>(MatDialogRef);
  private readonly store = inject(LeaveStore);

  protected readonly title = TITLES[this.data.mode];
  protected readonly confirmLabel = CONFIRM[this.data.mode];
  protected readonly dates = datesLabel(this.data.request);
  protected readonly daysText = formatDays(this.data.request.days);
  protected readonly split = `${formatCount(this.data.request.paidDays ?? 0)} paid · ${formatCount(this.data.request.lopDays ?? 0)} LOP`;
  protected readonly count = formatCount;

  protected readonly paidText = signal(
    String(defaultPaidDays(this.data.request.days, this.data.balance?.balance ?? null)),
  );
  private readonly paid = computed(() =>
    this.paidText().trim() === '' ? Number.NaN : Number(this.paidText()),
  );
  protected readonly problem = computed(() => paidDaysProblem(this.paid(), this.data.request.days));
  protected readonly sentence = computed(() => splitSentence(this.paid(), this.data.request.days));
  protected readonly note = signal('');
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    const mode = this.data.mode;
    if (mode === 'approve' && this.problem()) {
      this.error.set(this.problem() as string);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.decide(
        this.data.request,
        mode === 'approve' || mode === 'cancel',
        mode === 'approve' ? this.paid() : null,
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
