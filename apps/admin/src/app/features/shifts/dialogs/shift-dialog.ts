import { Component, computed, inject, signal } from '@angular/core';
import { FormField, form } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatChipListbox, MatChipListboxChange, MatChipOption } from '@angular/material/chips';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatHint, MatLabel, MatSuffix } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { toAppError } from '../../../core/auth/auth-api';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatMinutes } from '../../../shared/time/ist';
import { WEEKDAYS } from '../../settings/data/work-hours';
import { ShiftsStore } from '../data/shifts-store';
import {
  Shift,
  fromTimeValue,
  shiftLength,
  shiftProblem,
  shiftTimes,
  toTimeValue,
} from '../data/shifts.models';

export interface ShiftDialogData {
  /** Absent: a new shift. Present: edit it. */
  readonly shift?: Shift;
}

/** Closes with the saved shift's id and the snackbar text; undefined when cancelled. */
export interface ShiftDialogResult {
  readonly id: string;
  readonly snack: string;
}

/**
 * Add or edit a shift (shift.upsert; a new one gets a client uuid): name, start and end (an end
 * at or before the start ends the next day), days of the week, the unpaid break and whether it
 * is in use. Shows the shift's paid length as it is typed; refusals stay in the dialog.
 */
@Component({
  selector: 'app-shift-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    FormField,
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatSuffix,
    MatInput,
    MatChipListbox,
    MatChipOption,
    MatSlideToggle,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>{{ editing ? 'Edit shift' : 'New shift' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <mat-form-field>
            <mat-label>Name</mat-label>
            <input matInput autocomplete="off" placeholder="Morning" [formField]="f.name" />
          </mat-form-field>
          <div class="grid grid-cols-2 gap-3">
            <mat-form-field>
              <mat-label>Starts</mat-label>
              <input matInput type="time" [formField]="f.start" />
            </mat-form-field>
            <mat-form-field>
              <mat-label>Ends</mat-label>
              <input matInput type="time" [formField]="f.end" />
              <mat-hint>Before the start: ends the next day</mat-hint>
            </mat-form-field>
          </div>
          <mat-form-field>
            <mat-label>Unpaid break</mat-label>
            <input matInput inputmode="numeric" autocomplete="off" [formField]="f.breakMin" />
            <span matTextSuffix>min</span>
          </mat-form-field>
          <div class="flex flex-col gap-2">
            <span class="text-[15px] leading-[1.3]" id="shift-days-label">Days</span>
            <mat-chip-listbox
              multiple
              aria-labelledby="shift-days-label"
              [value]="days()"
              (change)="pickDays($event)"
            >
              @for (w of weekdays; track w.value) {
                <mat-chip-option [value]="w.value" [attr.aria-label]="w.label">{{
                  w.short
                }}</mat-chip-option>
              }
            </mat-chip-listbox>
          </div>
          <div class="flex items-center justify-between gap-4">
            <span class="flex flex-col gap-1">
              <span class="text-[15px] leading-[1.3]" id="shift-active">In use</span>
              <span class="text-[13px] leading-[1.3] text-muted" id="shift-active-sub">
                A shift not in use stays on past days but plans no new ones
              </span>
            </span>
            <mat-slide-toggle
              hideIcon
              aria-labelledby="shift-active"
              aria-describedby="shift-active-sub"
              [formField]="f.active"
            />
          </div>
          <p class="text-[13px] leading-[1.4] text-muted" aria-live="polite">{{ preview() }}</p>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save' : 'Add shift' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class ShiftDialog {
  private readonly data = inject<ShiftDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<ShiftDialog, ShiftDialogResult>>(MatDialogRef);
  private readonly store = inject(ShiftsStore);

  protected readonly editing = !!this.data.shift;
  protected readonly weekdays = WEEKDAYS;

  protected readonly model = signal({
    name: this.data.shift?.name ?? '',
    start: toTimeValue(this.data.shift?.startMin ?? 540),
    end: toTimeValue(this.data.shift?.endMin ?? 1080),
    breakMin: String(this.data.shift?.breakMin ?? 0),
    active: this.data.shift?.active ?? true,
  });
  protected readonly f = form(this.model);
  protected readonly days = signal<number[]>([...(this.data.shift?.days ?? [1, 2, 3, 4, 5, 6])]);
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  /** The shift as typed (NaN where a field is not a number yet). */
  private readonly typed = computed<Shift>(() => {
    const m = this.model();
    const breakText = m.breakMin.trim();
    return {
      id: this.data.shift?.id ?? '',
      name: m.name,
      startMin: fromTimeValue(m.start) ?? Number.NaN,
      endMin: fromTimeValue(m.end) ?? Number.NaN,
      days: [...this.days()].sort((a, b) => a - b),
      breakMin: breakText === '' ? 0 : Number(breakText),
      active: m.active,
    };
  });
  /** "9:00 AM – 6:00 PM · 8h paid after a 1h break". */
  protected readonly preview = computed(() => {
    const s = this.typed();
    if (!Number.isFinite(s.startMin) || !Number.isFinite(s.endMin)) return 'Pick both times';
    const paid = Number.isFinite(s.breakMin) ? shiftLength(s) : Number.NaN;
    const length = Number.isFinite(paid) ? formatMinutes(paid) : '—';
    const brk = s.breakMin > 0 ? ` after a ${formatMinutes(s.breakMin)} break` : '';
    return `${shiftTimes(s)} · ${length} paid${brk}`;
  });

  protected pickDays(event: MatChipListboxChange): void {
    this.days.set(((event.value as number[] | null) ?? []).map(Number));
    this.error.set('');
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const typed = this.typed();
    const shift: Shift = { ...typed, id: typed.id || crypto.randomUUID(), name: typed.name.trim() };
    const problem = shiftProblem(shift, this.store.shifts());
    if (problem) {
      this.error.set(problem);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveShift(shift);
      this.ref.close({
        id: shift.id,
        snack: this.editing ? `${shift.name} saved` : `${shift.name} added`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
