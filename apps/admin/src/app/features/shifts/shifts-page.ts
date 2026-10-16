import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { Clock } from '../../core/time/clock';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatIsoDate } from '../../shared/time/ist';
import { RosterView } from './components/roster-view';
import { ShiftDetail } from './components/shift-detail';
import { StaffHolidays } from './components/staff-holidays';
import { ShiftsStore } from './data/shifts-store';
import { daysLabel, isDay, shiftTimes } from './data/shifts.models';
import { ShiftDialog, ShiftDialogData, ShiftDialogResult } from './dialogs/shift-dialog';

/**
 * Staff › Shifts & holidays (docs/STAFF.md §6): the arena's shifts (list-detail: times, days,
 * break, who is assigned with effective dates), a read-only weekly roster and the staff
 * holidays. Everyone who can open the dashboard sees it; changes need the Settings permission.
 * The selection is in the URL (`?id=<shift>|roster|holidays`, `&week=2026-10-15`).
 */
@Component({
  selector: 'app-shifts-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    ShiftDetail,
    RosterView,
    StaffHolidays,
    MatButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Shifts and holidays"
      detailLabel="Shift"
      emptyText="Pick a shift, the weekly roster or the staff holidays"
      [open]="!!view()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Shifts & holidays" back="/settings" backLabel="Back to settings">
          <button
            actions
            mat-stroked-button
            type="button"
            [disabled]="!canEdit() || !store.data()"
            (click)="addShift()"
          >
            <mat-icon aria-hidden="true">add</mat-icon>Shift
          </button>
          @if (!canEdit()) {
            <p role="note" class="text-[13px] leading-[1.3] text-muted">
              Viewing only: changes need the Settings permission.
            </p>
          }
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading shifts" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <p role="alert" class="px-4 py-12 text-center text-sm text-danger">{{ error }}</p>
          } @else if (store.data()) {
            <ul class="flex flex-col gap-0.5" aria-label="Plans">
              <li>
                <app-list-row
                  title="Weekly roster"
                  subtitle="Who works which day"
                  icon="calendar_view_week"
                  [selected]="view() === 'roster'"
                  [queryParams]="{ id: 'roster' }"
                  queryParamsHandling="merge"
                />
              </li>
              <li>
                <app-list-row
                  title="Staff holidays"
                  [subtitle]="holidaysSub()"
                  icon="event_available"
                  [selected]="view() === 'holidays'"
                  [queryParams]="{ id: 'holidays' }"
                  queryParamsHandling="merge"
                />
              </li>
            </ul>
            <h2 class="px-3 pt-4 pb-2 text-[13px] leading-none font-semibold text-muted">
              Shifts · {{ store.shifts().length }}
            </h2>
            <ul class="flex flex-col gap-0.5" aria-label="Shifts">
              @for (s of store.shifts(); track s.id) {
                <li>
                  <app-list-row
                    [title]="s.name"
                    [subtitle]="rowSub(s)"
                    icon="schedule"
                    [selected]="s.id === shift()?.id"
                    [queryParams]="{ id: s.id }"
                    queryParamsHandling="merge"
                  >
                    @if (!s.active) {
                      <app-status-pill tone="warning">Not in use</app-status-pill>
                    }
                  </app-list-row>
                </li>
              } @empty {
                <li class="px-4 py-8 text-center text-sm leading-[1.4] text-muted">
                  No shifts yet. Add one, then assign staff to it.
                </li>
              }
            </ul>
          }
        </div>
      </ng-container>
      <ng-container detail>
        @switch (view()) {
          @case ('roster') {
            <app-roster-view [day]="week()" (dayChange)="setWeek($event)" (closed)="close()" />
          }
          @case ('holidays') {
            <app-staff-holidays (closed)="close()" />
          }
          @case ('shift') {
            @if (shift(); as s) {
              <app-shift-detail [shift]="s" (closed)="close()" />
            }
          }
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class ShiftsPage {
  protected readonly store = inject(ShiftsStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly clock = inject(Clock);

  /** `?id=` — a shift id, `roster` or `holidays`. */
  readonly id = input<string>();
  /** `?week=` — any IST date of the roster's week (default today). */
  readonly weekParam = input<string>(undefined, { alias: 'week' });

  protected readonly canEdit = this.arena.canEdit;
  protected readonly shift = computed(() => {
    const id = this.id();
    return id ? this.store.shifts().find((s) => s.id === id) : undefined;
  });
  protected readonly view = computed<'roster' | 'holidays' | 'shift' | undefined>(() => {
    const id = this.id();
    if (id === 'roster' || id === 'holidays') return id;
    if (this.shift()) return 'shift';
    return this.layout.wideDetail() && this.store.data() ? 'roster' : undefined;
  });
  protected readonly week = computed(() => {
    const w = this.weekParam();
    return w && isDay(w) ? w : formatIsoDate(this.clock.now());
  });
  protected readonly holidaysSub = computed(() => {
    const today = formatIsoDate(this.clock.now());
    const n = this.store.holidays().filter((h) => h.day >= today).length;
    return n ? `${n} coming up` : 'None coming up';
  });

  constructor() {
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

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
        void this.router.navigate([], {
          queryParams: { id: r.id },
          queryParamsHandling: 'merge',
        });
      });
  }

  protected setWeek(day: string): void {
    void this.router.navigate([], { queryParams: { week: day }, queryParamsHandling: 'merge' });
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }
}
