import { Component, input } from '@angular/core';

/**
 * A label / value row inside a detail section (design: `F.row`): muted label left, tabular value
 * right, baseline aligned. `strong` is the bill total style (700 16px).
 */
@Component({
  selector: 'app-detail-row',
  host: { class: 'flex items-baseline justify-between gap-4 text-sm leading-[1.3]' },
  template: `
    <span class="text-muted">{{ label() }}</span>
    <span
      class="text-right tabular-nums"
      [class.font-medium]="!strong()"
      [class.text-base]="strong()"
      [class.leading-none]="strong()"
      [class.font-bold]="strong()"
      >{{ value() }}</span
    >
  `,
})
export class DetailRow {
  readonly label = input.required<string>();
  readonly value = input.required<string>();
  readonly strong = input(false);
}
