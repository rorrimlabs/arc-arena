import { Component, computed, effect, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatIcon } from '@angular/material/icon';
import { MatProgressBar } from '@angular/material/progress-bar';
import { MatSnackBar } from '@angular/material/snack-bar';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { StatusPill } from '../../shared/status-pill/status-pill';
import { UserDetail } from './components/user-detail';
import { initials, statusTone } from './components/user-format';
import { UsersStore } from './data/users-store';
import { ArenaUser } from './data/user.models';
import { UserDialog, UserDialogData, UserDialogResult } from './dialogs/user-dialog';

/**
 * Users (design: `if (p === 'staff')`, extended to owners): owners and staff listed in their own
 * sections. The selected user is in the URL (`?id=`); on a wide screen the first one is shown
 * when none is chosen, as in the design.
 */
@Component({
  selector: 'app-users-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    UserDetail,
    StatusPill,
    MatButton,
    MatIcon,
    MatProgressBar,
  ],
  template: `
    <app-list-detail listLabel="Users" detailLabel="User" [open]="!!selected()" (closed)="close()">
      <ng-container list>
        <app-list-pane-header title="Users">
          <button actions mat-flat-button type="button" (click)="add()">
            <mat-icon aria-hidden="true">add</mat-icon>Add
          </button>
          <p class="text-[13px] leading-[1.3] text-muted">
            Owners manage the arena here. Staff sign in on the floor app.
          </p>
        </app-list-pane-header>
        @if (store.loading()) {
          <mat-progress-bar mode="indeterminate" aria-label="Loading users" />
        }
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          @if (store.loadError(); as error) {
            <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
              <p role="alert" class="text-sm text-danger">{{ error }}</p>
              <button mat-stroked-button type="button" (click)="store.load(true)">Try again</button>
            </div>
          } @else if (!store.loading() || store.users().length) {
            @for (group of groups(); track group.heading) {
              <section [attr.aria-labelledby]="'users-' + group.key">
                <h2
                  [id]="'users-' + group.key"
                  class="px-3 pt-4 pb-2 text-xs leading-none font-semibold text-subtle"
                >
                  {{ group.heading }} · {{ group.users.length }}
                </h2>
                <ul class="flex flex-col gap-0.5">
                  @for (u of group.users; track u.userId) {
                    <li>
                      <app-list-row
                        [title]="u.name"
                        [subtitle]="u.email"
                        [initials]="initials(u.name)"
                        [selected]="u.userId === selected()?.userId"
                        [queryParams]="{ id: u.userId }"
                      >
                        <app-status-pill [tone]="tone(u)">{{ label(u) }}</app-status-pill>
                      </app-list-row>
                    </li>
                  } @empty {
                    <li class="px-3 py-4 text-sm text-muted">{{ group.empty }}</li>
                  }
                </ul>
              </section>
            }
          }
        </div>
      </ng-container>
      <ng-container detail>
        @if (selected(); as user) {
          <app-user-detail [user]="user" (closed)="close()" />
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class UsersPage {
  protected readonly store = inject(UsersStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);
  private readonly dialog = inject(MatDialog);
  private readonly snack = inject(MatSnackBar);

  /** `?id=` — the selected user. */
  readonly id = input<string>();

  protected readonly initials = initials;
  protected readonly groups = computed(() => [
    {
      key: 'owners',
      heading: 'Owners',
      users: this.store.owners(),
      empty: 'No owners.',
    },
    {
      key: 'staff',
      heading: 'Staff',
      users: this.store.staff(),
      empty: 'No staff yet. Add the people who run the floor.',
    },
  ]);
  protected readonly selected = computed<ArenaUser | undefined>(() => {
    const id = this.id();
    if (id) return this.store.byId().get(id);
    return this.layout.wideDetail() ? this.store.users()[0] : undefined;
  });

  constructor() {
    // Load (and reload on an arena switch) the current arena's users.
    effect(() => {
      if (this.arena.current().id) void this.store.load();
    });
  }

  protected label(u: ArenaUser): string {
    return statusTone(u).label;
  }

  protected tone(u: ArenaUser) {
    return statusTone(u).tone;
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }

  protected add(): void {
    this.dialog
      .open<UserDialog, UserDialogData, UserDialogResult>(UserDialog, {
        data: { canAddOwners: this.arena.currentRole() === 'owner' },
        width: '520px',
        maxWidth: 'calc(100vw - 32px)',
      })
      .afterClosed()
      .subscribe((result) => {
        if (!result) return;
        this.snack.open(result.snack, undefined, { duration: 3200 });
        void this.router.navigate([], { queryParams: { id: result.userId } });
      });
  }
}
