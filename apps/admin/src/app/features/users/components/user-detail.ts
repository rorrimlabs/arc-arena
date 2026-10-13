import { Component, computed, inject, input, output } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatSlideToggle, MatSlideToggleChange } from '@angular/material/slide-toggle';
import { MatSnackBar } from '@angular/material/snack-bar';
import { toAppError } from '../../../core/auth/auth-api';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { UsersStore } from '../data/users-store';
import { ArenaUser, FLOOR_PERMS } from '../data/user.models';
import { UserDialog, UserDialogData, UserDialogResult } from '../dialogs/user-dialog';
import { initials, statusTone } from './user-format';

/**
 * Design: `if (p === 'staff')` detail. Staff: 30-day stats, floor permissions, Edit /
 * Deactivate. Owners: every permission, Edit only — removing an owner is an operator action.
 */
@Component({
  selector: 'app-user-detail',
  imports: [DetailPane, DetailSection, StatTile, StatusPill, MatButton, MatIcon, MatSlideToggle],
  template: `
    @let u = user();
    <app-detail-pane
      [crumb]="(u.role === 'owner' ? 'Users / Owners / ' : 'Users / Staff / ') + u.name"
      [heading]="u.name"
      [subtitle]="u.email"
      [initials]="initials(u.name)"
      (closed)="closed.emit()"
    >
      <div actions class="arena-compact flex gap-2">
        <button mat-stroked-button type="button" [disabled]="busy()" (click)="edit()">
          <mat-icon aria-hidden="true">edit</mat-icon>Edit
        </button>
        @if (u.role === 'staff') {
          @if (u.active) {
            <button
              mat-button
              type="button"
              class="danger-action"
              [disabled]="busy()"
              (click)="setActive(false)"
            >
              <mat-icon aria-hidden="true">person_off</mat-icon>Deactivate
            </button>
          } @else {
            <button mat-stroked-button type="button" [disabled]="busy()" (click)="setActive(true)">
              <mat-icon aria-hidden="true">person</mat-icon>Reactivate
            </button>
          }
        }
      </div>
      <app-status-pill chip [tone]="tone()">{{ status() }}</app-status-pill>

      @if (u.role === 'staff') {
        <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
          <app-stat-tile label="Bills · 30 days" [value]="u.bills30d.toString()" />
          <app-stat-tile label="Takings · 30 days" [value]="rupees(u.takings30dPaise)" />
          <app-stat-tile label="Refunds · 30 days" [value]="rupees(u.refunds30dPaise)" />
        </div>
      }
      @if (u.role === 'staff') {
        <app-detail-section
          heading="Permissions"
          subtitle="Applies next time they sign in on the floor app."
        >
          @for (p of perms; track p.code) {
            <div class="flex items-center justify-between gap-4">
              <span class="flex flex-col gap-1">
                <span class="text-[15px] leading-[1.3]" [id]="'perm-' + p.code">{{ p.label }}</span>
                <span class="text-[13px] leading-[1.3] text-muted" [id]="'perm-sub-' + p.code">{{
                  p.sub
                }}</span>
              </span>
              <mat-slide-toggle
                hideIcon
                [checked]="u.perms.includes(p.code)"
                [disabled]="busy() || !u.active"
                [aria-labelledby]="'perm-' + p.code"
                [aria-describedby]="'perm-sub-' + p.code"
                (change)="togglePerm(p.code, $event)"
              />
            </div>
          }
        </app-detail-section>
      } @else {
        <app-detail-section heading="Owner account">
          <p class="text-[13px] leading-[1.45] text-muted">
            Owners have every permission and manage this arena on this dashboard. They can also sign
            in on the floor app. Removing an owner is done by the operator.
          </p>
        </app-detail-section>
      }
      @if (u.invited && u.active) {
        <app-detail-section>
          <p class="text-[13px] leading-[1.45] text-muted">
            {{ u.email }} has not signed in yet. Give them the starting password in person; they
            choose their own after signing in.
          </p>
        </app-detail-section>
      }
    </app-detail-pane>
  `,
})
export class UserDetail {
  private readonly store = inject(UsersStore);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  readonly user = input.required<ArenaUser>();
  readonly closed = output<void>();

  protected readonly perms = FLOOR_PERMS;
  protected readonly initials = initials;
  protected readonly rupees = formatRupees;
  protected readonly status = computed(() => statusTone(this.user()).label);
  protected readonly tone = computed(() => statusTone(this.user()).tone);
  protected readonly busy = computed(() => this.store.saving() === this.user().userId);

  protected edit(): void {
    this.dialog
      .open<UserDialog, UserDialogData, UserDialogResult>(UserDialog, {
        data: { user: this.user() },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (result) this.say(result.snack);
      });
  }

  protected async setActive(active: boolean): Promise<void> {
    const u = this.user();
    try {
      await this.store.change(u, { active });
      this.say(
        active ? `${u.name} reactivated` : `${u.name} deactivated · signed out of the floor app`,
      );
    } catch (e) {
      this.say(toAppError(e).message);
    }
  }

  protected async togglePerm(code: string, event: MatSlideToggleChange): Promise<void> {
    const u = this.user();
    const perms = event.checked ? [...u.perms, code] : u.perms.filter((p) => p !== code);
    try {
      await this.store.change(u, { perms });
    } catch (e) {
      // Refused: put the switch back where the server left it.
      event.source.checked = !event.checked;
      this.say(toAppError(e).message);
    }
  }

  private say(message: string): void {
    this.snack.open(message, undefined, { duration: 3200 });
  }
}
