import { Component, inject, input } from '@angular/core';
import { MatIconButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { Layout } from '../../core/layout/layout';

/**
 * Top of a list pane (design: list header block): 64px title row with the menu button when
 * compact and any projected actions (e.g. the Add button), then projected search / chips /
 * summary rows, all above one hairline.
 */
@Component({
  selector: 'app-list-pane-header',
  imports: [MatIconButton, MatIcon],
  host: { class: 'flex flex-none flex-col gap-3 border-b border-border px-4 pb-3' },
  template: `
    <div class="flex h-topbar items-center gap-2">
      @if (layout.compact()) {
        <button
          mat-icon-button
          type="button"
          class="-ml-1.5"
          aria-label="Menu"
          aria-controls="app-nav"
          [attr.aria-expanded]="layout.navOpen()"
          (click)="layout.toggleNav()"
        >
          <mat-icon aria-hidden="true">menu</mat-icon>
        </button>
      }
      <h1 class="min-w-0 flex-1 truncate text-xl leading-[1.2] font-semibold">{{ title() }}</h1>
      <ng-content select="[actions]" />
    </div>
    <ng-content />
  `,
})
export class ListPaneHeader {
  readonly title = input.required<string>();
  protected readonly layout = inject(Layout);
}
