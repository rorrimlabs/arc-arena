import { Component, computed, inject, input, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSnackBar } from '@angular/material/snack-bar';
import { RouterLink } from '@angular/router';
import { isOwnerLevel } from '../../../core/arena/arena-api';
import { ArenaContext } from '../../../core/arena/arena-context';
import { Session } from '../../../core/auth/session';
import { Clock } from '../../../core/time/clock';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { DetailTab, DetailTabs } from '../../../shared/list-detail/detail-tabs';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import {
  formatCount,
  formatDayYear,
  formatDays,
  formatRange,
} from '../../../shared/staff/staff-format';
import { formatIsoDate } from '../../../shared/time/ist';
import { MarkDialog, MarkDialogData, MarkDialogResult } from '../../attendance/dialogs/mark-dialog';
import { LeaveStore } from '../../leave/data/leave-store';
import { LeaveBalance, LeaveRequest, datesLabel, splitLabel, statusLabel } from '../../leave/data/leave.models';
import { AdjustDialogData, LeaveAdjustDialog } from '../../leave/dialogs/adjust-dialog';
import { StaffPayDetail } from '../../pay-setup/components/staff-pay-detail';
import { PaySetupStore } from '../../pay-setup/data/pay-setup-store';
import { PayStaff, rateOn, resolvedProfile } from '../../pay-setup/data/pay-setup.models';
import { rateShort } from '../../pay-setup/dialogs/pay-rate-dialog';
import { ShiftsStore } from '../../shifts/data/shifts-store';
import {
  ShiftAssignment,
  assignmentDates,
  coversDay,
  daysLabel,
  shiftTimes,
} from '../../shifts/data/shifts.models';
import {
  AssignDialog,
  AssignDialogData,
  AssignDialogResult,
} from '../../shifts/dialogs/assign-dialog';
import { ShiftDialog, ShiftDialogData, ShiftDialogResult } from '../../shifts/dialogs/shift-dialog';
import { UserAccess } from '../../users/components/user-access';
import { initials } from '../../users/components/user-format';
import { ArenaUser } from '../../users/data/user.models';
import { UserDialog, UserDialogData, UserDialogResult } from '../../users/dialogs/user-dialog';
import { exemptFromTerms } from '../../settings/data/staff-terms';
import { EmployeeAttendance } from './employee-attendance';
import { MemberProfile } from './member-profile';

export type MemberTab =
  | 'overview'
  | 'profile'
  | 'attendance'
  | 'leave'
  | 'salary'
  | 'schedule'
  | 'access';

/**
 * One employee on Team, the one place for everything about them: Overview (contact, role,
 * status, joining date, shift, salary, and the employment details), Profile (personal details
 * and the staff terms they accepted; owner level), Attendance (their month),
 * Leave (balance, history, record, adjust), Salary (pay rate and its history), Schedule (their
 * shifts with effective dates; a day without a shift is a day off) and Access (app
 * permissions). Each tab shows only to logins with its permission: attendance needs Review
 * attendance or Payroll, leave Approve leave, salary Payroll; shifts change with Settings.
 * Owners' access is not managed here (Settings › Owners & access). The tabs are routable: the
 * tab is in the URL path (`/staff/team/<staff>/leave`; Overview is `/staff/team/<staff>`).
 */
