import { Component, inject, input, linkedSignal, signal } from '@angular/core';
import { FormField, email, form, maxLength, required, validate } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatHint, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { Router, RouterLink } from '@angular/router';
import { AuthApi, MIN_PASSWORD, passwordProblem, toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { AuthCard } from './auth-card';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

const CODE_LENGTH = 6;

/**
 * New arena owner: email + password, then the 6-digit code from the confirmation email. A
 * confirmed login continues to create its arena. Staff never register here — their owner
 * creates their login from Staff.
 */
@Component({
  selector: 'app-register',
  providers: [MATERIAL_DEFAULTS],
  imports: [AuthCard, FormField, MatFormField, MatLabel, MatHint, MatInput, MatButton, RouterLink],
  template: `
    @if (currentStep() === 'details') {
      <app-auth-card
        heading="Create your account"
        subtitle="For arena owners. Staff sign in on the floor app with the login you create for them."
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
          <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
            Create account
          </button>
        </form>
        <p class="text-sm text-muted">
          Already have an account? <a routerLink="/sign-in">Sign in</a>
        </p>
      </app-auth-card>
    } @else {
      <app-auth-card
        heading="Check your email"
        [subtitle]="
          'We sent a ' +
          codeLength +
          '-digit code to ' +
          pendingEmail() +
          '. If that email already has an account, no code is sent: sign in instead.'
        "
      >
        <form class="flex flex-col gap-5" novalidate (submit)="verify($event)">
          <mat-form-field appearance="outline" subscriptSizing="dynamic">
            <mat-label>Code</mat-label>
            <input
              matInput
              inputmode="numeric"
              autocomplete="one-time-code"
              [formField]="codeForm.code"
            />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
          @if (info()) {
            <p role="status" class="text-sm leading-[1.3] text-muted">{{ info() }}</p>
          }
          <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
            Confirm
          </button>
          <button
            mat-stroked-button
            type="button"
            class="arena-cta"
            [disabled]="busy()"
            (click)="resend()"
          >
            Resend code
          </button>
        </form>
        <p class="text-sm text-muted"><a routerLink="/sign-in">Back to sign in</a></p>
      </app-auth-card>
    }
  `,
})
export class Register {
  private readonly api = inject(AuthApi);
  private readonly session = inject(Session);
  private readonly router = inject(Router);

  /** `?step=code&email=…` resumes at the code (e.g. after signing in unconfirmed). */
  readonly step = input<string>();
  readonly email = input<string>();

  protected readonly minPassword = MIN_PASSWORD;
  protected readonly codeLength = CODE_LENGTH;
  protected readonly currentStep = linkedSignal(() =>
    this.step() === 'code' && this.email() ? 'code' : 'details',
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

  protected readonly codeModel = signal({ code: '' });
  protected readonly codeForm = form(this.codeModel, (p) => {
    maxLength(p.code, CODE_LENGTH);
    validate(p.code, ({ value }) =>
      new RegExp(`^\\d{${CODE_LENGTH}}$`).test(value().trim())
        ? null
        : { kind: 'code', message: `Enter the ${CODE_LENGTH}-digit code from the email` },
    );
  });

  protected readonly error = signal('');
  protected readonly info = signal('');
  protected readonly busy = signal(false);

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
      this.currentStep.set('code');
    });
  }

  protected async verify(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.codeForm().errorSummary()[0];
    if (first) {
      this.error.set(first.message ?? 'Check the code');
      return;
    }
    await this.run(async () => {
      await this.api.verifySignUp(this.pendingEmail(), this.codeModel().code.trim());
      await this.session.refresh();
      await this.router.navigate(['/create-arena']);
    });
  }

  protected async resend(): Promise<void> {
    await this.run(async () => {
      await this.api.resendCode(this.pendingEmail());
      this.info.set(`Sent a new code to ${this.pendingEmail()}.`);
    });
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
