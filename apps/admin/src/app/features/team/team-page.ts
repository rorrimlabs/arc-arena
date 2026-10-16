import { Component, computed, effect, inject } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { isOwnerLevel } from '../../core/arena/arena-api';
import { ArenaContext } from '../../core/arena/arena-context';
import { Clock } from '../../core/time/clock';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { childParams } from '../../shared/routing/child-params';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { formatIsoDate } from '../../shared/time/ist';
import { LeaveStore } from '../leave/data/leave-store';
import { PaySetupStore } from '../pay-setup/data/pay-setup-store';
import { PayStaff, rateOn } from '../pay-setup/data/pay-setup.models';
import { ShiftsStore } from '../shifts/data/shifts-store';
import { coversDay } from '../shifts/data/shifts.models';
import { InviteList } from '../users/components/invite-list';
import { initials } from '../users/components/user-format';
import { UsersStore } from '../users/data/users-store';
import { UserDialog, UserDialogData, UserDialogResult } from '../users/dialogs/user-dialog';
import { MemberDetail } from './components/member-detail';
import { isEmployee } from './data/team.models';

/**
 * Staff › Team: the venue's employees (staff, and an owner only when they are set to work here)
 * with their role, status and shift, and Add staff (an e-mailed staff invitation; never owner
 * access, which is Settings › Owners & access). Pending staff invitations follow the list. An
 * employee opens with everything about them in one place, in routable tabs. The selection is in
 * the URL path (`/staff/team/<staff>/leave`).
 */
@Component({
  selector: 'app-team-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    StatusPill,
    InviteList,
    MemberDetail,
    MatButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail
      listLabel="Team"
      detailLabel="Employee"
      emptyText="Pick someone to see their attendance, leave, salary and schedule"
      [open]="!!selected()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Team">
          <button
            actions
            mat-flat-button
            type="button"
            [disabled]="!arena.canEdit()"
            (click)="add()"
          >
            <mat-icon aria-hidden="true">person_add</mat-icon>Add staff
          </button>
          @if (summary()) {
            <p class="text-[13px] leading-[1.3] text-muted" aria-live="polite">{{ summary() }}</p>
          }
        </app-list-pane-header>
        @if (pay.loading() || shifts.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading the team" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (pay.loadError() || shifts.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="reload()">Try again</button>
            </div>
          } @else if (pay.data()) {
            <ul class="flex flex-col gap-0.5" aria-label="Employees">
              @for (s of people(); track s.id) {
                <li>
                  <app-list-row
                    [title]="s.name"
                    [subtitle]="rowSub(s)"
                    [initials]="initialsOf(s.name)"
                    [selected]="s.id === selected()?.id"
                    [link]="['/staff/team', s.id]"
                  >
                    @if (!s.active) {
                      <app-status-pill tone="danger">Access off</app-status-pill>
                    } @else if (users.byId().get(s.userId)?.invited) {
                      <app-status-pill tone="warning">Invited</app-status-pill>
                    }
                  </app-list-row>
                </li>
              } @empty {
                <li class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">
                  No staff yet. Add the people who work at the venue: they get an e-mail to join
                  and clock in on the floor app.
                </li>
              }
            </ul>
            @if (showInvites()) {
              <app-invite-list role="staff" heading="Invited, not joined yet" />
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as s) {
          <app-member-detail
            [staff]="s"
            [user]="users.byId().get(s.userId)"
            [tab]="params()['tab']"
            (closed)="close()"
          />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class TeamPage {
  protected readonly pay = inject(PaySetupStore);
  protected readonly shifts = inject(ShiftsStore);
  protected readonly users = inject(UsersStore);
  protected readonly arena = inject(ArenaContext);
  private readonly leave = inject(LeaveStore);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  private readonly today = formatIsoDate(inject(Clock).now());

  /** `/staff/team/:id[/:tab]` — a staff profile id and the employee section open. */
  protected readonly params = childParams();

  protected readonly initialsOf = initials;
  private readonly canPay = computed(() => this.arena.hasPerm('payroll'));
  /** Employees only, active first, each group by name. */
  protected readonly people = computed(() =>
    this.pay
      .staff()
      .filter((s) => isEmployee(s, this.pay.profileOf().get(s.id)))
      .sort((a, b) => Number(b.active) - Number(a.active) || a.name.localeCompare(b.name)),
  );
  protected readonly selected = computed(() => {
    const id = this.params()['id'];
    return id ? this.people().find((s) => s.id === id) : undefined;
  });
  /** Staff invitations still open, for owner-level logins (arena_invites). */
  protected readonly showInvites = computed(() => {
    const me = this.arena.currentMembership();
    return (
      !!me &&
      isOwnerLevel(me) &&
      (this.users.invites().some((i) => i.role === 'staff') || !!this.users.invitesError())
    );
  });
  protected readonly summary = computed(() => {
    const active = this.people().filter((s) => s.active);
    if (!active.length) return '';
    const noShift = active.filter((s) => !this.shiftNow(s.id)).length;
    const noPay = this.canPay() ? active.filter((s) => !this.rateNow(s.id)).length : 0;
    return [
      `${active.length} ${active.length === 1 ? 'employee' : 'employees'}`,
      noShift ? `${noShift} without a shift` : '',
      noPay ? `${noPay} without a salary` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  });

  constructor() {
    effect(() => {
      if (!this.arena.current().id) return;
      void this.pay.load();
      void this.shifts.load();
      void this.users.load();
      if (this.arena.hasPerm('leave_approve')) void this.leave.load();
    });
  }

  private shiftNow(staffId: string) {
    const a = this.shifts
      .assignments()
      .find((x) => x.staffId === staffId && coversDay(x, this.today));
    return a ? this.shifts.shifts().find((s) => s.id === a.shiftId) : undefined;
  }

  private rateNow(staffId: string) {
    return rateOn(
      (this.pay.data()?.rates ?? []).filter((r) => r.staffId === staffId),
      this.today,
    );
  }

  /** "Staff · Morning shift", "Owner · No shift". */
  protected rowSub(s: PayStaff): string {
    const perms = this.users.byId().get(s.userId)?.perms ?? [];
    const role =
      s.role === 'owner'
        ? 'Owner'
        : perms.includes('money') || perms.includes('reports')
          ? 'Staff · admin'
          : 'Staff';
    const shift = this.shiftNow(s.id);
    return `${role} · ${shift ? shift.name : 'No shift'}`;
  }

  protected reload(): void {
    void this.pay.load(true);
    void this.shifts.load(true);
  }

  /** Add staff: an e-mailed staff invitation (the staff role only, the default permissions). */
  protected add(): void {
    this.dialog
      .open<UserDialog, UserDialogData, UserDialogResult>(UserDialog, {
        data: { role: 'staff' },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        // They join once they accept the e-mailed invitation; then they appear here.
        void this.users.load(true);
      });
  }

  protected close(): void {
    void this.router.navigate(['/staff/team']);
  }
}
