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
import { ShiftsStore } from '../data/shifts-store';
import {
  ArenaHoliday,
  StaffHoliday,
  copyWindow,
  formatDay,
  missingHolidays,
} from '../data/shifts.models';
import {
  CopyHolidaysDialog,
  CopyHolidaysDialogData,
  CopyHolidaysDialogResult,
} from '../dialogs/copy-holidays-dialog';
import {
  StaffHolidayDialog,
  StaffHolidayDialogData,
  StaffHolidayDialogResult,
} from '../dialogs/staff-holiday-dialog';

/** One staff holiday: name over its date, Paid or Unpaid, Edit and Delete. */
@Component({
  selector: 'app-staff-holiday-row',
  imports: [StatusPill, MatIconButton, MatIcon],
  host: { class: 'flex items-center gap-2', role: 'group', '[attr.aria-label]': 'holiday().name' },
  template: `
    @let h = holiday();
    <span class="flex min-w-0 flex-1 flex-col gap-1">
      <span class="truncate text-[15px] leading-[1.3]">{{ h.name }}</span>
      <span class="text-[13px] leading-[1.3] text-muted">{{ day() }}</span>
    </span>
    <app-status-pill [tone]="h.paid ? 'success' : 'info'">{{
      h.paid ? 'Paid' : 'Unpaid'
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
export class StaffHolidayRow {
  readonly holiday = input.required<StaffHoliday>();
  readonly disabled = input(false);
  readonly edit = output<void>();
  readonly remove = output<void>();

  protected readonly day = computed(() => formatDay(this.holiday().day));
}

/**
 * Staff holidays (`staff_holidays`): days nobody is expected at work, paid by default. Separate
 * from the price list's holidays; "Copy from arena holidays" offers the price list's ones that
 * are missing here. Each change is saved on its own and the list reloads.
 */
@Component({
  selector: 'app-staff-holidays',
  imports: [DetailPane, DetailSection, StaffHolidayRow, MatButton, MatIcon],
  template: `
    <app-detail-pane
      crumb="Staff / Shifts / Staff holidays"
      icon="event_available"
      heading="Staff holidays"
      [subtitle]="subtitle()"
      (closed)="closed.emit()"
    >
      <div actions class="arena-compact flex gap-2">
        <button mat-stroked-button type="button" [disabled]="!canEdit() || busy()" (click)="add()">
          <mat-icon aria-hidden="true">add</mat-icon>Holiday
        </button>
      </div>
      @if (!canEdit()) {
        <p role="note" class="text-[13px] leading-[1.45] text-muted">
          Viewing only: changing staff holidays needs the Settings permission.
        </p>
      }
      <div>
        <button
          mat-stroked-button
          type="button"
          [disabled]="!canEdit() || busy()"
          (click)="copyFromArena()"
        >
          <mat-icon aria-hidden="true">content_copy</mat-icon>Copy from arena holidays
        </button>
      </div>

      <app-detail-section
        heading="Coming up"
        subtitle="Paid holidays are paid to monthly staff as usual. Work on a holiday counts as extra hours."
      >
        @for (h of upcoming(); track h.day) {
          <app-staff-holiday-row
            [holiday]="h"
            [disabled]="busy() || !canEdit()"
            (edit)="edit(h)"
            (remove)="remove(h)"
          />
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">
            No staff holidays coming up. Add them here or copy the arena's holidays.
          </p>
        }
        @if (error()) {
          <p role="alert" class="text-sm font-medium text-danger">{{ error() }}</p>
        }
      </app-detail-section>

      @if (past().length) {
        <app-detail-section heading="Past" subtitle="Kept for reference.">
          @for (h of past(); track h.day) {
            <app-staff-holiday-row
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
export class StaffHolidays {
  protected readonly canEdit = inject(ArenaContext).canEdit;
  private readonly store = inject(ShiftsStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly closed = output<void>();

  /** Today in the arena (IST). */
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
    return next ? `Next: ${next.name} · ${formatDay(next.day)}` : 'None coming up';
  });
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected add(): void {
    this.open({});
  }

  protected edit(holiday: StaffHoliday): void {
    this.open({ holiday });
  }

  private open(data: StaffHolidayDialogData): void {
    this.dialog
      .open<StaffHolidayDialog, StaffHolidayDialogData, StaffHolidayDialogResult>(
        StaffHolidayDialog,
        { data, width: '520px', maxWidth: 'calc(100vw - 32px)' },
      )
      .afterClosed()
      .subscribe((r) => {
        if (r) this.say(r.snack);
      });
  }

  /** Reads the price list's holidays for this month and the next 12; offers the missing ones. */
  protected async copyFromArena(): Promise<void> {
    const { first, last } = copyWindow(this.today);
    this.busy.set(true);
    this.error.set('');
    let missing: ArenaHoliday[];
    try {
      missing = missingHolidays(await this.store.arenaHolidays(first, last), this.store.holidays());
    } catch (e) {
      this.error.set(toAppError(e).message);
      return;
    } finally {
      this.busy.set(false);
    }
    if (!missing.length) {
      this.say('Every arena holiday in the next 12 months is already a staff holiday');
      return;
    }
    this.dialog
      .open<CopyHolidaysDialog, CopyHolidaysDialogData, CopyHolidaysDialogResult>(
        CopyHolidaysDialog,
        { data: { missing }, width: '520px', maxWidth: 'calc(100vw - 32px)' },
      )
      .afterClosed()
      .subscribe((r) => {
        if (r) this.say(r.snack);
      });
  }

  /** staff_holiday.delete, after a confirmation. */
  protected remove(h: StaffHoliday): void {
    const data: ConfirmDialogData = {
      title: `Delete ${h.name}?`,
      message: `${formatDay(h.day)} becomes a normal working day for staff. Finalised salary runs keep what they were paid on.`,
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
