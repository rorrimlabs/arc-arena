import { Component, input, output } from '@angular/core';
import { MatButton } from '@angular/material/button';

/**
 * The design's unsaved-changes bar (`dt.dirty`): a raised pill pinned 16px above the bottom of
 * the detail pane with Discard and Save. Project it into a detail pane's `[footer]`.
 */
@Component({
  selector: 'app-unsaved-bar',
  imports: [MatButton],
  host: {
    class:
      'sticky bottom-4 z-[5] mx-6 mt-auto mb-4 flex items-center gap-2 self-end rounded-[28px] bg-surface-raised py-2 pr-2 pl-5 shadow-raised',
    role: 'region',
    'aria-label': 'Unsaved changes',
  },
  template: `
    <span class="pr-2 text-sm leading-none text-muted">Unsaved changes</span>
    <button mat-button type="button" [disabled]="busy()" (click)="discard.emit()">Discard</button>
    <button mat-flat-button type="button" [disabled]="busy()" (click)="save.emit()">Save</button>
  `,
})
export class UnsavedBar {
  readonly busy = input(false);
  readonly discard = output<void>();
  readonly save = output<void>();
}
