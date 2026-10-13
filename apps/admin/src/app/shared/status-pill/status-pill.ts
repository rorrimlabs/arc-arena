import { Component, input } from '@angular/core';

export type PillTone = 'primary' | 'info' | 'warning' | 'danger' | 'success';

/** The design's 24px status pill (`pill(bg, c)`): soft background, strong text. */
@Component({
  selector: 'app-status-pill',
  host: {
    class:
      'inline-flex h-6 items-center rounded-chip px-2.5 text-xs leading-none font-medium whitespace-nowrap',
    '[class.bg-primary-soft]': "tone() === 'primary'",
    '[class.text-primary-text]': "tone() === 'primary'",
    '[class.bg-info-soft]': "tone() === 'info'",
    '[class.text-muted]': "tone() === 'info'",
    '[class.bg-warning-soft]': "tone() === 'warning'",
    '[class.text-warning]': "tone() === 'warning'",
    '[class.bg-danger-soft]': "tone() === 'danger'",
    '[class.text-danger]': "tone() === 'danger'",
    '[class.bg-success-soft]': "tone() === 'success'",
    '[class.text-success]': "tone() === 'success'",
  },
  template: '<ng-content />',
})
export class StatusPill {
  readonly tone = input<PillTone>('info');
}
