import { Component, computed, inject, output, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { RouterLink } from '@angular/router';
import { isOwnerLevel } from '../../../core/arena/arena-api';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { Session } from '../../../core/auth/session';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { ToggleRow } from '../../../shared/list-detail/toggle-row';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { PaySetupStore } from '../../pay-setup/data/pay-setup-store';
import { resolvedProfile, toHrDraft } from '../../pay-setup/data/pay-setup.models';
import { InviteList } from '../../users/components/invite-list';
import { initials } from '../../users/components/user-format';
import { UsersStore } from '../../users/data/users-store';
import { ArenaUser } from '../../users/data/user.models';
import { UserDialog, UserDialogData, UserDialogResult } from '../../users/dialogs/user-dialog';

/**
 * Settings › Owners & access: who owns the venue (every permission, managed on this dashboard)
 * and their open invitations. Only an owner invites another owner (invite_member refuses
 * anyone else). Owners are not employees: they have no attendance, leave or pay unless "Works
 * here as staff" is on (their HR profile tracks attendance; needs Payroll), which adds them to
 * Team. Staff permissions, admin access included, are on each employee's Access tab on Team.
 */
@Component({
  selector: 'app-owners-access',
  imports: [
    DetailPane,
    DetailSection,
    ToggleRow,
    StatusPill,
    InviteList,
    MatButton,
    MatIcon,
    RouterLink,
  ],
  template: `
    <app-detail-pane
      crumb="Settings / Owners & access"
      icon="admin_panel_settings"
      heading="Owners & access"
      subtitle="Owners manage the venue. Employees are on Team."
      (closed)="closed.emit()"
    >
      @if (isOwner()) {
        <div actions class="arena-compact">
          <button mat-stroked-button type="button" (click)="invite()">
            <mat-icon aria-hidden="true">person_add</mat-icon>Invite an owner
          </button>
        </div>
      }

      <app-detail-section
        heading="Owners"
        subtitle="Every permission, on this dashboard and the floor app. Removing an owner is done by the operator."
      >
        @if (users.loadError(); as error) {
          <p role="alert" class="text-sm text-danger">{{ error }}</p>
        }
        @for (o of users.owners(); track o.userId) {
          <div class="flex flex-col gap-3 border-b border-border pb-4 last:border-b-0 last:pb-0">
            <div class="flex items-center gap-3">
              <span
                class="grid size-10 flex-none place-items-center rounded-full bg-primary-soft text-[13px] font-semibold text-primary-text"
                aria-hidden="true"
                >{{ initialsOf(o.name) }}</span
              >
              <span class="flex min-w-0 flex-1 flex-col gap-1">
                <span class="truncate text-sm font-semibold">{{ o.name }}</span>
                <span class="truncate text-[12.5px] text-muted">{{ o.email }}</span>
              </span>
              @if (o.userId === me()) {
                <app-status-pill tone="primary">You</app-status-pill>
              } @else if (o.invited) {
                <app-status-pill tone="warning">Not signed in yet</app-status-pill>
              }
            </div>
            @if (canPay()) {
              <app-toggle-row
                label="Works here as staff"
                sub="Adds them to Team: attendance, leave and pay like any employee."
                [checked]="works(o)"
                [disabled]="!profileOf(o) || savingWorks()"
                (changed)="setWorks(o, $event)"
              />
            }
          </div>
        }
      </app-detail-section>

      @if (showInvites()) {
        <app-invite-list role="owner" heading="Owner invitations" />
      }

      <app-detail-section heading="Staff access">
        <p class="text-[13px] leading-[1.45] text-muted">
          Staff sign in on the floor app with the permissions you give them. Change what someone
          can do, admin access included, on Team › their Access tab. Staff permissions never make
          someone an owner.
        </p>
        <a class="text-sm font-medium text-primary-text" routerLink="/staff/team">Open Team</a>
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class OwnersAccess {
  protected readonly users = inject(UsersStore);
  private readonly pay = inject(PaySetupStore);
  private readonly arena = inject(ArenaContext);
  private readonly session = inject(Session);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);
  protected readonly savingWorks = signal(false);

  readonly closed = output<void>();

  protected readonly initialsOf = initials;
  protected readonly me = computed(() => this.session.user()?.id);
  protected readonly isOwner = computed(() => this.arena.currentRole() === 'owner');
  protected readonly canPay = computed(() => this.arena.hasPerm('payroll'));
  protected readonly showInvites = computed(() => {
    const m = this.arena.currentMembership();
    return (
      !!m &&
      isOwnerLevel(m) &&
      (this.users.invites().some((i) => i.role === 'owner') || !!this.users.invitesError())
    );
  });

  constructor() {
    void this.users.load();
    void this.pay.load();
  }

  protected profileOf(o: ArenaUser) {
    return this.pay.staff().find((s) => s.userId === o.userId);
  }

  protected works(o: ArenaUser): boolean {
    const s = this.profileOf(o);
    return !!s && resolvedProfile(s, this.pay.profileOf().get(s.id)).tracksAttendance;
  }

  /** hr_profile.save with tracks_attendance: the explicit "this owner is also an employee". */
  protected async setWorks(o: ArenaUser, event: MatSlideToggleChange): Promise<void> {
    const s = this.profileOf(o);
    if (!s || this.savingWorks()) return;
    const draft = toHrDraft(resolvedProfile(s, this.pay.profileOf().get(s.id)));
    this.savingWorks.set(true);
    try {
      await this.pay.saveProfile(s.id, { ...draft, tracksAttendance: event.checked });
      this.snack.open(
        event.checked ? `${o.name} now appears on Team` : `${o.name} no longer appears on Team`,
        undefined,
        { duration: 3200 },
      );
    } catch (e) {
      event.source.checked = !event.checked;
      this.snack.open(toAppError(e).message, undefined, { duration: 3200 });
    } finally {
      this.savingWorks.set(false);
    }
  }

  protected invite(): void {
    this.dialog
      .open<UserDialog, UserDialogData, UserDialogResult>(UserDialog, {
        data: { role: 'owner', canAddOwners: true },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        void this.users.load(true);
      });
  }
}
