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
import { ShiftsStore } from '../data/shifts-store';
import { StaffHoliday, formatDay, isDay } from '../data/shifts.models';

export interface StaffHolidayDialogData {
  /** Absent: add one. Present: edit it (its day may move). */
  readonly holiday?: StaffHoliday;
}

export interface StaffHolidayDialogResult {
  readonly snack: string;
}

export const MAX_STAFF_HOLIDAY_NAME = 60;

/**
 * Add or edit a staff holiday (staff_holiday.upsert, keyed by day): the date, a name and
 * whether it is paid (the default). One holiday per day, so a day another holiday has is refused
 * here; moving one to another day clears the old day.
 */
@Component({
  selector: 'app-staff-holiday-dialog',
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
    <h2 mat-dialog-title>{{ editing ? 'Edit staff holiday' : 'Add staff holiday' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">
            Nobody is expected at work that day. Anyone who works it gets every minute as extra
            hours.
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
              <span class="text-[15px] leading-[1.3]" id="staff-holiday-paid">Paid</span>
              <span class="text-[13px] leading-[1.3] text-muted" id="staff-holiday-paid-sub">
                Monthly staff are paid for the day as usual
              </span>
            </span>
            <mat-slide-toggle
              hideIcon
              aria-labelledby="staff-holiday-paid"
              aria-describedby="staff-holiday-paid-sub"
              [formField]="f.paid"
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
export class StaffHolidayDialog {
  private readonly data = inject<StaffHolidayDialogData>(MAT_DIALOG_DATA);
  protected readonly ref =
    inject<MatDialogRef<StaffHolidayDialog, StaffHolidayDialogResult>>(MatDialogRef);
  private readonly store = inject(ShiftsStore);

  protected readonly editing = !!this.data.holiday;

  protected readonly model = signal({
    day: this.data.holiday?.day ?? formatIsoDate(inject(Clock).now()),
    name: this.data.holiday?.name ?? '',
    paid: this.data.holiday?.paid ?? true,
  });
  protected readonly f = form(this.model, (p) => {
    validate(p.day, ({ value }) => {
      const day = value();
      if (!isDay(day)) return { kind: 'day', message: 'Pick a date' };
      const taken = this.store
        .holidays()
        .find((h) => h.day === day && h.day !== this.data.holiday?.day);
      return taken
        ? {
            kind: 'taken',
            message: `${formatDay(day)} is already ${taken.name} · edit that one instead`,
          }
        : null;
    });
    const nameMessage = `Enter a name of up to ${MAX_STAFF_HOLIDAY_NAME} characters`;
    maxLength(p.name, MAX_STAFF_HOLIDAY_NAME, { message: nameMessage });
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
    const m = this.model();
    const holiday = { day: m.day, name: m.name.trim(), paid: m.paid };
    this.busy.set(true);
    this.error.set('');
    try {
      await this.store.saveHoliday(holiday, this.data.holiday?.day);
      this.ref.close({
        snack: this.editing
          ? `${holiday.name} saved`
          : `${holiday.name} added · ${formatDay(holiday.day)}`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
