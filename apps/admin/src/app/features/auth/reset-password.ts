import { Location, PlatformLocation } from '@angular/common';
import { Component, computed, inject, signal } from '@angular/core';
import { FormField, form, validate } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router, RouterLink } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { AuthApi, MIN_PASSWORD, passwordProblem, toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';
import { AuthCard } from './auth-card';
import { focusOnStepChange } from './step-focus';

type Step = 'loading' | 'link-error' | 'failed' | 'password' | 'done';

export const RESET_LINK_EXPIRED =
  'This reset link has expired or was already used. Ask for a new one.';
export const RESET_LINK_INCOMPLETE =
  'This reset link is incomplete. Open the whole link from the email, or ask for a new one.';

/**
 * Opened from the password-reset email (AuthApi.requestPasswordReset): Supabase Auth appends
 * `#access_token…&type=recovery`, or `#error…` for a used or expired link. The tokens are read
 * once and the address replaced with `/reset-password` straight away. The link signs the person
 * in; they choose a new password, then continue to the dashboard (owners and managers) or are
 * told to sign in on the staff app.
 */
@Component({
  selector: 'app-reset-password',
  providers: [MATERIAL_DEFAULTS],
  imports: [
    AuthCard,
    FormField,
    MatFormField,
    MatLabel,
    MatHint,
    MatInput,
    MatButton,
    MatProgressBar,
    RouterLink,
  ],
  template: `
    @switch (step()) {
      @case ('link-error') {
        <app-auth-card heading="Password reset link" subtitle="Your password was not changed.">
          <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">{{ error() }}</p>
          <p class="text-sm text-muted">
            <a routerLink="/sign-in" [queryParams]="{ step: 'forgot' }">Ask for a new link</a>
          </p>
        </app-auth-card>
      }
      @case ('failed') {
        <app-auth-card heading="Password reset link" subtitle="Your password was not changed.">
          <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">{{ error() }}</p>
          <button mat-flat-button type="button" class="arena-cta" data-step-focus (click)="start()">
            Try again
          </button>
        </app-auth-card>
      }
      @case ('password') {
        <app-auth-card
          heading="Choose a new password"
          [subtitle]="
            'For ' + email() + '. It replaces your old password here and on the staff app.'
          "
        >
          <form class="flex flex-col gap-5" novalidate (submit)="save($event)">
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>New password</mat-label>
              <input
                matInput
                type="password"
                autocomplete="new-password"
                data-step-focus
                [formField]="passwordForm.password"
              />
              <mat-hint>At least {{ minPassword }} characters, letters and digits</mat-hint>
            </mat-form-field>
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Type it again</mat-label>
              <input
                matInput
                type="password"
                autocomplete="new-password"
                [formField]="passwordForm.again"
              />
            </mat-form-field>
            @if (error()) {
              <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">
                {{ error() }}
              </p>
            }
            <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
              Save new password
            </button>
          </form>
        </app-auth-card>
      }
      @case ('done') {
        <app-auth-card heading="Password changed" [subtitle]="'Signed in as ' + email() + '.'">
          @if (dashboard()) {
            <p role="status" class="sr-only">Your new password is saved.</p>
            <button
              mat-flat-button
              type="button"
              class="arena-cta"
              data-step-focus
              (click)="openDashboard()"
            >
              Open dashboard
            </button>
          } @else {
            <p role="status" class="text-sm leading-[1.45]">
              Sign in on the staff app with {{ email() }} and your new password.
            </p>
            <button
              mat-flat-button
              type="button"
              class="arena-cta"
              data-step-focus
              (click)="done()"
            >
              Done
            </button>
          }
        </app-auth-card>
      }
      @default {
        <app-auth-card heading="Password reset" subtitle="One moment…">
          <mat-progress-bar mode="indeterminate" aria-label="Opening the reset link" />
        </app-auth-card>
      }
    }
  `,
})
export class ResetPassword {
  private readonly api = inject(AuthApi);
  private readonly session = inject(Session);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);
  private readonly location = inject(Location);

  /** Read once from the address (kept only in memory). */
  private readonly link: {
    readonly access: string | null;
    readonly refresh: string | null;
    readonly type: string | null;
    readonly error: string | null;
  };

  protected readonly minPassword = MIN_PASSWORD;
  protected readonly step = signal<Step>('loading');
  protected readonly error = signal('');
  protected readonly busy = signal(false);
  /** The login may use this dashboard (manages an arena); otherwise it is floor staff. */
  protected readonly dashboard = signal(false);
  protected readonly email = computed(() => this.session.user()?.email ?? '');

  protected readonly passwordModel = signal({ password: '', again: '' });
  protected readonly passwordForm = form(this.passwordModel, (p) => {
    validate(p.password, ({ value }) => {
      const problem = passwordProblem(value());
      return problem ? { kind: 'password', message: problem } : null;
    });
    validate(p.again, ({ value, valueOf }) =>
      value() === valueOf(p.password)
        ? null
        : { kind: 'mismatch', message: 'The two passwords are different' },
    );
  });

  constructor() {
    // The address as opened (the browser's location; tests use Angular's fake navigation).
    const fragment = new URLSearchParams(inject(PlatformLocation).hash.replace(/^#/, ''));
    this.link = {
      access: fragment.get('access_token'),
      refresh: fragment.get('refresh_token'),
      type: fragment.get('type'),
      error: fragment.get('error_code') ?? fragment.get('error'),
    };
    // The session tokens must not stay in the address bar or history.
    this.location.replaceState('/reset-password');
    focusOnStepChange(this.step);
    void this.start();
  }

  protected async start(): Promise<void> {
    this.error.set('');
    if (this.link.error) {
      // otp_expired (used, or too old) or access_denied: either way the link is spent.
      this.linkError(RESET_LINK_EXPIRED);
      return;
    }
    if (!this.link.access || !this.link.refresh || this.link.type !== 'recovery') {
      this.linkError(RESET_LINK_INCOMPLETE);
      return;
    }
    this.step.set('loading');
    try {
      await this.api.signInFromLink(this.link.access, this.link.refresh);
      await this.session.refresh();
    } catch (e) {
      const err = toAppError(e);
      if (err.code === 'network') {
        this.error.set(err.message);
        this.step.set('failed');
      } else {
        this.linkError(RESET_LINK_EXPIRED);
      }
      return;
    }
    this.step.set('password');
  }

  protected async save(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.passwordForm().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      await this.api.setPassword(this.passwordModel().password);
    } catch (e) {
      this.error.set(toAppError(e).message);
      return;
    } finally {
      this.busy.set(false);
    }
    this.passwordModel.set({ password: '', again: '' });
    let dashboard = true;
    try {
      await this.arena.load(true);
      dashboard = this.arena.arenas().length > 0;
    } catch {
      // Not readable right now: the dashboard's own guard decides when it is opened.
    }
    this.dashboard.set(dashboard);
    this.step.set('done');
  }

  protected async openDashboard(): Promise<void> {
    await this.router.navigateByUrl('/');
  }

  /** Staff are done here: they work on the staff app, so leave the dashboard signed out. */
  protected async done(): Promise<void> {
    await this.session.signOut();
  }

  private linkError(message: string): void {
    this.error.set(message);
    this.step.set('link-error');
  }
}
