import { Component, input } from '@angular/core';
import { PageHeader } from '../core/layout/page-header';
import { ListDetail } from './list-detail/list-detail';
import { ListPaneHeader } from './list-detail/list-pane-header';

/**
 * Stand-in for a screen that has not been built yet.
 * It shows the screen's empty frame: `list` is the list/detail frame,
 * `page` a plain page under the top bar (Overview).
 */
@Component({
  selector: 'app-screen-placeholder',
  imports: [PageHeader, ListDetail, ListPaneHeader],
  host: { class: 'contents' },
  template: `
    @if (kind() === 'list') {
      <app-list-detail [listLabel]="heading()" [open]="false" emptyText="Nothing to show yet">
        <ng-container list>
          <app-list-pane-header [title]="heading()" />
          <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
            <p class="px-4 py-12 text-center text-sm leading-[1.4] text-muted">{{ notBuilt }}</p>
          </div>
        </ng-container>
      </app-list-detail>
    } @else {
      <app-page-header [title]="heading()" />
      <p class="p-5 text-sm text-muted">{{ notBuilt }}</p>
    }
  `,
})
export class ScreenPlaceholder {
  /** Bound from the route's `data.heading`. */
  readonly heading = input.required<string>();
  /** Bound from the route's `data.kind`. */
  readonly kind = input<'list' | 'page'>('page');

  protected readonly notBuilt = "This screen hasn't been built yet.";
}
