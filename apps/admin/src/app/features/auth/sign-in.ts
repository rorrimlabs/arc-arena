import { Component, inject } from '@angular/core';
import { Session } from '../../core/auth/session';

/**
 * Minimal sign-in so signing out has somewhere to land. The design's full screen (email and
 * password fields) is built with `/design-build sign-in`.
 */
@Component({
  selector: 'app-sign-in',
  host: { class: 'flex min-h-dvh items-center justify-center bg-bg p-6 text-fg' },
  template: `
    <div
      class="flex w-full max-w-[400px] flex-col gap-5 rounded-card border border-border bg-surface p-8"
    >
      <div
        class="grid size-12 place-items-center rounded-[14px] bg-primary font-display text-[17px] leading-none font-extrabold text-on-primary"
        aria-hidden="true"
      >
        404
      </div>
      <div class="flex flex-col gap-2">
        <h1 class="text-h2">Owner sign in</h1>
        <p class="text-sm text-muted">Sales, stations, pricing and staff for your arenas.</p>
      </div>
      <button
        type="button"
        class="h-12 rounded-full bg-primary text-[15px] leading-none font-medium text-on-primary hover:bg-primary-hi"
        (click)="session.signIn()"
      >
        Sign in
      </button>
    </div>
  `,
})
export class SignIn {
  protected readonly session = inject(Session);
}
