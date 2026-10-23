import { DOCUMENT } from '@angular/common';
import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton, MatIconButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatMenu, MatMenuItem, MatMenuTrigger } from '@angular/material/menu';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router, RouterLink } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Session } from '../../core/auth/session';
import { Layout } from '../../core/layout/layout';
import { Clock } from '../../core/time/clock';
import { injectNow } from '../../core/time/ticker';
import { DetailPane } from '../../shared/list-detail/detail-pane';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { addDays, formatIsoDate, formatMinutes, formatTime } from '../../shared/time/ist';
import { CalendarStore } from '../calendar/data/calendar-store';
import {
  CalendarRow,
  calendarRows,
  cellDate,
  monthDays,
  monthLabel,
  shiftMonth,
  units,
} from '../calendar/data/calendar.models';
import { LeaveStore } from '../leave/data/leave-store';
import { AttendanceRulesStore } from '../settings/data/attendance-rules';
import { ShiftsStore } from '../shifts/data/shifts-store';
import { initials } from '../users/components/user-format';
import { attendanceCsv } from './components/attendance-csv';
import { DayDetail } from './components/day-detail';
import { EntryDetail } from './components/entry-detail';
import { EntryRow } from './components/entry-row';
import { MonthGrid } from './components/month-grid';
import { PersonMonth } from './components/person-month';
import { AttendanceRequestsStore } from './data/attendance-requests';
import { AttendanceStore } from './data/attendance-store';
import { LogRow, StaffMember, isOwnRecord } from './data/attendance.models';
import { DayRow, dayCounts, dayRows } from './data/today.models';
import { MarkDialog, MarkDialogData, MarkDialogResult, MarkKind } from './dialogs/mark-dialog';
import { RequestsDialog } from './dialogs/requests-dialog';

/** The permission this screen needs (the owner holds every permission). */
export const ATTENDANCE_PERM = 'attendance_review';

/** How many days back the Today view looks for entries still waiting for review. */
const REVIEW_DAYS = 7;

/**
 * Staff › Attendance, in the list/detail frame of every other screen. Today lists each employee
 * with their status, clock-in, clock-out and hours; Calendar lists each employee's month, with
 * everyone's month grid beside the list on a wide screen. A person opens their day (or, in
 * Calendar, their month first) with the actions it allows; an entry opens with its evidence
 * under Technical details. Mark attendance adds hours someone worked without clocking in, or
 * records their paid or unpaid leave. Entries needing review and leave requests head the list
 * when there are any; the full log and the export are in the menu. Only employees are listed:
 * the server's attendance_days leaves out owners unless they are tracked as working here.
 * The view, month and selection are in the URL
 * (`?view=calendar&month=2026-10&staff=…&day=2026-10-15&id=…&review=1`).
 */
