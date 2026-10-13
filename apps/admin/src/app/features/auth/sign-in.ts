import { Component, inject, signal } from '@angular/core';
import { FormField, email, form, required } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { Router, RouterLink } from '@angular/router';
import { toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { AuthCard } from './auth-card';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

/** Owner sign in (design: `signedOut` block). Staff sign in on the floor app instead. */
@Component({
  selector: 'app-sign-in',
  providers: [MATERIAL_DEFAULTS],
  imports: [AuthCard, FormField, MatFormField, MatLabel, MatInput, MatButton, RouterLink],
  template: `
    <app-auth-card
      heading="Owner sign in"
      subtitle="Sales, stations, pricing and staff for your arenas."
    >
      <form class="flex flex-col gap-5" novalidate (submit)="submit($event)">
        <mat-form-field appearance="outline" subscriptSizing="dynamic">
          <mat-label>Email</mat-label>
          <input matInput type="email" autocomplete="email" [formField]="f.email" />
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
          <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
        }
        <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">Sign in</button>
      </form>
      <p class="text-sm text-muted">
        New to ArenaOS? <a routerLink="/register">Create an account</a>
      </p>
    </app-auth-card>
  `,
})
export class SignIn {
  private readonly session = inject(Session);
  private readonly router = inject(Router);

  protected readonly model = signal({ email: '', password: '' });
  protected readonly f = form(this.model, (p) => {
    required(p.email, { message: 'Enter your email' });
    email(p.email, { message: 'Enter a valid email' });
    required(p.password, { message: 'Enter your password' });
  });
  protected readonly error = signal('');
  protected readonly busy = signal(false);

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
      await this.session.signIn(address.trim(), password);
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
}
