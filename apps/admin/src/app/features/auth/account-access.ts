import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router } from '@angular/router';
import { ACCESS_HOME, ArenaContext } from '../../core/arena/arena-context';
import { toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { AuthCard } from './auth-card';

/**
 * A signed-in login the dashboard is not for, told why from its server-side memberships
 * (ArenaContext.access): floor staff (use the staff app), access turned off (ask the owner, or the
 * operator for an owner), or memberships that could not be read (try again). An owner-level login
 * or a new owner who lands here is sent on (dashboard / Create Arena); a staff login never sees
 * Create Arena.
 */
@Component({
  selector: 'app-account-access',
  imports: [AuthCard, MatButton, MatProgressBar],
  template: `
    @switch (state()) {
      @case ('error') {
        <app-auth-card heading="We couldn't check your access" [subtitle]="signedInAs()">
          <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">{{ error() }}</p>
          <button
            mat-flat-button
            type="button"
            class="arena-cta"
            [disabled]="busy()"
            (click)="check()"
          >
            Try again
          </button>
          <button mat-button type="button" class="self-start" (click)="session.signOut()">
            Sign out
          </button>
        </app-auth-card>
      }
      @case ('staff') {
        <app-auth-card heading="Use the 404 Arena staff app" [subtitle]="signedInAs()">
          <p role="status" class="text-sm leading-[1.45]">
            You are on the staff of {{ arenaNames() }}. Sign in on the staff app with
            {{ session.user()?.email }} and your password.
          </p>
          <p class="text-sm leading-[1.45] text-muted">
            This dashboard is for owners and managers. If you should manage the arena here, ask the
            owner to give you Money or Reports access.
          </p>
          <button mat-flat-button type="button" class="arena-cta" (click)="session.signOut()">
            Sign out
          </button>
        </app-auth-card>
      }
      @case ('off') {
        <app-auth-card heading="Your access is turned off" [subtitle]="signedInAs()">
          <p role="status" class="text-sm leading-[1.45]">
            Your access to {{ arenaNames() }} has been turned off.
            {{
              owner()
                ? 'Ask the operator to restore it.'
                : 'Ask the owner to turn it back on if you still need it.'
            }}
          </p>
          <button mat-flat-button type="button" class="arena-cta" (click)="session.signOut()">
            Sign out
          </button>
        </app-auth-card>
      }
      @default {
        <app-auth-card heading="Your access" subtitle="One moment…">
          <mat-progress-bar mode="indeterminate" aria-label="Checking your access" />
        </app-auth-card>
      }
    }
  `,
})
export class AccountAccess implements OnInit {
  protected readonly session = inject(Session);
  private readonly context = inject(ArenaContext);
  private readonly router = inject(Router);

  protected readonly error = signal('');
  protected readonly busy = signal(false);
  protected readonly state = computed(() =>
    this.error() ? 'error' : this.context.loaded() ? this.context.access() : 'loading',
  );
  protected readonly signedInAs = computed(
    () => `Signed in as ${this.session.user()?.email ?? ''}.`,
  );
  /** The arenas this login is a member of, named (active ones for staff, all when off). */
  protected readonly arenaNames = computed(() => {
    const all = this.context.memberships();
    const shown = this.context.access() === 'staff' ? all.filter((m) => m.active) : all;
    return shown.map((m) => m.arenaName).join(', ');
  });
  /** An owner whose own access is off: only the operator can restore it. */
  protected readonly owner = computed(() =>
    this.context.memberships().some((m) => m.role === 'owner'),
  );

  ngOnInit(): void {
    void this.check();
  }

  /** Reads the memberships again; an owner or a new owner is sent where they belong. */
  protected async check(): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      await this.context.load(true);
    } catch (e) {
      this.error.set(toAppError(e).message);
      return;
    } finally {
      this.busy.set(false);
    }
    const access = this.context.access();
    if (access === 'owner' || access === 'none') {
      await this.router.navigateByUrl(ACCESS_HOME[access]);
    }
  }
}
