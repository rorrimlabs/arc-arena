import { Component, computed, inject, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { Clock } from '../../../core/time/clock';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { formatDayYear } from '../../../shared/staff/staff-format';
import { formatIsoDate } from '../../../shared/time/ist';
import { PayPolicyRow, policyLines, policyOn, rowOn } from '../../payroll/data/pay-policy';
import { PaySetupStore } from '../data/pay-setup-store';
import { finalisedLimitText, minEffectiveFrom } from '../data/pay-setup.models';
import { PayPolicyDialog, PayPolicyDialogData } from '../dialogs/pay-policy-dialog';

/**
 * The arena's pay rules: those in force today in plain words, the history (each row applies to
 * runs starting on or after its date), and Change from… (rules are never edited).
 */
@Component({
  selector: 'app-pay-rules-detail',
  imports: [DetailPane, DetailSection, DetailRow, MatButton, MatIcon],
  template: `
    <app-detail-pane
      crumb="Staff / Pay setup / Pay rules"
      icon="rule"
      heading="Pay rules"
      [subtitle]="since()"
      (closed)="closed.emit()"
    >
      @if (canEdit()) {
        <button actions mat-stroked-button type="button" (click)="change()">
          <mat-icon aria-hidden="true">edit_calendar</mat-icon>Change from…
        </button>
      }
      <app-detail-section
        heading="In force today"
        subtitle="Deductions are only suggestions: on every pay run you keep or waive each one per person."
      >
        @for (l of lines(); track l.label) {
          <app-detail-row [label]="l.label" [value]="l.value" />
        }
        @if (limit()) {
          <p class="text-[13px] leading-[1.4] text-muted">{{ limit() }}</p>
        }
      </app-detail-section>
      <app-detail-section
        heading="History"
        subtitle="A pay run uses the rules in force on its first day."
      >
        @for (r of store.policies(); track r.id) {
          <div class="flex flex-col gap-1 border-b border-border pb-3 last:border-b-0 last:pb-0">
            <span class="text-sm font-semibold">From {{ day(r.effectiveFrom) }}</span>
            <span class="text-[13px] leading-[1.4] text-muted">{{ brief(r) }}</span>
            <span class="text-xs text-muted">Set by {{ store.userName(r.createdBy) }}</span>
          </div>
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">
            None saved: the defaults above apply until you change them.
          </p>
        }
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class PayRulesDetail {
  protected readonly store = inject(PaySetupStore);
  private readonly arena = inject(ArenaContext);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  private readonly today = formatIsoDate(inject(Clock).now());
  protected readonly day = formatDayYear;
  protected readonly canEdit = computed(() => this.arena.hasPerm('payroll'));
  private readonly rows = computed(() => this.store.data()?.policies ?? []);
  protected readonly current = computed(() => policyOn(this.rows(), this.today));
  protected readonly lines = computed(() => policyLines(this.current()));
  protected readonly since = computed(() => {
    const row = rowOn(this.rows(), this.today);
    return row ? `In force since ${formatDayYear(row.effectiveFrom)}` : 'The defaults';
  });
  protected readonly limit = computed(() =>
    finalisedLimitText(this.store.data()?.finalisedEnd ?? null),
  );

  protected brief(r: PayPolicyRow): string {
    return policyLines(r.policy)
      .map((l) => `${l.label}: ${l.value}`)
      .join(' · ');
  }

  protected change(): void {
    const finalisedEnd = this.store.data()?.finalisedEnd ?? null;
    const min = minEffectiveFrom(finalisedEnd);
    const data: PayPolicyDialogData = {
      current: this.current(),
      finalisedEnd,
      suggestedFrom: min && min > this.today ? min : this.today,
      taken: this.rows().map((r) => r.effectiveFrom),
    };
    this.dialog
      .open(PayPolicyDialog, { data, width: '560px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((done) => {
        if (done) this.snack.open('New pay rules saved', undefined, { duration: 3200 });
      });
  }
}
