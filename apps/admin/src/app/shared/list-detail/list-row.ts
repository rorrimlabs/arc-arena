import { Component, input } from '@angular/core';
import { Params, QueryParamsHandling, RouterLink } from '@angular/router';

/**
 * One row of a list pane (design: `item()`): 40px initials or icon tile, bold title over a
 * muted subtitle, projected trailing content (value, status pill). Selected rows are tinted
 * primary-soft with a hairline ring. Selecting is a link so it lands in the URL and history.
 */
@Component({
  selector: 'app-list-row',
  imports: [RouterLink],
  template: `
    <a
      [routerLink]="link()"
      [queryParams]="queryParams()"
      [queryParamsHandling]="queryParamsHandling()"
      [attr.aria-current]="selected() ? 'true' : null"
      class="flex min-h-16 w-full items-center gap-3 rounded-card px-3 py-2.5 text-fg no-underline hover:bg-info-soft hover:text-fg"
      [class.bg-primary-soft]="selected()"
      [class.ring-1]="selected()"
      [class.ring-inset]="selected()"
      [class.ring-primary/30]="selected()"
    >
      @if (initials()) {
        <span
          class="grid size-10 flex-none place-items-center rounded-full bg-info-soft text-[13px] leading-none font-semibold"
          aria-hidden="true"
          >{{ initials() }}</span
        >
      } @else if (icon()) {
        <span
          class="icon grid size-10 flex-none place-items-center rounded-card bg-surface text-[22px] text-muted"
          aria-hidden="true"
          >{{ icon() }}</span
        >
      }
      <span class="flex min-w-0 flex-1 flex-col gap-1">
        <span class="truncate text-sm leading-[1.25] font-semibold">{{ title() }}</span>
        <span class="truncate text-[12.5px] leading-[1.3] text-muted">{{ subtitle() }}</span>
      </span>
      <span class="flex flex-none flex-col items-end gap-1.25"><ng-content /></span>
    </a>
  `,
})
export class ListRow {
  readonly title = input.required<string>();
  readonly subtitle = input('');
  readonly initials = input('');
  readonly icon = input('');
  readonly selected = input(false);
  /** Router link of the row (default: the current page, selection in the query params). */
  readonly link = input<string | readonly unknown[]>([]);
  readonly queryParams = input<Params | null>(null);
  /** 'merge' keeps the page's other query params (e.g. list filters) when selecting. */
  readonly queryParamsHandling = input<QueryParamsHandling>('');
}
