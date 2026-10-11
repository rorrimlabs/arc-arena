import { Component, input } from '@angular/core';
import { PageHeader } from '../core/layout/page-header';

/** Stand-in for a screen that has not been built yet (build it with `/design-build <screen>`). */
@Component({
  selector: 'app-screen-placeholder',
  imports: [PageHeader],
  template: `
    <app-page-header [title]="heading()" />
    <p class="p-5 text-sm text-muted">This screen hasn't been built yet.</p>
  `,
})
export class ScreenPlaceholder {
  /** Bound from the route's `data.heading`. */
  readonly heading = input.required<string>();
}
