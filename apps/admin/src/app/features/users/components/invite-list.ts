import { Component, computed, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatSnackBar } from '@angular/material/snack-bar';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { ConfirmDialog, ConfirmDialogData } from '../../../shared/confirm/confirm-dialog';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatDate } from '../../../shared/time/ist';
import { UsersStore } from '../data/users-store';
import { PendingInvite } from '../data/user.models';

/**
 * The arena's open invitations under the people lists: who was invited, as what, by whom, and
 * until when the link works. Withdrawing (after confirming) stops the link working.
 */
@Component({
  selector: 'app-invite-list',
  imports: [MatButton, StatusPill],
  template: `
    <section aria-labelledby="users-invites">
      <h2 id="users-invites" class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle">
        {{ heading() }} · {{ invites().length }}
      </h2>
      @if (store.invitesError(); as error) {
        <p role="alert" class="px-3 py-2 text-sm text-danger">{{ error }}</p>
      }
      <ul class="flex flex-col gap-0.5">
        @for (i of invites(); track i.inviteId) {
          <li class="flex min-h-16 items-center gap-3 rounded-card px-3 py-2.5">
            <span
              class="icon grid size-10 flex-none place-items-center rounded-full bg-info-soft text-[20px] leading-none text-muted"
              aria-hidden="true"
              >mail</span
            >
            <span class="flex min-w-0 flex-1 flex-col gap-1">
              <span class="truncate text-sm leading-[1.25] font-semibold">{{ i.email }}</span>
              <span class="truncate text-[12.5px] leading-[1.3] text-muted">{{ details(i) }}</span>
              <span>
                <app-status-pill [tone]="i.expired ? 'danger' : 'warning'">{{
                  i.expired ? 'Expired' : 'Expires ' + date(i.expiresAt)
                }}</app-status-pill>
              </span>
            </span>
            <span class="arena-compact flex-none">
              <button
                mat-button
                type="button"
                class="danger-action"
                [disabled]="store.saving() === i.inviteId || !canEdit()"
                [attr.aria-label]="'Withdraw the invitation to ' + i.email"
                (click)="withdraw(i)"
              >
                Withdraw
              </button>
            </span>
          </li>
        }
      </ul>
    </section>
  `,
})
export class InviteList {
  /** Without the Settings permission the server refuses every change here. */
  protected readonly canEdit = inject(ArenaContext).canEdit;
  protected readonly store = inject(UsersStore);

  /** Only this role's invitations (Team lists staff, Settings › Owners & access owners). */
  readonly role = input<'owner' | 'staff' | null>(null);
  readonly heading = input('Pending invitations');
  protected readonly invites = computed(() =>
    this.store.invites().filter((i) => !this.role() || i.role === this.role()),
  );
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  protected readonly date = formatDate;

  protected details(i: PendingInvite): string {
    return [
      i.name,
      i.role === 'owner' ? 'Owner' : 'Staff',
      i.invitedByName ? `invited by ${i.invitedByName}` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  }

  protected withdraw(invite: PendingInvite): void {
    this.dialog
      .open<ConfirmDialog, ConfirmDialogData, boolean>(ConfirmDialog, {
        data: {
          title: `Withdraw the invitation to ${invite.email}?`,
          message:
            'The link in their e-mail stops working and they do not join. You can invite them again later.',
          confirm: 'Withdraw',
          danger: true,
        },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe(async (yes) => {
        if (!yes) return;
        try {
          await this.store.revoke(invite);
          this.say(`Invitation to ${invite.email} withdrawn`);
        } catch (e) {
          this.say(toAppError(e).message);
        }
      });
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
