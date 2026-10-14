import { Component, computed, inject, signal } from '@angular/core';
import { FormField, form, hidden, validate } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatButtonToggle, MatButtonToggleGroup } from '@angular/material/button-toggle';
import {
  MAT_DIALOG_DATA,
  MatDialogActions,
  MatDialogContent,
  MatDialogRef,
  MatDialogTitle,
} from '@angular/material/dialog';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { toAppError } from '../../../core/auth/auth-api';
import { UsersStore } from '../data/users-store';
import { ArenaUser, DEFAULT_STAFF_PERMS, INVITE_DAYS, UserRole } from '../data/user.models';
import { MATERIAL_DEFAULTS } from '../../../shared/material/material-defaults';

export interface UserDialogData {
  /** Absent: invite someone new. Present: edit this user's name. */
  readonly user?: ArenaUser;
  /** The signed-in login may invite owners (it is an owner itself). */
  readonly canAddOwners?: boolean;
}

/** What the page shows in the snackbar after the dialog closes; undefined when cancelled. */
export interface UserDialogResult {
  /** The edited user; absent after an invitation (nobody joins until they accept). */
  readonly userId?: string;
  readonly snack: string;
}

const SUBTITLES: Readonly<Record<UserRole, string>> = {
  staff: `We e-mail them a link (it works for ${INVITE_DAYS} days). They choose their own password, then sign in on the staff app with this email. Set permissions once they have joined.`,
  owner: `We e-mail them a link (it works for ${INVITE_DAYS} days). They choose their own password, then manage the arena here with every permission.`,
};

/**
 * Design dialog `d.k === 'staff'`, extended to owners. Inviting e-mails a one-time link (the
 * person sets their own password when they accept it; nobody else ever chooses it); editing
 * renames. Refusals stay in the dialog.
 */
@Component({
  selector: 'app-user-dialog',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    FormField,
    MatDialogTitle,
    MatDialogContent,
    MatDialogActions,
    MatButtonToggleGroup,
    MatButtonToggle,
    MatFormField,
    MatLabel,
    MatInput,
    MatButton,
  ],
  template: `
    <h2 mat-dialog-title>{{ editing ? 'Edit details' : 'Invite user' }}</h2>
    <form novalidate (submit)="save($event)">
      <mat-dialog-content>
        <div class="flex flex-col gap-5 pt-1">
          <p class="text-sm leading-[1.4] text-muted">{{ subtitle() }}</p>
          @if (!editing && data.canAddOwners) {
            <div>
              <mat-button-toggle-group
                aria-label="Role"
                hideSingleSelectionIndicator
                [value]="role()"
                (change)="role.set($event.value)"
              >
                <mat-button-toggle value="staff">Staff</mat-button-toggle>
                <mat-button-toggle value="owner">Owner</mat-button-toggle>
              </mat-button-toggle-group>
            </div>
          }
          <mat-form-field>
            <mat-label>Name</mat-label>
            <input matInput autocomplete="off" [formField]="f.name" />
          </mat-form-field>
          @if (!editing) {
            <mat-form-field>
              <mat-label>Email</mat-label>
              <input
                matInput
                type="email"
                autocomplete="off"
                placeholder="name@404arena.in"
                [formField]="f.email"
              />
            </mat-form-field>
          } @else {
            <p class="text-sm text-muted">Email: {{ data.user?.email }}</p>
          }
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
        </div>
      </mat-dialog-content>
      <mat-dialog-actions align="end">
        <button mat-button type="button" [disabled]="busy()" (click)="ref.close()">Cancel</button>
        <button mat-flat-button type="submit" [disabled]="busy()">
          {{ editing ? 'Save' : 'Send invitation' }}
        </button>
      </mat-dialog-actions>
    </form>
  `,
})
export class UserDialog {
  protected readonly data = inject<UserDialogData>(MAT_DIALOG_DATA);
  protected readonly ref = inject<MatDialogRef<UserDialog, UserDialogResult>>(MatDialogRef);
  private readonly store = inject(UsersStore);

  protected readonly editing = !!this.data.user;
  protected readonly role = signal<UserRole>('staff');
  protected readonly subtitle = computed(() =>
    this.editing ? 'Changes apply next time they sign in.' : SUBTITLES[this.role()],
  );

  protected readonly model = signal({ name: this.data.user?.name ?? '', email: '' });
  protected readonly f = form(this.model, (p) => {
    validate(p.name, ({ value }) =>
      value().trim().length >= 2 ? null : { kind: 'name', message: 'Enter a name' },
    );
    hidden(p.email, { when: () => this.editing });
    validate(p.email, ({ value }) => {
      const email = value().trim().toLowerCase();
      if (!/^\S+@\S+\.\S+$/.test(email)) return { kind: 'email', message: 'Enter a valid email' };
      return this.store.users().some((u) => u.email.toLowerCase() === email)
        ? { kind: 'taken', message: 'That email already has access to this arena' }
        : null;
    });
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
    const name = this.model().name.trim();
    this.busy.set(true);
    this.error.set('');
    try {
      const user = this.data.user;
      if (user) {
        await this.store.change(user, { name });
        this.ref.close({ userId: user.userId, snack: 'Details saved' });
        return;
      }
      const role = this.role();
      const email = this.model().email.trim().toLowerCase();
      await this.store.invite({
        role,
        name,
        email,
        perms: role === 'owner' ? [] : DEFAULT_STAFF_PERMS,
      });
      this.ref.close({
        snack: `Invitation sent to ${email}${role === 'owner' ? ' as an owner' : ''}`,
      });
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
