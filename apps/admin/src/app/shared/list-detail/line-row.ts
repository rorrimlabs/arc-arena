import { Component, input } from '@angular/core';
import { RouterLink } from '@angular/router';

/**
 * A linked two-line row inside a detail section (design: `F.line`): title over a muted
 * subtitle, a tabular value on the right; it opens another screen (a bill, a member).
 */
@Component({
  selector: 'app-line-row',
  imports: [RouterLink],
  host: { class: 'block -mx-2 -my-2' },
  template: `
    <a
      [routerLink]="link()"
      [queryParams]="queryParams()"
      class="flex min-h-11 items-center gap-3 rounded-chip px-2 text-fg no-underline hover:bg-info-soft hover:text-fg"
    >
      <span class="flex min-w-0 flex-1 flex-col gap-0.75">
        <span class="truncate text-sm leading-[1.2] font-medium">{{ title() }}</span>
        <span class="truncate text-xs leading-[1.2] text-muted">{{ subtitle() }}</span>
      </span>
      <span class="flex-none text-sm leading-none font-semibold tabular-nums">{{ value() }}</span>
    </a>
  `,
})
export class LineRow {
  readonly title = input.required<string>();
  readonly subtitle = input('');
  readonly value = input('');
  readonly link = input.required<string | readonly unknown[]>();
  readonly queryParams = input<Record<string, string> | null>(null);
}
