import { Component, computed, effect, inject, linkedSignal, output, signal } from '@angular/core';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { UnsavedBar } from '../../../shared/list-detail/unsaved-bar';
import {
  DEFAULT_LEAVE_RULES,
  LeaveRulesDraft,
  LeaveRulesStore,
  fromLeaveDraft,
  leaveDraftProblems,
  leaveRulesSummary,
  sameLeaveDraft,
  toLeaveDraft,
} from '../data/leave-rules';

/**
 * Settings › Leave rules (docs/STAFF.md §2 Leave): the paid-leave allowance per leave year (a
 * person's own allowance is set in Staff › Pay setup), whether half days may be asked for, and
 * how many days back unplanned leave may be applied. Saves the whole `leave_rules` setting.
 */
@Component({
  selector: 'app-leave-settings',
  imports: [
    DetailPane,
    DetailSection,
    ToggleRow,
    UnsavedBar,
    MatFormField,
    MatLabel,
    MatHint,
    MatSuffix,
    MatInput,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Staff / Leave rules"
      icon="event_available"
      heading="Leave rules"
      [subtitle]="summary()"
      (closed)="closed.emit()"
    >
      @if (store.loadError(); as error) {
        <app-detail-section>
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Leave rules couldn't load: {{ error }}
          </p>
        </app-detail-section>
      } @else if (!store.rules()) {
        <app-detail-section>
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        </app-detail-section>
      } @else {
        @let d = draft();
        @let p = shownProblems();
        <app-detail-section
          heading="Paid leave"
          subtitle="The leave year starts on each person's joining date. Unused days don't carry over."
        >
          <mat-form-field class="max-w-72">
            <mat-label>Paid leave days per year</mat-label>
            <input
              matInput
              type="number"
              inputmode="decimal"
              min="0"
              max="366"
              step="0.5"
              aria-describedby="leave-paid-error"
              [attr.aria-invalid]="!!p.paidLeaveDays"
              [disabled]="!canEdit()"
              [value]="d.paidLeaveDays"
              (input)="set({ paidLeaveDays: $any($event.target).value })"
            />
            <span matTextSuffix>days</span>
            <mat-hint>0–366, half days allowed. A person's own number is set in Pay setup</mat-hint>
          </mat-form-field>
          @if (p.paidLeaveDays) {
            <p id="leave-paid-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.paidLeaveDays }}
            </p>
          }
          <app-toggle-row
            label="Half-day leave"
            sub="Staff may ask for the first or second half of a single day"
            [checked]="d.halfDayAllowed"
            [disabled]="!canEdit()"
            (changed)="set({ halfDayAllowed: $event.checked })"
          />
        </app-detail-section>

        <app-detail-section
          heading="Unplanned leave"
          subtitle="Sick days and emergencies can be applied for afterwards. Planned leave must start today or later."
        >
          <mat-form-field class="max-w-72">
            <mat-label>Can be applied up to</mat-label>
            <input
              matInput
              type="number"
              inputmode="numeric"
              min="0"
              max="31"
              aria-describedby="leave-back-error"
              [attr.aria-invalid]="!!p.unplannedBackdateDays"
              [disabled]="!canEdit()"
              [value]="d.unplannedBackdateDays"
              (input)="set({ unplannedBackdateDays: $any($event.target).value })"
            />
            <span matTextSuffix>days back</span>
            <mat-hint>0–31 days</mat-hint>
          </mat-form-field>
          @if (p.unplannedBackdateDays) {
            <p id="leave-back-error" role="alert" class="text-[13px] leading-[1.4] text-danger">
              {{ p.unplannedBackdateDays }}
            </p>
          }
          @if (error()) {
            <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
          }
        </app-detail-section>
      }

      @if (dirty()) {
        <app-unsaved-bar footer [busy]="busy()" (discard)="discard()" (save)="save()" />
      }
    </app-detail-pane>
  `,
})
export class LeaveSettings {
  private readonly arena = inject(ArenaContext);
  protected readonly store = inject(LeaveRulesStore);
  private readonly snack = inject(MatSnackBar);
  readonly closed = output<void>();

  protected readonly canEdit = this.arena.canEdit;
  private readonly saved = computed(() => toLeaveDraft(this.store.rules() ?? DEFAULT_LEAVE_RULES));
  protected readonly draft = linkedSignal<LeaveRulesDraft>(() => this.saved());
  protected readonly dirty = computed(
    () => !!this.store.rules() && !sameLeaveDraft(this.draft(), this.saved()),
  );
  private readonly tried = signal(false);
  protected readonly shownProblems = computed(() =>
    this.tried() ? leaveDraftProblems(this.draft()) : {},
  );
  protected readonly summary = computed(() => {
    const r = this.store.rules();
    return r ? leaveRulesSummary(r) : this.arena.current().name;
  });
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected set(change: Partial<LeaveRulesDraft>): void {
    this.draft.update((d) => ({ ...d, ...change }));
    this.error.set('');
  }

  protected discard(): void {
    this.draft.set(this.saved());
    this.tried.set(false);
    this.error.set('');
  }

  protected async save(): Promise<void> {
    this.tried.set(true);
    const rules = fromLeaveDraft(this.draft());
    if (!rules) {
      this.error.set('Fix the values marked above, then save again');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.save(rules);
      this.tried.set(false);
      this.snack.open('Leave rules saved', undefined, { duration: 3200 });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
