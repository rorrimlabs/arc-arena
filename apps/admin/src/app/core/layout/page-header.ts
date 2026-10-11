import { Component, inject, input } from '@angular/core';
import { Layout } from './layout';

/**
 * The 64px page top bar from the design: menu button (compact only), page title, and any
 * projected actions on the right.
 */
@Component({
  selector: 'app-page-header',
  host: {
    class:
      'sticky top-0 z-20 flex h-topbar flex-none items-center gap-2 border-b border-border bg-bg pr-4 pl-5',
  },
  template: `
    @if (layout.compact()) {
      <button
        type="button"
        class="-ml-2 grid size-11 flex-none place-items-center rounded-full hover:bg-info-soft"
        aria-label="Menu"
        aria-controls="app-nav"
        [attr.aria-expanded]="layout.navOpen()"
        (click)="layout.toggleNav()"
      >
        <span class="icon text-2xl leading-none" aria-hidden="true">menu</span>
      </button>
    }
    <h1 class="min-w-0 flex-1 truncate text-xl leading-[1.2] font-semibold">{{ title() }}</h1>
    <ng-content />
  `,
})
export class PageHeader {
  readonly title = input.required<string>();
  protected readonly layout = inject(Layout);
}
