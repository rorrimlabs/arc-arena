import { Component, computed, inject, signal } from '@angular/core';
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
import { formatRange } from '../../../shared/staff/staff-format';
import { PeriodKind } from '../data/pay-policy';
import { PayrollStore } from '../data/payroll-store';
import { MAX_RUN_DAYS, Period, SalaryRun, newRunProblem } from '../data/payroll.models';

export interface NewRunDialogData {
  readonly suggested: Period;
  readonly kind: PeriodKind;
  readonly runs: readonly SalaryRun[];
}

const KIND_TEXT: Readonly<Record<PeriodKind, string>> = {
  monthly: 'Your pay rules use monthly periods; this is the next one.',
  weekly: 'Your pay rules use weekly periods; this is the next week.',
  custom: `Your pay rules use custom periods: pick the dates (at most ${MAX_RUN_DAYS} days).`,
};

/**
 * Starts a draft pay run (salary_run.create) for the next period, suggested from the pay rules;
 * the dates can be changed. Runs may not overlap (checked here first, then by the server).
 * Closes with the new run's id.
 */
@Component({
  selector: 'app-new-run-dialog',
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
    <h2 mat-dialog-title>Calculate pay</h2>
    <form novalidate (submit)="confirm($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">{{ kindText }}</p>
          <div class="grid grid-cols-2 gap-3">
            <mat-form-field>
              <mat-label>First day</mat-label>
              <input
                matInput
                type="date"
                aria-describedby="new-run-problem"
                [value]="first()"
                (change)="first.set($any($event.target).value)"
              />
            </mat-form-field>
            <mat-form-field>
              <mat-label>Last day</mat-label>
              <input
                matInput
                type="date"
                aria-describedby="new-run-problem"
                [value]="last()"
                (change)="last.set($any($event.target).value)"
              />
            </mat-form-field>
          </div>
          <p
            id="new-run-problem"
            class="text-sm leading-[1.4]"
            [class.text-danger]="!!problem()"
            [class.font-medium]="!!problem()"
            aria-live="polite"
          >
            {{ problem() ?? 'Draft for ' + label() + '. It opens on the month-end timesheet.' }}
          </p>
          <p class="text-[13px] leading-[1.4] text-muted">
            Building it closes forgotten clock-ins and includes everyone with a pay rate who was
            employed during the period. Nothing is final until you finalise it.
          </p>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy() || !!problem()">
          Calculate
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class NewRunDialog {
  protected readonly data = inject<NewRunDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<NewRunDialog, string>>(MatDialogRef);
  private readonly store = inject(PayrollStore);

  protected readonly kindText = KIND_TEXT[this.data.kind];
  protected readonly first = signal(this.data.suggested.first);
  protected readonly last = signal(this.data.suggested.last);
  protected readonly problem = computed(() =>
    newRunProblem({ first: this.first(), last: this.last() }, this.data.runs),
  );
  protected readonly label = computed(() => formatRange(this.first(), this.last()));
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async confirm(event: Event): Promise<void> {
    event.preventDefault();
    if (this.problem()) return;
    this.busy.set(true);
    this.error.set('');
    const id = crypto.randomUUID();
    try {
      await this.store.create(id, { first: this.first(), last: this.last() });
      this.ref.close(id);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
