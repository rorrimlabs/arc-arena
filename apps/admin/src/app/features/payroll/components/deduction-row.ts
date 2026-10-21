import { Component, computed, input, linkedSignal, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { formatPaise } from '../../../shared/money/rupees.pipe';
import { formatDays } from '../../../shared/staff/staff-format';
import { Deduction } from '../data/payroll.models';

export interface DeductionDecision {
  readonly applied: boolean;
  readonly note: string;
}

/** "1 day × ₹580.65 = ₹580.65" (the server's units, day rate and rounded suggestion). */
export function deductionFormula(d: Deduction): string {
  return `${formatDays(d.units)} × ${formatPaise(Math.round(d.ratePaise))} = ${formatPaise(d.amountPaise)}`;
}

/**
 * One suggested deduction on a person's breakdown: what it is, its formula, Keep or Waive and an
 * optional note. Read-only unless `editable` (a draft run and the Payroll permission).
 */
@Component({
  selector: 'app-deduction-row',
  imports: [MatButtonToggleGroup, MatButtonToggle, MatFormField, MatLabel, MatInput, MatButton],
  host: { class: 'flex flex-col gap-2 border-b border-border pb-4 last:border-b-0 last:pb-0' },
  template: `
    @let d = deduction();
    <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
      <span class="flex min-w-0 flex-col gap-0.5">
        <span class="text-sm leading-[1.3] font-medium">{{ d.label }}</span>
        <span class="text-xs leading-[1.3] text-muted tabular-nums">{{ formula() }}</span>
      </span>
      <span
        class="text-sm font-semibold tabular-nums"
        [class.line-through]="!d.applied"
        [class.text-muted]="!d.applied"
        >−{{ amount() }}</span
      >
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <mat-button-toggle-group
        hideSingleSelectionIndicator
        [attr.aria-label]="d.label + ' deduction'"
        [value]="d.applied ? 'keep' : 'waive'"
        [disabled]="!editable() || busy()"
        (change)="decided.emit({ applied: $event.value === 'keep', note: note() })"
      >
        <mat-button-toggle value="keep">Keep</mat-button-toggle>
        <mat-button-toggle value="waive">Waive</mat-button-toggle>
      </mat-button-toggle-group>
      @if (editable()) {
        <mat-form-field class="arena-dense min-w-48 flex-1">
          <mat-label>Note (optional)</mat-label>
          <input
            matInput
            autocomplete="off"
            maxlength="500"
            [value]="note()"
            (input)="note.set($any($event.target).value)"
          />
        </mat-form-field>
        @if (noteChanged()) {
          <button
            mat-stroked-button
            type="button"
            [disabled]="busy()"
            (click)="decided.emit({ applied: d.applied, note: note() })"
          >
            Save note
          </button>
        }
      } @else if (d.note) {
        <span class="text-[13px] text-muted">“{{ d.note }}”</span>
      }
    </div>
  `,
})
export class DeductionRow {
  readonly deduction = input.required<Deduction>();
  readonly editable = input(false);
  readonly busy = input(false);
  readonly decided = output<DeductionDecision>();

  protected readonly note = linkedSignal(() => this.deduction().note ?? '');
  protected readonly noteChanged = computed(
    () => this.note().trim() !== (this.deduction().note ?? '').trim(),
  );
  protected readonly formula = computed(() => deductionFormula(this.deduction()));
  protected readonly amount = computed(() => formatPaise(this.deduction().amountPaise));
}
