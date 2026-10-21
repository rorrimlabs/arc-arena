import { Location, PlatformLocation } from '@angular/common';
import { Component, inject, input, linkedSignal, signal } from '@angular/core';
import { FormField, email, form, required, validate } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { MatProgressBar } from '@angular/material/progress-bar';
import { Router, RouterLink } from '@angular/router';
import { AuthApi, MIN_PASSWORD, passwordProblem, toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { AuthCard } from './auth-card';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';
import { Captcha, Turnstile } from '../../shared/turnstile/turnstile';

type Step = 'details' | 'check' | 'confirming' | 'link-error';

const CONFIRM_LINK_EXPIRED =
  'This confirmation link has expired or was already used.';
const CONFIRM_LINK_INCOMPLETE =
  'This confirmation link is incomplete. Open the whole link from the email.';

/**
 * New arena owner: email + password, then the link in the confirmation email, which opens this
 * page again with `#access_token…&type=signup` (or `#error…` for a used or expired link). The
 * tokens are read once and the address replaced with `/register` straight away; the confirmed
 * login continues to create its arena. Staff never register here — they join from the
 * invitation an owner sends them from Users.
 */
@Component({
  selector: 'app-register',
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
    Turnstile,
  ],
  template: `
    @if (currentStep() === 'details') {
      <app-auth-card
        heading="Create your account"
        subtitle="For arena owners. Staff join from the invitation you send them, then sign in on the floor app."
      >
        <form class="flex flex-col gap-5" novalidate (submit)="signUp($event)">
          <mat-form-field appearance="outline" subscriptSizing="dynamic">
            <mat-label>Email</mat-label>
            <input matInput type="email" autocomplete="email" [formField]="details.email" />
          </mat-form-field>
          <mat-form-field appearance="outline" subscriptSizing="dynamic">
            <mat-label>Password</mat-label>
            <input
              matInput
              type="password"
              autocomplete="new-password"
              [formField]="details.password"
            />
            <mat-hint>At least {{ minPassword }} characters, letters and digits</mat-hint>
          </mat-form-field>
          <mat-form-field appearance="outline" subscriptSizing="dynamic">
            <mat-label>Type it again</mat-label>
            <input
              matInput
              type="password"
              autocomplete="new-password"
              [formField]="details.again"
            />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
          <app-turnstile />
          <button
            mat-flat-button
            type="submit"
            class="arena-cta"
            [disabled]="busy() || !captcha.ready()"
          >
            Create account
          </button>
        </form>
        <p class="text-sm text-muted">
          Already have an account? <a routerLink="/sign-in">Sign in</a>
        </p>
      </app-auth-card>
    } @else if (currentStep() === 'check') {
      <app-auth-card
        heading="Check your email"
        [subtitle]="
          'We sent a confirmation link to ' +
          pendingEmail() +
          '. Open it in this browser to continue. If that email already has an account, no link is sent: sign in instead.'
        "
      >
        @if (error()) {
          <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
        }
        @if (info()) {
          <p role="status" class="text-sm leading-[1.3] text-muted">{{ info() }}</p>
        }
        <app-turnstile />
        <button
          mat-stroked-button
          type="button"
          class="arena-cta"
          [disabled]="busy() || !captcha.ready()"
          (click)="resend()"
        >
          Resend link
        </button>
        <p class="text-sm text-muted"><a routerLink="/sign-in">Back to sign in</a></p>
      </app-auth-card>
    } @else if (currentStep() === 'confirming') {
      <app-auth-card heading="Confirming your email" subtitle="One moment.">
        <mat-progress-bar mode="indeterminate" />
      </app-auth-card>
    } @else {
      <app-auth-card heading="Confirmation link" subtitle="Your account was not confirmed.">
        <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">{{ error() }}</p>
        <p class="text-sm leading-[1.45] text-muted">
          Sign in with your email and password: if your email is not confirmed yet, you can send a
          new link from there.
        </p>
        <p class="text-sm text-muted"><a routerLink="/sign-in">Go to sign in</a></p>
      </app-auth-card>
    }
  `,
})
export class Register {
  protected readonly captcha = inject(Captcha);
  private readonly api = inject(AuthApi);
  private readonly session = inject(Session);
  private readonly router = inject(Router);
  private readonly location = inject(Location);

  /** `?step=check&email=…` resumes at "check your email" (e.g. after signing in unconfirmed). */
  readonly step = input<string>();
  readonly email = input<string>();

  protected readonly minPassword = MIN_PASSWORD;
  protected readonly currentStep = linkedSignal<Step>(() =>
    this.step() === 'check' && this.email() ? 'check' : 'details',
  );
  protected readonly pendingEmail = linkedSignal(() => this.email() ?? '');

  protected readonly detailsModel = signal({ email: '', password: '', again: '' });
  protected readonly details = form(this.detailsModel, (p) => {
    required(p.email, { message: 'Enter your email' });
    email(p.email, { message: 'Enter a valid email' });
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

  protected readonly error = signal('');
  protected readonly info = signal('');
  protected readonly busy = signal(false);

  constructor() {
    // Opened from the confirmation link? (The browser's location; tests use fake navigation.)
    const fragment = new URLSearchParams(inject(PlatformLocation).hash.replace(/^#/, ''));
    const link = {
      access: fragment.get('access_token'),
      refresh: fragment.get('refresh_token'),
      type: fragment.get('type'),
      error: fragment.get('error_code') ?? fragment.get('error'),
    };
    if (!link.access && !link.error) return;
    // The session tokens must not stay in the address bar or history.
    this.location.replaceState('/register');
    void this.confirm(link);
  }

  protected async signUp(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.details().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const address = this.detailsModel().email.trim().toLowerCase();
    await this.run(async () => {
      const outcome = await this.api.signUp(address, this.detailsModel().password);
      if (outcome === 'signed-in') {
        await this.session.refresh();
        await this.router.navigate(['/create-arena']);
        return;
      }
      this.pendingEmail.set(address);
      this.currentStep.set('check');
    });
  }

  protected async resend(): Promise<void> {
    await this.run(async () => {
      await this.api.resendConfirmation(this.pendingEmail());
      this.info.set(`Sent a new link to ${this.pendingEmail()}.`);
    });
  }

  private async confirm(link: {
    access: string | null;
    refresh: string | null;
    type: string | null;
    error: string | null;
  }): Promise<void> {
    if (link.error) {
      // otp_expired (used, or too old) or access_denied: either way the link is spent.
      this.linkError(CONFIRM_LINK_EXPIRED);
      return;
    }
    if (!link.access || !link.refresh || link.type !== 'signup') {
      this.linkError(CONFIRM_LINK_INCOMPLETE);
      return;
    }
    this.currentStep.set('confirming');
    try {
      await this.api.signInFromLink(link.access, link.refresh);
      await this.session.refresh();
    } catch (e) {
      const err = toAppError(e);
      this.linkError(err.code === 'network' ? err.message : CONFIRM_LINK_EXPIRED);
      return;
    }
    await this.router.navigate(['/create-arena']);
  }

  private linkError(message: string): void {
    this.error.set(message);
    this.currentStep.set('link-error');
  }

  private async run(action: () => Promise<void>): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    this.info.set('');
    try {
      await action();
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
