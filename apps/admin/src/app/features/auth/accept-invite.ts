import { Location, PlatformLocation } from '@angular/common';
import { Component, computed, inject, signal } from '@angular/core';
import { FormField, email, form, required, validate } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router, RouterLink } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import {
  AcceptedInvite,
  AuthApi,
  INVITE_ACCEPT_MESSAGES,
  MIN_PASSWORD,
  passwordProblem,
  toAppError,
} from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';
import { AuthCard } from './auth-card';

type Step =
  | 'loading'
  | 'invalid'
  | 'link-error'
  | 'sign-in'
  | 'password'
  | 'confirm'
  | 'working'
  | 'done'
  | 'failed';

const INVITE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^[0-9a-f]{64}$/i;

export const LINK_EXPIRED = 'This link has expired. Ask for a new invitation.';
const LINK_UNUSABLE = 'This link can no longer be used. Ask for a new invitation.';

/**
 * Opened from the invitation e-mail: `/accept-invite?invite=<id>&token=<hex>` plus the
 * fragment Supabase Auth appends (`#access_token…&type=invite` for a new login,
 * `type=magiclink` for an existing one, or `#error…`). The token is read once and the address
 * replaced with `/accept-invite` straight away. A new login chooses its password before
 * joining; anyone without a link session can sign in to accept. Owners continue to the
 * dashboard; staff are told to sign in on the staff app.
 */
