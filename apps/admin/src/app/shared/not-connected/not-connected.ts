import { Component } from '@angular/core';

/**
 * Marks part of a designed screen that the backend cannot store or report yet: the controls
 * beside it are shown as designed but disabled. Project a one-line reason.
 */
@Component({
  selector: 'app-not-connected',
  host: { class: 'flex flex-wrap items-center gap-2', role: 'note' },
  template: `
    <span
      class="inline-flex h-6 flex-none items-center gap-1 rounded-chip bg-warning-soft pr-2.5 pl-2 text-xs leading-none font-medium whitespace-nowrap text-warning"
    >
      <span class="icon text-[14px]" aria-hidden="true">link_off</span>Not connected yet
    </span>
    <span class="min-w-0 flex-1 text-[13px] leading-[1.4] text-muted"><ng-content /></span>
  `,
})
export class NotConnected {}