@Component({
  selector: 'app-member-detail',
  imports: [
    DetailPane,
    DetailSection,
    DetailRow,
    StatusPill,
    StaffPayDetail,
    UserAccess,
    EmployeeAttendance,
    MemberProfile,
    MatButton,
    DetailTabs,
    MatIcon,
    RouterLink,
  ],
  template: `
    @let s = staff();
    <app-detail-pane
      [crumb]="'Staff / Team / ' + s.name"
      [heading]="s.name"
      [subtitle]="user()?.email ?? ''"
      [initials]="initialsOf(s.name)"
      (closed)="closed.emit()"
    >
      <app-status-pill chip [tone]="status().tone">{{ status().label }}</app-status-pill>
      <app-detail-tabs label="Employee sections" [tabs]="tabLinks()" [active]="current()">

      @switch (current()) {
        @case ('overview') {
          <app-detail-section>
            <app-detail-row label="E-mail" [value]="user()?.email ?? '—'" [muted]="!user()" />
            <app-detail-row label="Role" [value]="roleText()" />
            <app-detail-row label="Status" [value]="status().label" />
            @if (canPay()) {
              <app-detail-row label="Joined" [value]="joined()" [muted]="!profile().joinedOn" />
            }
            <app-detail-row label="Shift" [value]="shiftNow()" [muted]="shiftNow() === 'None'" />
            @if (canPay()) {
              <app-detail-row
                label="Salary"
                [value]="rate() ? rateText(rate()!) : 'Not set'"
                [muted]="!rate()"
              />
            }
            @if (user(); as u) {
              <div>
                <button
                  mat-stroked-button
                  type="button"
                  [disabled]="!canEdit()"
                  (click)="editName(u)"
                >
                  <mat-icon aria-hidden="true">edit</mat-icon>Edit name
                </button>
              </div>
            }
          </app-detail-section>
          @if (canPay()) {
            <app-staff-pay-detail [staff]="s" part="profile" />
          }
        }
        @case ('profile') {
          <app-member-profile [staff]="s" [exempt]="termsExempt()" />
        }
        @case ('attendance') {
          <app-employee-attendance [staffId]="s.id" [name]="s.name" />
        }
        @case ('leave') {
          <app-detail-section heading="Paid leave">
            @if (ownRecord()) {
              <p role="note" class="text-[13px] leading-[1.45] text-muted">
                This is your own leave: another approver (or the owner) records or adjusts it.
              </p>
            }
            @if (balance(); as b) {
              <app-detail-row
                label="Left this year"
                [value]="count(b.balance) + ' of ' + count(b.allowance + b.adjustments) + ' days'"
                [strong]="true"
              />
              <app-detail-row label="Used" [value]="days(b.used)" />
              <app-detail-row label="Leave year" [value]="range(b.yearStart, b.yearEnd)" />
            } @else {
              <p class="text-sm text-muted">No leave balance yet.</p>
            }
            @if (!ownRecord()) {
              <div class="flex flex-wrap gap-2">
                <button mat-stroked-button type="button" (click)="recordLeave()">
                  <mat-icon aria-hidden="true">event_available</mat-icon>Record leave
                </button>
                @if (balance(); as b) {
                  <button mat-button type="button" (click)="adjust(b)">Adjust balance</button>
                }
              </div>
            }
          </app-detail-section>
          <app-detail-section heading="History">
            <ul class="flex flex-col" aria-label="Leave history">
              @for (r of leaveHistory(); track r.id) {
                <li class="border-b border-border last:border-b-0">
                  <a
                    class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2.5 text-fg no-underline hover:text-fg"
                    routerLink="/staff/attendance/leave"
                    [queryParams]="{ tab: 'all', staff: s.id, id: r.id }"
                  >
                    <span class="min-w-0 flex-1 text-sm">
                      <span class="font-medium">{{ dates(r) }}</span>
                      <span class="block text-[12.5px] text-muted">{{ leaveSub(r) }}</span>
                    </span>
                    <app-status-pill [tone]="statusOf(r).tone">{{ statusOf(r).label }}</app-status-pill>
                  </a>
                </li>
              } @empty {
                <li class="text-sm text-muted">No leave yet.</li>
              }
            </ul>
          </app-detail-section>
        }
        @case ('salary') {
          <app-staff-pay-detail [staff]="s" part="pay" />
        }
        @case ('schedule') {
          <app-detail-section
            heading="Shifts"
            subtitle="Days without a shift are days off. Attendance and pay follow these dates."
          >
            @for (a of assignments(); track a.id) {
              @let sh = shiftOf(a);
              <div class="flex flex-wrap items-start gap-x-3 gap-y-1">
                <div class="flex min-w-0 flex-1 flex-col gap-1">
                  <span class="text-sm font-semibold">{{ sh?.name ?? 'Shift' }}</span>
                  <span class="text-[13px] leading-[1.4] text-muted"
                    >{{ sh ? times(sh) + ' · ' + weekdays(sh.days) : '' }} · {{ datesOf(a) }}</span
                  >
                </div>
                @if (canEdit()) {
                  <button
                    mat-button
                    type="button"
                    class="arena-compact"
                    (click)="changeDates(a)"
                  >
                    Change dates
                  </button>
                }
              </div>
            } @empty {
              <p class="text-sm leading-[1.4] text-muted">
                No shift: every day counts as a day off, so attendance never shows them absent.
              </p>
            }
            @if (canEdit()) {
              <div class="flex flex-wrap gap-2">
                @if (hasShifts()) {
                  <button mat-stroked-button type="button" (click)="assign()">
                    <mat-icon aria-hidden="true">schedule</mat-icon>Assign a shift
                  </button>
                } @else {
                  <button mat-stroked-button type="button" (click)="createShift()">
                    <mat-icon aria-hidden="true">add</mat-icon>Create your working hours
                  </button>
                }
              </div>
              <p class="text-[12.5px] leading-[1.4] text-muted">
                To end a shift, change its dates and set the last day. The venue's shifts and
                holidays are in Settings › Staff.
              </p>
            }
          </app-detail-section>
        }
        @case ('access') {
          @if (user(); as u) {
            <app-user-access [user]="u" />
          }
        }
      }
      </app-detail-tabs>
    </app-detail-pane>
  `,
})
export class MemberDetail {
  private readonly arena = inject(ArenaContext);
  private readonly session = inject(Session);
  private readonly pay = inject(PaySetupStore);
  private readonly shifts = inject(ShiftsStore);
  private readonly leave = inject(LeaveStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly today = formatIsoDate(inject(Clock).now());

  readonly staff = input.required<PayStaff>();
  /** Their login on Users (e-mail, invited or not, permissions), when readable. */
  readonly user = input<ArenaUser | undefined>(undefined);
  /** `/staff/team/<staff>/<tab>`: the section open (Overview when missing or not allowed). */
  readonly tab = input<string | undefined>(undefined);
  readonly closed = output<void>();

  protected readonly initialsOf = initials;
  protected readonly times = shiftTimes;
  protected readonly weekdays = daysLabel;
  protected readonly datesOf = assignmentDates;
  protected readonly range = formatRange;
  protected readonly count = formatCount;
  protected readonly days = formatDays;
  protected readonly dates = datesLabel;
  protected readonly rateText = rateShort;

  protected readonly canEdit = this.arena.canEdit;
  protected readonly canPay = computed(() => this.arena.hasPerm('payroll'));
  private readonly canLeave = computed(() => this.arena.hasPerm('leave_approve'));
  /** Personal details and terms acceptances are readable by owner level only. */
  private readonly ownerLevel = computed(() => {
    const m = this.arena.currentMembership();
    return !!m && isOwnerLevel(m);
  });
  /** Owner level (role owner, or money / reports) never accepts the staff terms. */
  protected readonly termsExempt = computed(() =>
    exemptFromTerms({ role: this.staff().role, perms: this.user()?.perms ?? [] }),
  );
  private readonly canSeeAttendance = computed(
    () => this.arena.hasPerm('attendance_review') || this.canPay(),
  );

  protected readonly tabs = computed(() =>
    [
      { key: 'overview' as const, label: 'Overview', show: true },
      { key: 'profile' as const, label: 'Profile', show: this.ownerLevel() },
      { key: 'attendance' as const, label: 'Attendance', show: this.canSeeAttendance() },
      { key: 'leave' as const, label: 'Leave', show: this.canLeave() },
      { key: 'salary' as const, label: 'Salary', show: this.canPay() },
      { key: 'schedule' as const, label: 'Schedule', show: true },
      // Owners' access is all permissions, managed in Settings › Owners & access.
      { key: 'access' as const, label: 'Access', show: !!this.user() && this.staff().role === 'staff' },
    ].filter((t) => t.show),
  );
  protected readonly tabLinks = computed<DetailTab[]>(() =>
    this.tabs().map((t) => ({
      ...t,
      link:
        t.key === 'overview'
          ? ['/staff/team', this.staff().id]
          : ['/staff/team', this.staff().id, t.key],
    })),
  );
  protected readonly current = computed<MemberTab>(
    () => this.tabs().find((t) => t.key === this.tab())?.key ?? 'overview',
  );

  protected readonly status = computed(() => {
    if (!this.staff().active) return { label: 'Access off', tone: 'danger' as const };
    if (this.user()?.invited) return { label: 'Invited', tone: 'warning' as const };
    return { label: 'Active', tone: 'success' as const };
  });
  /** Role, never permissions: owner who also works here, staff with admin access, or staff. */
  protected readonly roleText = computed(() => {
    if (this.staff().role === 'owner') return 'Owner, also works here';
    const perms = this.user()?.perms ?? [];
    return perms.includes('money') || perms.includes('reports') ? 'Staff · admin access' : 'Staff';
  });
  /** Their own record and not the owner: nobody approves or records their own leave. */
  protected readonly ownRecord = computed(
    () =>
      this.staff().userId === this.session.user()?.id && this.arena.currentRole() !== 'owner',
  );
  protected readonly profile = computed(() =>
    resolvedProfile(this.staff(), this.pay.profileOf().get(this.staff().id)),
  );
  protected readonly joined = computed(() => {
    const j = this.profile().joinedOn;
    return j ? formatDayYear(j) : 'Not set';
  });
  /** Their current and future shift assignments, earliest first. */
  protected readonly assignments = computed(() =>
    this.shifts
      .assignments()
      .filter(
        (a) =>
          a.staffId === this.staff().id && (a.effectiveTo === null || a.effectiveTo >= this.today),
      )
      .sort((a, b) => a.effectiveFrom.localeCompare(b.effectiveFrom)),
  );
  protected readonly shiftNow = computed(() => {
    const names = this.assignments()
      .filter((a) => coversDay(a, this.today))
      .map((a) => this.shiftOf(a)?.name)
      .filter(Boolean);
    return names.length ? names.join(', ') : 'None';
  });
  protected readonly hasShifts = computed(() => this.shifts.shifts().some((s) => s.active));
  protected readonly rate = computed(() =>
    rateOn(
      (this.pay.data()?.rates ?? []).filter((r) => r.staffId === this.staff().id),
      this.today,
    ),
  );
  protected readonly balance = computed(() => this.leave.balanceOf().get(this.staff().id));
  protected readonly leaveHistory = computed(() =>
    this.leave
      .requests()
      .filter((r) => r.staffId === this.staff().id)
      .sort((a, b) => b.fromDate.localeCompare(a.fromDate)),
  );

  protected shiftOf(a: ShiftAssignment) {
    return this.shifts.shifts().find((s) => s.id === a.shiftId);
  }

  protected statusOf(r: LeaveRequest) {
    return statusLabel(r.status);
  }

  protected leaveSub(r: LeaveRequest): string {
    return [formatDays(r.days), splitLabel(r)].filter(Boolean).join(' · ');
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }

  protected editName(u: ArenaUser): void {
    this.dialog
      .open<UserDialog, UserDialogData, UserDialogResult>(UserDialog, {
        data: { user: u },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => {
        if (!r) return;
        this.say(r.snack);
        void this.pay.load(true);
      });
  }

  protected assign(): void {
    this.dialog
      .open<AssignDialog, AssignDialogData, AssignDialogResult>(AssignDialog, {
        data: { staffId: this.staff().id },
        width: '480px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => r && this.say(r.snack));
  }

  protected changeDates(a: ShiftAssignment): void {
    const shift = this.shiftOf(a);
    if (!shift) return;
    this.dialog
      .open<AssignDialog, AssignDialogData, AssignDialogResult>(AssignDialog, {
        data: { shift, assignment: a },
        width: '480px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => r && this.say(r.snack));
  }

  /** No shifts yet: create the venue's standard shift, then assign this person to it. */
  protected createShift(): void {
    this.dialog
      .open<ShiftDialog, ShiftDialogData, ShiftDialogResult>(ShiftDialog, {
        data: {},
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => {
        if (!r) return;
        this.say(r.snack);
        this.assign();
      });
  }

  protected recordLeave(): void {
    if (this.ownRecord()) return;
    const s = this.staff();
    const data: MarkDialogData = {
      staff: [{ id: s.id, name: s.name, active: s.active, userId: s.userId }],
      staffId: s.id,
      kind: 'paid_leave',
      canAttendance: false,
      canLeave: true,
    };
    this.dialog
      .open<MarkDialog, MarkDialogData, MarkDialogResult>(MarkDialog, {
        data,
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((r) => r && this.say(r.snack));
  }

  protected adjust(b: LeaveBalance): void {
    const data: AdjustDialogData = { balance: b };
    this.dialog
      .open(LeaveAdjustDialog, { data, width: '440px', autoFocus: 'first-tabbable' })
      .afterClosed()
      .subscribe((done) => done && this.say('Balance adjusted'));
  }
}