@Component({
  selector: 'app-accept-invite',
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
      @case ('invalid') {
        <app-auth-card heading="Invitation link incomplete" subtitle="Nothing was changed.">
          <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">
            This invitation link is incomplete. Open the whole link from the e-mail, or ask for a
            new invitation.
          </p>
          <p class="text-sm text-muted"><a routerLink="/sign-in">Go to sign in</a></p>
        </app-auth-card>
      }
      @case ('link-error') {
        <app-auth-card heading="Invitation link" subtitle="Nothing was changed.">
          <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">
            {{ linkError() }}
          </p>
          <p class="text-sm leading-[1.45] text-muted">
            Already chose a password for this e-mail address? You can still sign in to accept.
          </p>
          <button mat-stroked-button type="button" class="arena-cta" (click)="step.set('sign-in')">
            Sign in to accept
          </button>
        </app-auth-card>
      }
      @case ('sign-in') {
        <app-auth-card
          heading="Sign in to accept"
          subtitle="Use the e-mail address the invitation was sent to, and your password."
        >
          <form class="flex flex-col gap-5" novalidate (submit)="signIn($event)">
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Email</mat-label>
              <input matInput type="email" autocomplete="email" [formField]="signInForm.email" />
            </mat-form-field>
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Password</mat-label>
              <input
                matInput
                type="password"
                autocomplete="current-password"
                [formField]="signInForm.password"
              />
            </mat-form-field>
            @if (error()) {
              <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">
                {{ error() }}
              </p>
            }
            <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
              Sign in and accept
            </button>
          </form>
        </app-auth-card>
      }
      @case ('password') {
        <app-auth-card
          heading="Choose your password"
          [subtitle]="
            'Signed in as ' + email() + '. You will sign in with this e-mail and this password.'
          "
        >
          <form class="flex flex-col gap-5" novalidate (submit)="savePassword($event)">
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Password</mat-label>
              <input
                matInput
                type="password"
                autocomplete="new-password"
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
              Save password and join
            </button>
          </form>
        </app-auth-card>
      }
      @case ('confirm') {
        <app-auth-card
          heading="Accept your invitation"
          [subtitle]="'Signed in as ' + email() + '.'"
        >
          <form class="flex flex-col gap-5" novalidate (submit)="savePassword($event)">
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>New password (optional)</mat-label>
              <input
                matInput
                type="password"
                autocomplete="new-password"
                [formField]="passwordForm.password"
              />
              <mat-hint>Leave blank to keep your current password</mat-hint>
            </mat-form-field>
            @if (passwordModel().password) {
              <mat-form-field appearance="outline" subscriptSizing="dynamic">
                <mat-label>Type it again</mat-label>
                <input
                  matInput
                  type="password"
                  autocomplete="new-password"
                  [formField]="passwordForm.again"
                />
              </mat-form-field>
            }
            @if (error()) {
              <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">
                {{ error() }}
              </p>
            }
            <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
              Accept invitation
            </button>
            <button
              mat-button
              type="button"
              class="arena-cta"
              [disabled]="busy()"
              (click)="switchAccount()"
            >
              Not you? Sign out
            </button>
          </form>
        </app-auth-card>
      }
      @case ('done') {
        @let joined = result();
        @if (dashboard()) {
          <app-auth-card
            [heading]="'Welcome to ' + (joined?.arenaName ?? 'the arena')"
            subtitle="You can now manage the arena on this dashboard."
          >
            <p role="status" class="sr-only">Invitation accepted.</p>
            <button mat-flat-button type="button" class="arena-cta" (click)="openDashboard()">
              Open dashboard
            </button>
          </app-auth-card>
        } @else {
          <app-auth-card
            [heading]="'You have joined ' + (joined?.arenaName ?? 'the arena')"
            subtitle="Invitation accepted."
          >
            <p role="status" class="text-sm leading-[1.45]">
              Sign in on the staff app with {{ email() }} and your password.
            </p>
            <button mat-flat-button type="button" class="arena-cta" (click)="done()">Done</button>
          </app-auth-card>
        }
      }
      @case ('failed') {
        <app-auth-card heading="Could not accept the invitation" subtitle="Nothing was changed.">
          <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">{{ error() }}</p>
          @if (retryable()) {
            <button mat-flat-button type="button" class="arena-cta" (click)="retry()">
              Try again
            </button>
          }
          @if (session.signedIn()) {
            <button mat-stroked-button type="button" class="arena-cta" (click)="switchAccount()">
              Sign out
            </button>
          } @else {
            <p class="text-sm text-muted"><a routerLink="/sign-in">Go to sign in</a></p>
          }
        </app-auth-card>
      }
      @default {
        <app-auth-card heading="Invitation" subtitle="One moment…">
          <mat-progress-bar mode="indeterminate" aria-label="Accepting the invitation" />
        </app-auth-card>
      }
    }
  `,
})
export class AcceptInvite {
  private readonly api = inject(AuthApi);
  protected readonly session = inject(Session);
  private readonly arena = inject(ArenaContext);
  private readonly router = inject(Router);
  private readonly location = inject(Location);

  /** Read once from the address (kept only in memory). */
  private readonly inviteId: string;
  private readonly token: string;
  private readonly link: {
    readonly access: string | null;
    readonly refresh: string | null;
    readonly type: string | null;
    readonly error: string | null;
  };

  protected readonly minPassword = MIN_PASSWORD;
  protected readonly step = signal<Step>('loading');
  protected readonly error = signal('');
  protected readonly linkError = signal(LINK_EXPIRED);
  protected readonly retryable = signal(false);
  protected readonly busy = signal(false);
  protected readonly result = signal<AcceptedInvite | null>(null);
  /** The joined login may use this dashboard (owner level); otherwise it is floor staff. */
  protected readonly dashboard = signal(false);
  protected readonly email = computed(() => this.session.user()?.email ?? '');

  protected readonly signInModel = signal({ email: '', password: '' });
  protected readonly signInForm = form(this.signInModel, (p) => {
    required(p.email, { message: 'Enter your email' });
    email(p.email, { message: 'Enter a valid email' });
    required(p.password, { message: 'Enter your password' });
  });

  /** The new password: required for a new login, optional when confirming. */
  protected readonly passwordModel = signal({ password: '', again: '' });
  protected readonly passwordForm = form(this.passwordModel, (p) => {
    validate(p.password, ({ value }) => {
      if (!value() && this.step() === 'confirm') return null;
      const problem = passwordProblem(value());
      return problem ? { kind: 'password', message: problem } : null;
    });
    validate(p.again, ({ value, valueOf }) =>
      !valueOf(p.password) || value() === valueOf(p.password)
        ? null
        : { kind: 'mismatch', message: 'The two passwords are different' },
    );
  });

  constructor() {
    // The address as opened (the browser's location; tests use Angular's fake navigation).
    const { search, hash } = inject(PlatformLocation);
    const query = new URLSearchParams(search);
    const fragment = new URLSearchParams(hash.replace(/^#/, ''));
    this.inviteId = query.get('invite') ?? '';
    this.token = query.get('token') ?? '';
    this.link = {
      access: fragment.get('access_token'),
      refresh: fragment.get('refresh_token'),
      type: fragment.get('type'),
      error: fragment.get('error_code') ?? fragment.get('error'),
    };
    // The one-time token (and any session tokens) must not stay in the address bar or history.
    this.location.replaceState('/accept-invite');
    void this.start();
  }

  private async start(): Promise<void> {
    if (!INVITE_ID.test(this.inviteId) || !TOKEN.test(this.token)) {
      this.step.set('invalid');
      return;
    }
    if (this.link.error) {
      this.linkError.set(this.link.error === 'otp_expired' ? LINK_EXPIRED : LINK_UNUSABLE);
      this.step.set('link-error');
      return;
    }
    if (this.link.access && this.link.refresh) {
      try {
        await this.api.signInFromLink(this.link.access, this.link.refresh);
        await this.session.refresh();
      } catch (e) {
        const err = toAppError(e);
        if (err.code === 'network') {
          this.fail(err.message, true);
          return;
        }
        this.linkError.set(LINK_UNUSABLE);
        this.step.set('link-error');
        return;
      }
      // A new login has no password yet: it chooses one before joining.
      this.step.set(this.link.type === 'invite' ? 'password' : 'confirm');
      return;
    }
    await this.session.ready;
    this.step.set(this.session.signedIn() ? 'confirm' : 'sign-in');
  }

  protected async signIn(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.signInForm().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const { email: address, password } = this.signInModel();
    this.busy.set(true);
    this.error.set('');
    try {
      await this.api.signIn(address.trim().toLowerCase(), password);
      await this.session.refresh();
    } catch (e) {
      const err = toAppError(e);
      this.error.set(
        err.code === 'email_not_confirmed'
          ? INVITE_ACCEPT_MESSAGES['email_not_confirmed']
          : err.message,
      );
      this.busy.set(false);
      return;
    }
    this.busy.set(false);
    await this.accept();
  }

  /** Password step (required) or confirm step (optional): save it, then join. */
  protected async savePassword(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.passwordForm().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const password = this.passwordModel().password;
    if (password) {
      this.busy.set(true);
      this.error.set('');
      try {
        await this.api.setPassword(password);
      } catch (e) {
        this.error.set(toAppError(e).message);
        this.busy.set(false);
        return;
      }
      this.busy.set(false);
      // Saved: a retry after a failed accept must not ask for it again.
      this.passwordModel.set({ password: '', again: '' });
    }
    await this.accept();
  }

  protected async retry(): Promise<void> {
    if (this.session.signedIn()) await this.accept();
    else await this.start();
  }

  /** Signs out of the wrong (or someone else's) login and offers to sign in as the invitee. */
  protected async switchAccount(): Promise<void> {
    await this.api.signOut();
    await this.session.refresh();
    this.error.set('');
    this.step.set('sign-in');
  }

  protected async openDashboard(): Promise<void> {
    const joined = this.result();
    if (joined) this.arena.select(joined.arenaId);
    await this.router.navigateByUrl('/');
  }

  /** Staff are done here: they work on the staff app, so leave the dashboard signed out. */
  protected async done(): Promise<void> {
    await this.session.signOut();
  }

  private async accept(): Promise<void> {
    this.step.set('working');
    this.error.set('');
    try {
      const joined = await this.api.acceptInvite(this.inviteId, this.token);
      this.result.set(joined);
      try {
        await this.arena.load(true);
      } catch {
        // Not readable right now: decide by the invitation's role.
      }
      this.dashboard.set(
        joined.role === 'owner' || this.arena.arenas().some((a) => a.id === joined.arenaId),
      );
      this.step.set('done');
    } catch (e) {
      const err = toAppError(e);
      if (err.code === 'forbidden') {
        // Not signed in (any more): sign in as the invited address.
        this.error.set(err.message);
        this.step.set('sign-in');
        return;
      }
      if (err.code === 'invite_wrong_account') {
        this.fail(
          `You are signed in as ${this.email()}, but this invitation was sent to a different e-mail address. Sign out, then open the link from the e-mail again.`,
        );
        return;
      }
      this.fail(err.message, err.code === 'network');
    }
  }

  private fail(message: string, retryable = false): void {
    this.error.set(message);
    this.retryable.set(retryable);
    this.step.set('failed');
  }
}