@Component({
  selector: 'app-attendance-home-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    DetailPane,
    StatusPill,
    MonthGrid,
    PersonMonth,
    DayDetail,
    EntryDetail,
    EntryRow,
    RouterLink,
    MatButton,
    MatIconButton,
    MatButtonToggleGroup,
    MatButtonToggle,
    MatIcon,
    MatMenu,
    MatMenuItem,
    MatMenuTrigger,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Attendance"
      [detailLabel]="detailLabel()"
      emptyText="Pick someone to see their day"
      [open]="detail() !== null"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Attendance">
          @if (canAttendance() || canLeave()) {
            <button
              actions
              mat-flat-button
              type="button"
              [disabled]="!attendance.log()"
              (click)="mark()"
            >
              <mat-icon aria-hidden="true">add</mat-icon>Mark
            </button>
          }
          <button
            actions
            mat-icon-button
            type="button"
            aria-label="More attendance options"
            [matMenuTriggerFor]="more"
          >
            <mat-icon aria-hidden="true">more_vert</mat-icon>
          </button>
          <mat-menu #more="matMenu" xPosition="before">
            <a mat-menu-item routerLink="records">
              <mat-icon aria-hidden="true">list_alt</mat-icon>Detailed records
            </a>
            @if (canLeave()) {
              <a mat-menu-item routerLink="leave">
                <mat-icon aria-hidden="true">event_available</mat-icon>Leave requests and balances
              </a>
            }
            <button
              mat-menu-item
              type="button"
              [disabled]="!periodRows().length"
              (click)="exportCsv()"
            >
              <mat-icon aria-hidden="true">download</mat-icon>Export (CSV)
            </button>
            <button mat-menu-item type="button" (click)="refresh()">
              <mat-icon aria-hidden="true">refresh</mat-icon>Refresh
            </button>
          </mat-menu>
          <mat-button-toggle-group
            aria-label="View"
            hideSingleSelectionIndicator
            [value]="view()"
            (change)="pickView($event.value)"
          >
            <mat-button-toggle value="today">Today</mat-button-toggle>
            <mat-button-toggle value="calendar">Calendar</mat-button-toggle>
          </mat-button-toggle-group>
          @if (view() === 'calendar') {
            <div class="-my-1 flex items-center gap-1">
              <button
                mat-icon-button
                type="button"
                aria-label="Previous month"
                (click)="setParams({ month: shiftMonth(month(), -1), staff: null, day: null })"
              >
                <mat-icon aria-hidden="true">chevron_left</mat-icon>
              </button>
              <span class="flex-1 text-center text-sm font-medium" aria-live="polite">{{
                monthTitle()
              }}</span>
              <button
                mat-icon-button
                type="button"
                aria-label="Next month"
                [disabled]="month() >= today().slice(0, 7)"
                (click)="setParams({ month: shiftMonth(month(), 1), staff: null, day: null })"
              >
                <mat-icon aria-hidden="true">chevron_right</mat-icon>
              </button>
            </div>
          }
          <p class="text-[13px] leading-[1.3] text-muted" aria-live="polite">{{ summary() }}</p>
        </app-list-pane-header>
        @if (calendar.loading() || attendance.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading attendance" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (calendar.loadError() || attendance.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="refresh()">Try again</button>
            </div>
          } @else if (calendar.days() && attendance.log()) {
            @if (pending().length || openLeave() || openRequests()) {
              <ul class="flex flex-col gap-0.5" aria-label="Waiting for you">
                @if (pending().length) {
                  <li>
                    <app-list-row
                      title="Needs review"
                      [subtitle]="pendingText()"
                      icon="error"
                      [selected]="reviewOpen()"
                      [queryParams]="{ review: 1, staff: null, day: null, id: null }"
                      queryParamsHandling="merge"
                    >
                      <app-status-pill tone="warning">{{ pending().length }}</app-status-pill>
                    </app-list-row>
                  </li>
                }
                @if (openRequests(); as n) {
                  <li>
                    <!-- Opens a dialog, not a page: a button styled like app-list-row. -->
                    <button
                      type="button"
                      class="flex min-h-16 w-full items-center gap-3 rounded-card px-3 py-2.5 text-left text-fg hover:bg-info-soft"
                      (click)="openRequestsDialog()"
                    >
                      <span
                        class="icon grid size-10 flex-none place-items-center rounded-card bg-surface text-[22px] text-muted"
                        aria-hidden="true"
                        >more_time</span
                      >
                      <span class="flex min-w-0 flex-1 flex-col gap-1">
                        <span class="truncate text-sm leading-[1.25] font-semibold"
                          >Missed time requests</span
                        >
                        <span class="truncate text-[12.5px] leading-[1.3] text-muted"
                          >Staff asking to add or fix a punch</span
                        >
                      </span>
                      <app-status-pill tone="warning">{{ n }}</app-status-pill>
                    </button>
                  </li>
                }
                @if (openLeave(); as n) {
                  <li>
                    <app-list-row
                      title="Leave requests"
                      subtitle="Waiting for a decision"
                      icon="event_available"
                      link="leave"
                    >
                      <app-status-pill tone="warning">{{ n }}</app-status-pill>
                    </app-list-row>
                  </li>
                }
              </ul>
              <h2 class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle">
                Employees
              </h2>
            }
            <ul class="flex flex-col gap-0.5" aria-label="Employees">
              @if (view() === 'today') {
                @for (r of todayRows(); track r.staffId) {
                  <li>
                    <app-list-row
                      [title]="r.staffName"
                      [subtitle]="todaySub(r)"
                      [initials]="initialsOf(r.staffName)"
                      [selected]="r.staffId === staffParam()"
                      [queryParams]="{ staff: r.staffId, day: today(), review: null, id: null }"
                      queryParamsHandling="merge"
                    >
                      <app-status-pill [tone]="r.label.tone">{{ r.label.label }}</app-status-pill>
                      @if (r.pending) {
                        <app-status-pill tone="warning">Review</app-status-pill>
                      }
                    </app-list-row>
                  </li>
                } @empty {
                  <li class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                    No employees yet. Add staff on Team; they clock in on the floor app.
                  </li>
                }
              } @else {
                @for (r of monthRows(); track r.staffId) {
                  <li>
                    <app-list-row
                      [title]="r.staffName"
                      [subtitle]="monthSub(r)"
                      [initials]="initialsOf(r.staffName)"
                      [selected]="r.staffId === staffParam()"
                      [queryParams]="{ staff: r.staffId, day: null, review: null, id: null }"
                      queryParamsHandling="merge"
                    >
                      <span class="text-sm font-semibold tabular-nums">{{
                        hours(r.totals.workedMin)
                      }}</span>
                    </app-list-row>
                  </li>
                } @empty {
                  <li class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                    No employees yet. Add staff on Team; they clock in on the floor app.
                  </li>
                }
              }
            </ul>
          }
        </div>
      </ng-container>
      <ng-container detail>
        @switch (detail()) {
          @case ('entry') {
            @if (entry(); as e) {
              <app-entry-detail
                [row]="e"
                [canReview]="canAttendance()"
                [ownRecord]="isOwn(e.entry.staffId)"
                [now]="now()"
                [locationChecked]="locationChecked()"
                [currentFence]="rules.rules()?.geofence ?? null"
                (closed)="close()"
              />
            }
          }
          @case ('day') {
            @if (picked(); as r) {
              <app-day-detail
                [row]="r"
                [canAttendance]="canAttendance()"
                [canLeave]="canLeave()"
                [ownRecord]="isOwn(r.staffId)"
                [locationChecked]="locationChecked()"
                (mark)="mark($event, r)"
                (closed)="close()"
              />
            }
          }
          @case ('person') {
            @if (person(); as p) {
              <app-detail-pane
                [crumb]="'Staff / Attendance / ' + p.staffName"
                [heading]="p.staffName"
                [subtitle]="monthTitle()"
                [initials]="initialsOf(p.staffName)"
                (closed)="close()"
              >
                <app-person-month
                  [days]="days()"
                  [cells]="p.cells"
                  [name]="p.staffName"
                  [monthName]="monthTitle()"
                  [today]="today()"
                  (pick)="setParams({ day: $event })"
                />
              </app-detail-pane>
            }
          }
          @case ('review') {
            <app-detail-pane
              crumb="Staff / Attendance / Needs review"
              icon="error"
              heading="Needs review"
              [subtitle]="reviewSubtitle()"
              (closed)="close()"
            >
              @if (pending().length) {
                <ul class="-mx-3 flex flex-col gap-0.5" aria-label="Entries needing review">
                  @for (r of pending(); track r.entry.id) {
                    <li><app-entry-row [row]="r" [now]="now()" [selected]="false" /></li>
                  }
                </ul>
              } @else {
                <p class="text-sm text-muted">Nothing waiting. Everything has been reviewed.</p>
              }
            </app-detail-pane>
          }
          @case ('month') {
            <app-month-grid
              [rows]="monthRows()"
              [days]="days()"
              [today]="today()"
              [monthName]="monthTitle()"
              (closed)="close()"
            />
          }
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class AttendanceHomePage {
  protected readonly attendance = inject(AttendanceStore);
  protected readonly calendar = inject(CalendarStore);
  protected readonly rules = inject(AttendanceRulesStore);
  private readonly layout = inject(Layout);
  private readonly leave = inject(LeaveStore);
  private readonly requests = inject(AttendanceRequestsStore);
  private readonly shifts = inject(ShiftsStore);
  private readonly arena = inject(ArenaContext);
  private readonly session = inject(Session);
  private readonly clock = inject(Clock);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly document = inject(DOCUMENT);

  /** `?view=calendar` (default: today). */
  readonly viewParam = input<string>(undefined, { alias: 'view' });
  /** `?month=2026-10` (Calendar; default this IST month). */
  readonly monthParam = input<string>(undefined, { alias: 'month' });
  /** `?staff=` and `?day=`: the person (and day) open. */
  readonly staffParam = input<string>(undefined, { alias: 'staff' });
  readonly dayParam = input<string>(undefined, { alias: 'day' });
  /** `?review=1`: the entries waiting for review. */
  readonly reviewParam = input<string>(undefined, { alias: 'review' });
  /** `?id=`: one entry with its evidence. */
  readonly id = input<string>();

  protected readonly shiftMonth = shiftMonth;
  protected readonly initialsOf = initials;
  protected readonly now = injectNow(30_000);
  protected readonly today = computed(() => formatIsoDate(this.now()));
  protected readonly view = computed(() =>
    this.viewParam() === 'calendar' ? 'calendar' : 'today',
  );
  protected readonly month = computed(() => {
    const m = this.monthParam();
    return m && monthDays(m) ? m : this.today().slice(0, 7);
  });
  protected readonly days = computed(() => monthDays(this.month()) ?? []);
  protected readonly monthTitle = computed(() => monthLabel(this.month()));

  protected readonly canAttendance = computed(() => this.arena.hasPerm(ATTENDANCE_PERM));
  protected readonly canLeave = computed(() => this.arena.hasPerm('leave_approve'));
  /** Off when punches are accepted wherever they happen (outside rule "allow"). */
  protected readonly locationChecked = computed(
    () => (this.rules.rules()?.outsideRule ?? 'flag') !== 'allow',
  );

  /** The days the screen reads: today (and the week before, for review), or the month. */
  private readonly period = computed(() => {
    if (this.view() === 'calendar') {
      const d = this.days();
      return { first: d[0], last: d[d.length - 1] };
    }
    return { first: addDays(this.today(), -(REVIEW_DAYS - 1)), last: this.today() };
  });
  protected readonly todayRows = computed(() =>
    dayRows(this.calendar.days() ?? [], this.attendance.rows(), this.today(), this.today()),
  );
  protected readonly monthRows = computed(() =>
    calendarRows(this.calendar.days() ?? [], this.days()),
  );
  protected readonly picked = computed<DayRow | undefined>(() => {
    const staff = this.staffParam();
    const day = this.dayParam();
    if (!staff || !day) return undefined;
    return dayRows(this.calendar.days() ?? [], this.attendance.rows(), day, this.today()).find(
      (r) => r.staffId === staff,
    );
  });
  protected readonly person = computed(() =>
    this.monthRows().find((r) => r.staffId === this.staffParam()),
  );
  protected readonly entry = computed<LogRow | undefined>(() => {
    const id = this.id();
    return id ? this.attendance.byId().get(id) : undefined;
  });
  protected readonly reviewOpen = computed(() => this.reviewParam() === '1');
  /** What the detail pane shows; everyone's month by default on a wide Calendar. */
  protected readonly detail = computed(() => {
    if (this.entry()) return 'entry';
    if (this.picked()) return 'day';
    if (this.reviewOpen()) return 'review';
    if (this.view() === 'calendar' && this.person()) return 'person';
    if (this.view() === 'calendar' && this.layout.wideDetail() && this.calendar.days()) {
      return 'month';
    }
    return null;
  });
  protected readonly detailLabel = computed(() => {
    switch (this.detail()) {
      case 'entry':
        return 'Attendance entry';
      case 'review':
        return 'Needs review';
      case 'person':
      case 'month':
        return 'Month';
      default:
        return 'Day';
    }
  });
  /** Entries in the loaded days still waiting for a reviewer, oldest first. */
  protected readonly pending = computed(() =>
    this.attendance
      .rows()
      .filter((r) => r.entry.review === 'pending' && r.entry.status === 'active')
      .reverse(),
  );
  protected readonly pendingText = computed(() => {
    const n = this.pending().length;
    return `${n} ${n === 1 ? 'entry' : 'entries'} ${this.reviewSubtitle().toLowerCase()}`;
  });
  protected readonly reviewSubtitle = computed(() =>
    this.view() === 'calendar' ? `In ${this.monthTitle()}` : `In the last ${REVIEW_DAYS} days`,
  );
  protected readonly openLeave = computed(() => (this.canLeave() ? this.leave.openCount() : 0));
  protected readonly openRequests = computed(() =>
    this.canAttendance() ? this.requests.pending().length : 0,
  );
  /** The loaded entries inside the period shown (for the export). */
  protected readonly periodRows = computed(() => {
    const first = this.view() === 'calendar' ? this.period().first : this.today();
    const last = this.period().last;
    return this.attendance
      .rows()
      .filter((r) => r.entry.workDate >= first && r.entry.workDate <= last);
  });
  protected readonly summary = computed(() => {
    if (this.view() === 'calendar') {
      const n = this.monthRows().length;
      return `${n} ${n === 1 ? 'employee' : 'employees'}`;
    }
    const c = dayCounts(this.todayRows());
    const parts = [
      cellDate(this.today()),
      c.working ? `${c.working} working` : '',
      c.completed ? `${c.completed} done` : '',
      c.not_in ? `${c.not_in} not in yet` : '',
      c.absent ? `${c.absent} absent` : '',
      c.on_leave ? `${c.on_leave} on leave` : '',
    ].filter(Boolean);
    return parts.join(' · ');
  });

  constructor() {
    effect(() => {
      const p = this.period();
      if (!this.arena.current().id || !p.first) return;
      void this.calendar.load(this.view() === 'calendar' ? p.first : this.today(), p.last);
      void this.attendance.load({ first: p.first, last: p.last });
    });
    effect(() => {
      if (!this.arena.current().id) return;
      void this.rules.load();
      void this.shifts.load();
      if (this.canLeave()) void this.leave.load();
      if (this.canAttendance()) void this.requests.load();
    });
    // The permission taken away live (or another arena picked without it): leave.
    effect(() => {
      if (this.arena.loaded() && this.arena.current().id && !this.arena.hasPerm(ATTENDANCE_PERM)) {
        void this.router.navigateByUrl('/overview');
      }
    });
  }

  protected setParams(params: Record<string, string | number | null>): void {
    void this.router.navigate([], { queryParams: params, queryParamsHandling: 'merge' });
  }

  protected pickView(view: 'today' | 'calendar'): void {
    this.setParams({
      view: view === 'calendar' ? 'calendar' : null,
      month: null,
      staff: null,
      day: null,
      id: null,
      review: null,
    });
  }

  /** Back one level: an entry to its day, a Calendar day to the person's month, else the list. */
  protected close(): void {
    if (this.id()) this.setParams({ id: null });
    else if (this.view() === 'calendar' && this.dayParam() && this.staffParam()) {
      this.setParams({ day: null });
    } else this.setParams({ staff: null, day: null, review: null });
  }

  protected refresh(): void {
    void this.calendar.refresh();
    void this.attendance.refresh();
    if (this.canLeave()) void this.leave.refresh();
    if (this.canAttendance()) void this.requests.load();
  }

  protected openRequestsDialog(): void {
    this.dialog
      .open<RequestsDialog, void, boolean>(RequestsDialog, {
        width: '560px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(() => void this.attendance.refresh());
  }

  protected hours(min: number): string {
    return min > 0 ? formatMinutes(min) : '—';
  }

  /** "In 10:02 am · Out 6:05 pm · 8h 3m", or the status note when they have not clocked in. */
  protected todaySub(r: DayRow): string {
    if (!r.firstIn) return r.label.note ?? 'No clock-in';
    const out = r.day.open ? 'working' : r.lastOut ? formatTime(r.lastOut) : '—';
    const h = r.day.workedMin > 0 ? ` · ${formatMinutes(r.day.workedMin)}` : '';
    return `In ${formatTime(r.firstIn)} · Out ${out}${h}`;
  }

  /** "20 present · 1 absent · 2 leave". */
  protected monthSub(r: CalendarRow): string {
    const t = r.totals;
    return [
      `${units(t.present)} present`,
      t.absent ? `${units(t.absent)} absent` : '',
      t.leave ? `${units(t.leave)} leave` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  }

  /** The entry belongs to the login and they are not the owner (own-record rule). */
  protected isOwn(staffId: string): boolean {
    return isOwnRecord(
      staffId,
      this.attendance.staff(),
      this.session.user()?.id,
      this.arena.currentRole(),
    );
  }

  /** Employees the login may mark: tracked (listed here), active, never themselves. */
  private markable(): StaffMember[] {
    const tracked = new Set((this.calendar.days() ?? []).map((d) => d.staffId));
    return this.attendance
      .staff()
      .filter((s) => s.active && tracked.has(s.id) && !this.isOwn(s.id));
  }

  protected mark(kind?: MarkKind, row?: DayRow): void {
    const data: MarkDialogData = {
      staff: this.markable(),
      staffId: row?.staffId ?? this.staffParam() ?? null,
      day: row?.day.workDate ?? (this.view() === 'today' ? this.today() : null),
      kind,
      canAttendance: this.canAttendance(),
      canLeave: this.canLeave(),
    };
    this.dialog
      .open<MarkDialog, MarkDialogData, MarkDialogResult>(MarkDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        // The day's status and hours come from the server: read them again.
        void this.calendar.refresh();
      });
  }

  protected exportCsv(): void {
    const rows = this.periodRows();
    const first = this.view() === 'calendar' ? this.period().first : this.today();
    const last = this.period().last;
    const user = this.session.user();
    const csv = attendanceCsv(rows, {
      arena: this.arena.current().name,
      first,
      last,
      generatedAt: this.clock.now(),
      generatedBy: user ? `${user.name} <${user.email}>` : null,
      filters: null,
    });
    const slug = this.arena
      .current()
      .name.toLowerCase()
      .replace(/[^a-z0-9]+/g, '-');
    try {
      // A byte-order mark so spreadsheet apps read names as UTF-8.
      const url = URL.createObjectURL(new Blob(['﻿', csv], { type: 'text/csv' }));
      const a = this.document.createElement('a');
      a.href = url;
      a.download = `${slug || 'arena'}-attendance-${first === last ? first : `${first}_to_${last}`}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url));
    } catch {
      // Download blocked (e.g. a sandboxed preview): the snackbar still reports the count.
    }
    this.snack.open(`${rows.length} entr${rows.length === 1 ? 'y' : 'ies'} exported`, undefined, {
      duration: 3200,
    });
  }
}
