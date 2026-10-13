import { Component, input } from '@angular/core';

/** `age16` / `age18`: the design's age badges (`--bd-16`, `--bd-18`). */
export type PillTone = 'primary' | 'info' | 'warning' | 'danger' | 'success' | 'age16' | 'age18';

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
    '[class.bg-bd-16-bg]': "tone() === 'age16'",
    '[class.text-bd-16]': "tone() === 'age16'",
    '[class.bg-bd-18-bg]': "tone() === 'age18'",
    '[class.text-bd-18]': "tone() === 'age18'",
  },
  template: '<ng-content />',
})
export class StatusPill {
  readonly tone = input<PillTone>('info');
}
