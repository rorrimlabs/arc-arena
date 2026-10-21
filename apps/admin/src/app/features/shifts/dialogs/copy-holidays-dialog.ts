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
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { ShiftsStore } from '../data/shifts-store';
import { ArenaHoliday, formatDay } from '../data/shifts.models';

export interface CopyHolidaysDialogData {
  /** The arena holidays that are not staff holidays yet. */
  readonly missing: readonly ArenaHoliday[];
}

export interface CopyHolidaysDialogResult {
  readonly snack: string;
}

/**
 * "Copy from arena holidays": the price list's holidays (this month and the next 12) that are
 * not staff holidays yet, each ticked; the ticked ones are added as paid staff holidays in one
 * call (one staff_holiday.upsert per day).
 */
@Component({
  selector: 'app-copy-holidays-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [MatDialogTitle, MatDialogContent, MatDialogActions, MatCheckbox, MatButton],
  template: `
    <h2 mat-dialog-title>Copy from arena holidays</h2>
    <mat-dialog-content>
      <div class="flex flex-col gap-4 pt-1">
        <p class="text-sm leading-[1.4] text-muted">
          These holidays from Pricing are not staff holidays yet. The ones you tick are added as
          paid staff holidays.
        </p>
        <ul class="flex flex-col gap-1" aria-label="Arena holidays to copy">
          @for (h of data.missing; track h.day) {
            <li>
              <mat-checkbox [checked]="picked().has(h.day)" (change)="toggle(h.day, $event.checked)">
                {{ h.name }} · {{ day(h.day) }}
              </mat-checkbox>
            </li>
          }
        </ul>
        @if (error()) {
          <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
        }
      </div>
    </mat-dialog-content>
    <mat-dialog-actions align="end">
      <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
      <button
        mat-flat-button
        type="button"
        [disabled]="busy() || !count()"
        (click)="copy()"
      >
        {{ label() }}
      </button>
    </mat-dialog-actions>
  `,
})
export class CopyHolidaysDialog {
  protected readonly data = inject<CopyHolidaysDialogData>(MAT_DIALOG_DATA);
  protected readonly ref =
    inject<MatDialogRef<CopyHolidaysDialog, CopyHolidaysDialogResult>>(MatDialogRef);
  private readonly store = inject(ShiftsStore);

  protected readonly day = formatDay;
  protected readonly picked = signal(new Set(this.data.missing.map((h) => h.day)));
  protected readonly count = computed(() => this.picked().size);
  protected readonly label = computed(() =>
    this.count() === 1 ? 'Add 1 holiday' : `Add ${this.count()} holidays`,
  );
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected toggle(day: string, on: boolean): void {
    this.picked.update((s) => {
      const next = new Set(s);
      if (on) next.add(day);
      else next.delete(day);
      return next;
    });
  }

  protected async copy(): Promise<void> {
    const days = this.data.missing.filter((h) => this.picked().has(h.day));
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.copyHolidays(days);
      this.ref.close({
        snack: `${days.length} staff holiday${days.length === 1 ? '' : 's'} added`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
