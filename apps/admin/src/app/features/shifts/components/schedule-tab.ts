import { Component, computed, inject, input } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { MatAnchor, MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { map } from 'rxjs';
import { ArenaContext } from '../../../core/arena/arena-context';
import { Clock } from '../../../core/time/clock';
import { ListRow } from '../../../shared/list-detail/list-row';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatIsoDate } from '../../../shared/time/ist';
import { ShiftsStore } from '../data/shifts-store';
import { daysLabel, isDay, shiftTimes } from '../data/shifts.models';
import { ShiftDialog, ShiftDialogData, ShiftDialogResult } from '../dialogs/shift-dialog';
import { RosterView } from './roster-view';
import { ShiftDetail } from './shift-detail';
import { StaffHolidays } from './staff-holidays';

const SCHEDULE = '/settings/staff/schedule';

/**
 * Settings › Staff › Schedule (docs/STAFF.md §6): the arena's shifts, the read-only weekly
 * roster and the staff holidays, one under the other. A shift opens in its place at
 * `/settings/staff/schedule/<shift>`; the roster's week is `?week=2026-10-15`. Everyone who can
 * open the dashboard sees it; changes need the Settings permission.
 */
@Component({
  selector: 'app-schedule-tab',
  imports: [
    RosterView,
    StaffHolidays,
    ShiftDetail,
    ListRow,
    StatusPill,
    MatAnchor,
    MatButton,
    MatIcon,
    RouterLink,
  ],
  host: { class: 'flex flex-col gap-5' },
  template: `
    @if (shiftId()) {
      <div>
        <a mat-button [routerLink]="schedule" class="-ml-3">
          <mat-icon aria-hidden="true">arrow_back</mat-icon>All shifts
        </a>
      </div>
      @if (shift(); as s) {
        <app-shift-detail [shift]="s" (closed)="toSchedule()" />
      } @else if (store.data()) {
        <p class="text-sm leading-[1.4] text-muted">This shift no longer exists.</p>
      }
    } @else {
      @if (store.loadError(); as error) {
        <p role="alert" class="text-sm text-danger">{{ error }}</p>
      }
      <div class="flex flex-col gap-3">
        <div class="flex items-center gap-3">
          <div class="flex min-w-0 flex-1 flex-col gap-1">
            <h3 class="text-lg leading-[1.2] font-semibold">Shifts</h3>
            <span class="text-sm leading-[1.3] text-muted">{{ shiftsSub() }}</span>
          </div>
          <button
            mat-stroked-button
            type="button"
            [disabled]="!canEdit() || !store.data()"
            (click)="addShift()"
          >
            <mat-icon aria-hidden="true">add</mat-icon>Shift
          </button>
        </div>
        @if (!canEdit()) {
          <p role="note" class="text-[13px] leading-[1.3] text-muted">
            Viewing only: changes need the Settings permission.
          </p>
        }
        @if (store.data()) {
          <ul class="flex flex-col gap-0.5" aria-label="Shifts">
            @for (s of store.shifts(); track s.id) {
              <li>
                <app-list-row
                  [title]="s.name"
                  [subtitle]="rowSub(s)"
                  icon="schedule"
                  [link]="[schedule, s.id]"
                >
                  @if (!s.active) {
                    <app-status-pill tone="warning">Not in use</app-status-pill>
                  }
                </app-list-row>
              </li>
            } @empty {
              <li class="px-4 py-6 text-center text-sm leading-[1.4] text-muted">
                No shifts yet. Add one, then assign staff to it.
              </li>
            }
          </ul>
        }
      </div>
      <app-roster-view [day]="week()" (dayChange)="setWeek($event)" />
      <app-staff-holidays />
    }
  `,
})
export class ScheduleTab {
  protected readonly store = inject(ShiftsStore);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly clock = inject(Clock);

  /** The shift open (`/settings/staff/schedule/<shift>`), if any. */
  readonly shiftId = input<string | undefined>(undefined);

  protected readonly schedule = SCHEDULE;
  protected readonly canEdit = this.arena.canEdit;
  private readonly weekParam = toSignal(
    inject(ActivatedRoute).queryParamMap.pipe(map((p) => p.get('week'))),
  );
  protected readonly shift = computed(() => {
    const id = this.shiftId();
    return id ? this.store.shifts().find((s) => s.id === id) : undefined;
  });
  protected readonly week = computed(() => {
    const w = this.weekParam();
    return w && isDay(w) ? w : formatIsoDate(this.clock.now());
  });
  protected readonly shiftsSub = computed(() => {
    const n = this.store.shifts().filter((s) => s.active).length;
    return n ? `${n} in use` : 'None in use: every day is a day off';
  });

  protected rowSub(s: { startMin: number; endMin: number; days: readonly number[] }): string {
    return `${shiftTimes(s)} · ${daysLabel(s.days)}`;
  }

  protected addShift(): void {
    this.dialog
      .open<ShiftDialog, ShiftDialogData, ShiftDialogResult>(ShiftDialog, {
        data: {},
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => {
        if (!r) return;
        this.snack.open(r.snack, undefined, { duration: 3200 });
        void this.router.navigate([SCHEDULE, r.id]);
      });
  }

  protected setWeek(day: string): void {
    void this.router.navigate([], { queryParams: { week: day }, queryParamsHandling: 'merge' });
  }

  protected toSchedule(): void {
    void this.router.navigate([SCHEDULE]);
  }
}
