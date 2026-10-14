import { Component, inject, input, linkedSignal, signal } from '@angular/core';
import { FormField, email, form, required } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { Router, RouterLink } from '@angular/router';
import { AuthApi, toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { AuthCard } from './auth-card';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';
import { focusOnStepChange } from './step-focus';

type Step = 'sign-in' | 'forgot' | 'sent';

/**
 * Owner sign in (design: `signedOut` block). Staff sign in on the floor app instead.
 * `?step=forgot` asks for a password-reset link, which opens /reset-password.
 */
@Component({
  selector: 'app-sign-in',
  providers: [MATERIAL_DEFAULTS],
  imports: [AuthCard, FormField, MatFormField, MatLabel, MatInput, MatButton, RouterLink],
  template: `
    @switch (currentStep()) {
      @case ('forgot') {
        <app-auth-card
          heading="Reset your password"
          subtitle="Enter the email you sign in with. We will email you a link to choose a new password."
        >
          <form class="flex flex-col gap-5" novalidate (submit)="sendReset($event)">
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Email</mat-label>
              <input
                matInput
                type="email"
                autocomplete="email"
                data-step-focus
                [formField]="f.email"
              />
            </mat-form-field>
            @if (error()) {
              <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">
                {{ error() }}
              </p>
            }
            <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
              Send reset link
            </button>
          </form>
          <p class="text-sm text-muted"><a routerLink="/sign-in">Back to sign in</a></p>
        </app-auth-card>
      }
      @case ('sent') {
        <app-auth-card heading="Check your email" subtitle="The link works once.">
          <p role="status" tabindex="-1" data-step-focus class="text-sm leading-[1.45]">
            If {{ sentTo() }} has an account, we sent it a link to choose a new password. Nothing
            there? Check spam, or send it again.
          </p>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
          <button
            mat-stroked-button
            type="button"
            class="arena-cta"
            [disabled]="busy()"
            (click)="resend()"
          >
            Send again
          </button>
          <p class="text-sm text-muted"><a routerLink="/sign-in">Back to sign in</a></p>
        </app-auth-card>
      }
      @default {
        <app-auth-card
          heading="Owner sign in"
          subtitle="Sales, stations, pricing and staff for your arenas."
        >
          <form class="flex flex-col gap-5" novalidate (submit)="submit($event)">
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Email</mat-label>
              <input
                matInput
                type="email"
                autocomplete="email"
                data-step-focus
                [formField]="f.email"
              />
            </mat-form-field>
            <mat-form-field appearance="outline" subscriptSizing="dynamic">
              <mat-label>Password</mat-label>
              <input
                matInput
                type="password"
                autocomplete="current-password"
                [formField]="f.password"
              />
            </mat-form-field>
            @if (error()) {
              <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">
                {{ error() }}
              </p>
            }
            <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
              Sign in
            </button>
          </form>
          <p class="text-sm text-muted">
            <a routerLink="/sign-in" [queryParams]="{ step: 'forgot' }">Forgot your password?</a>
          </p>
          <p class="text-sm text-muted">
            New to ArenaOS? <a routerLink="/register">Create an account</a>
          </p>
        </app-auth-card>
      }
    }
  `,
})
export class SignIn {
  private readonly session = inject(Session);
  private readonly api = inject(AuthApi);
  private readonly router = inject(Router);

  /** `?step=forgot` opens the reset request (the link on this page, or an expired reset link). */
  readonly step = input<string>();
  /** `?next=`: where the visitor was going when sign-in was asked for (Session.safeNext). */
  readonly next = input<string>();

  protected readonly currentStep = linkedSignal<Step>(() =>
    this.step() === 'forgot' ? 'forgot' : 'sign-in',
  );
  /** The address the last reset link went to (as typed, trimmed). */
  protected readonly sentTo = signal('');

  protected readonly model = signal({ email: '', password: '' });
  protected readonly f = form(this.model, (p) => {
    required(p.email, { message: 'Enter your email' });
    email(p.email, { message: 'Enter a valid email' });
    required(p.password, { message: 'Enter your password' });
  });
  /** Each step starts without the previous one's message. */
  protected readonly error = linkedSignal({ source: this.currentStep, computation: () => '' });
  protected readonly busy = signal(false);

  constructor() {
    focusOnStepChange(this.currentStep);
  }

  protected async submit(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the form');
      return;
    }
    const { email: address, password } = this.model();
    this.busy.set(true);
    this.error.set('');
    try {
      await this.session.signIn(address.trim(), password, this.next());
    } catch (e) {
      const err = toAppError(e);
      if (err.code === 'email_not_confirmed') {
        // Signed up but never entered the code: finish that first.
        await this.router.navigate(['/register'], {
          queryParams: { step: 'code', email: address.trim() },
        });
        return;
      }
      this.error.set(err.message);
    } finally {
      this.busy.set(false);
    }
  }

  protected async sendReset(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f.email().errors()[0];
    if (first) {
      this.error.set(first.message ?? 'Enter a valid email');
      return;
    }
    if (await this.requestReset(this.model().email.trim().toLowerCase())) {
      this.currentStep.set('sent');
    }
  }

  protected async resend(): Promise<void> {
    await this.requestReset(this.sentTo());
  }

  private async requestReset(address: string): Promise<boolean> {
    this.busy.set(true);
    this.error.set('');
    try {
      await this.api.requestPasswordReset(address);
      this.sentTo.set(address);
      return true;
    } catch (e) {
      this.error.set(toAppError(e).message);
      return false;
    } finally {
      this.busy.set(false);
    }
  }
}
