import { Component, computed, inject, input, output, signal } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Clock } from '../../../core/time/clock';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatIsoDate } from '../../../shared/time/ist';
import { PricingStore } from '../data/pricing-store';
import { Holiday, formatHolidayDay } from '../data/pricing.models';
import { HolidayDialog, HolidayDialogData, HolidayDialogResult } from '../dialogs/holiday-dialog';

/** One holiday: name over its date, closed or open, Edit and Delete. */
@Component({
  selector: 'app-holiday-row',
  imports: [StatusPill, MatIconButton, MatIcon],
  host: { class: 'flex items-center gap-2', role: 'group', '[attr.aria-label]': 'holiday().name' },
  template: `
    @let h = holiday();
    <span class="flex min-w-0 flex-1 flex-col gap-1">
      <span class="truncate text-[15px] leading-[1.3]">{{ h.name }}</span>
      <span class="text-[13px] leading-[1.3] text-muted">{{ day() }}</span>
    </span>
    <app-status-pill [tone]="h.closed ? 'warning' : 'info'">{{
      h.closed ? 'Closed' : 'Open'
    }}</app-status-pill>
    <button
      mat-icon-button
      type="button"
      [attr.aria-label]="'Edit ' + h.name"
      [disabled]="disabled()"
      (click)="edit.emit()"
    >
      <mat-icon aria-hidden="true">edit</mat-icon>
    </button>
    <button
      mat-icon-button
      type="button"
      [attr.aria-label]="'Delete ' + h.name"
      [disabled]="disabled()"
      (click)="remove.emit()"
    >
      <mat-icon aria-hidden="true">delete</mat-icon>
    </button>
  `,
})
export class HolidayRow {
  readonly holiday = input.required<Holiday>();
  readonly disabled = input(false);
  readonly edit = output<void>();
  readonly remove = output<void>();

  protected readonly day = computed(() => formatHolidayDay(this.holiday().day));
}

/**
 * Holidays (server: holidays; part of the price list): special days that pricing rules can skip
 * (or apply only on), optionally closed all day. Coming-up days first, then past ones (most recent first). Each change is saved on its
 * own (holiday.upsert / holiday.delete) and the price list reloads.
 */
@Component({
  selector: 'app-holidays-detail',
  imports: [DetailPane, DetailSection, HolidayRow, MatButton, MatIcon],
  template: `
    <app-detail-pane
      crumb="Pricing / Holidays"
      icon="event_busy"
      heading="Holidays"
      [subtitle]="subtitle()"
      (closed)="closed.emit()"
    >
      <div actions class="arena-compact flex gap-2">
        <button mat-stroked-button type="button" [disabled]="!canEdit()" (click)="add()">
          <mat-icon aria-hidden="true">add</mat-icon>Holiday
        </button>
      </div>

      <app-detail-section
        heading="Coming up"
        subtitle="Rules set to skip holidays don't apply on these days. A closed day is shut all day."
      >
        @for (h of upcoming(); track h.day) {
          <app-holiday-row
            [holiday]="h"
            [disabled]="busy() || !canEdit()"
            (edit)="edit(h)"
            (remove)="remove(h)"
          />
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">
            No holidays coming up. Add public holidays and the days the arena is closed.
          </p>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      @if (past().length) {
        <app-detail-section
          heading="Past"
          subtitle="Kept for reference. Delete any you no longer need."
        >
          @for (h of past(); track h.day) {
            <app-holiday-row
              [holiday]="h"
              [disabled]="busy() || !canEdit()"
              (edit)="edit(h)"
              (remove)="remove(h)"
            />
          }
        </app-detail-section>
      }
    </app-detail-pane>
  `,
})
export class HolidaysDetail {
  /** Without the Settings permission the server refuses every change here. */
  protected readonly canEdit = inject(ArenaContext).canEdit;
  private readonly store = inject(PricingStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly closed = output<void>();

  /** Today in the arena (IST), "2026-10-13". */
  private readonly today = formatIsoDate(inject(Clock).now());
  protected readonly upcoming = computed(() =>
    this.store.holidays().filter((h) => h.day >= this.today),
  );
  protected readonly past = computed(() =>
    this.store
      .holidays()
      .filter((h) => h.day < this.today)
      .reverse(),
  );
  protected readonly subtitle = computed(() => {
    const next = this.upcoming()[0];
    return next ? `Next: ${next.name} · ${formatHolidayDay(next.day)}` : 'None coming up';
  });
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected add(): void {
    this.open({});
  }

  protected edit(holiday: Holiday): void {
    this.open({ holiday });
  }

  private open(data: HolidayDialogData): void {
    this.dialog
      .open<HolidayDialog, HolidayDialogData, HolidayDialogResult>(HolidayDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (result) this.say(result.snack);
      });
  }

  /** holiday.delete, after a confirmation that says what changes. */
  protected remove(h: Holiday): void {
    const data: ConfirmDialogData = {
      title: `Delete ${h.name}?`,
      message: `${formatHolidayDay(h.day)} becomes a normal day for pricing rules${
        h.closed ? ' and the arena counts as open' : ''
      }. Sessions already started keep their prices.`,
      confirm: 'Delete',
      danger: true,
    };
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        this.busy.set(true);
        this.error.set('');
        try {
          await this.store.deleteHoliday(h.day);
          this.say(`${h.name} deleted`);
        } catch (e) {
          this.error.set(toAppError(e).message);
        } finally {
          this.busy.set(false);
        }
      });
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
