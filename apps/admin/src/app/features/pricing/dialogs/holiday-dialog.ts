import { Component, inject, signal } from '@angular/core';
import { FormField, form, maxLength, validate } from '@angular/forms/signals';
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
import { MatSlideToggle } from '@angular/material/slide-toggle';
import { toAppError } from '../../../core/auth/auth-api';
import { Clock } from '../../../core/time/clock';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';
import { formatIsoDate } from '../../../shared/time/ist';
import { PricingStore } from '../data/pricing-store';
import { Holiday, formatHolidayDay, isCalendarDay } from '../data/pricing.models';

export interface HolidayDialogData {
  /** Absent: add a holiday. Present: edit it (its day may move). */
  readonly holiday?: Holiday;
}

/** Closes with the saved day and the snackbar text; undefined when cancelled. */
export interface HolidayDialogResult {
  readonly day: string;
  readonly snack: string;
}

export const MAX_HOLIDAY_NAME = 60;

/**
 * Add or edit a holiday (holiday.upsert, keyed by day): its date, name and whether the arena is
 * closed all day. One holiday per day, so a date another holiday already has is refused here
 * rather than overwriting it. Moving a holiday to another date clears the old one.
 */
@Component({
  selector: 'app-holiday-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    FormField,
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatSlideToggle,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>{{ editing ? 'Edit holiday' : 'Add holiday' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            Pricing rules set to skip holidays don't apply that day. Sessions already started keep
            their prices.
          </p>
          <mat-form-field>
            <mat-label>Date</mat-label>
            <input matInput type="date" [formField]="f.day" />
            <mat-hint>The arena's calendar day (IST)</mat-hint>
          </mat-form-field>
          <mat-form-field>
            <mat-label>Name</mat-label>
            <input matInput autocomplete="off" placeholder="Diwali" [formField]="f.name" />
          </mat-form-field>
          <div class="flex items-center justify-between gap-4">
            <span class="flex flex-col gap-1">
              <span class="text-[15px] leading-[1.3]" id="holiday-closed">Closed all day</span>
              <span class="text-[13px] leading-[1.3] text-muted" id="holiday-closed-sub">
                The arena doesn't open at all that day
              </span>
            </span>
            <mat-slide-toggle
              hideIcon
              aria-labelledby="holiday-closed"
              aria-describedby="holiday-closed-sub"
              [formField]="f.closed"
            />
          </div>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save' : 'Add holiday' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class HolidayDialog {
  private readonly data = inject<HolidayDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<HolidayDialog, HolidayDialogResult>>(MatDialogRef);
  private readonly store = inject(PricingStore);

  protected readonly editing = !!this.data.holiday;

  protected readonly model = signal({
    // A new holiday starts on the arena's today (IST), from the app clock.
    day: this.data.holiday?.day ?? formatIsoDate(inject(Clock).now()),
    name: this.data.holiday?.name ?? '',
    closed: this.data.holiday?.closed ?? false,
  });
  protected readonly f = form(this.model, (p) => {
    validate(p.day, ({ value }) => {
      const day = value();
      if (!isCalendarDay(day)) return { kind: 'day', message: 'Pick a date' };
      const taken = this.store
        .holidays()
        .find((h) => h.day === day && h.day !== this.data.holiday?.day);
      return taken
        ? {
            kind: 'taken',
            message: `${formatHolidayDay(day)} is already ${taken.name} · edit that one instead`,
          }
        : null;
    });
    const nameMessage = `Enter a name of up to ${MAX_HOLIDAY_NAME} characters`;
    maxLength(p.name, MAX_HOLIDAY_NAME, { message: nameMessage });
    validate(p.name, ({ value }) =>
      value().trim() ? null : { kind: 'name', message: nameMessage },
    );
  });
  protected readonly error = signal('');
  protected readonly busy = signal(false);

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const before = this.data.holiday;
    const holiday: Holiday = {
      day: this.model().day,
      name: this.model().name.trim(),
      closed: this.model().closed,
    };
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveHoliday(holiday, before?.day);
      this.ref.close({
        day: holiday.day,
        snack: before
          ? `${holiday.name} saved`
          : `${holiday.name} added · ${formatHolidayDay(holiday.day)}`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
