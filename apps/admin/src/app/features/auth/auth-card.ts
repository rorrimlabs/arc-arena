import { Component, input } from '@angular/core';

/**
 * The signed-out card from the design (`signedOut` block): 404 badge, display title, muted
 * subtitle, then the projected form. Shared by sign in, register and create arena.
 */
@Component({
  selector: 'app-auth-card',
  host: { class: 'flex min-h-dvh items-center justify-center bg-bg p-6 text-fg' },
  template: `
    <main
      class="flex w-full max-w-[400px] flex-col gap-5 rounded-card border border-border bg-surface p-8"
    >
      <div
        class="grid size-12 place-items-center rounded-[14px] bg-primary font-display text-[17px] leading-none font-extrabold text-on-primary"
        aria-hidden="true"
      >
        404
      </div>
      <div class="flex flex-col gap-1.5">
        <h1 class="font-display text-[28px] leading-[1.1] font-bold">{{ heading() }}</h1>
        <p class="text-sm leading-[1.4] text-muted">{{ subtitle() }}</p>
      </div>
      <ng-content />
    </main>
  `,
})
export class AuthCard {
  readonly heading = input.required<string>();
  readonly subtitle = input.required<string>();
}
