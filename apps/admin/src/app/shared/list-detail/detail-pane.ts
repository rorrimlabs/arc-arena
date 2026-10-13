import { Component, inject, input, output } from '@angular/core';
import { MatIconButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { Layout } from '../../core/layout/layout';

/**
 * Detail pane body from the design (`dt.some` block): sticky 64px bar (close when it is an
 * overlay, breadcrumb, projected `[actions]`), then the hero (initials or icon, display title,
 * projected `[chip]` and subtitle, projected `[big]` amount), projected `[stats]`, and the
 * projected sections.
 */
@Component({
  selector: 'app-detail-pane',
  imports: [MatIconButton, MatIcon],
  host: { class: 'flex min-h-full flex-col' },
  template: `
    <div
      class="sticky top-0 z-[5] flex h-topbar flex-none items-center gap-2 border-b border-border bg-bg pr-4 pl-6"
    >
      @if (!layout.wideDetail()) {
        <button
          mat-icon-button
          type="button"
          class="-ml-3"
          aria-label="Close"
          (click)="closed.emit()"
        >
          <mat-icon aria-hidden="true">close</mat-icon>
        </button>
      }
      <span class="min-w-0 flex-1 truncate text-sm leading-none font-medium text-muted">{{
        crumb()
      }}</span>
      <ng-content select="[actions]" />
    </div>
    <div class="flex w-full max-w-[880px] flex-col gap-5 p-6">
      <div class="flex items-center gap-4">
        @if (initials()) {
          <span
            class="grid size-14 flex-none place-items-center rounded-full bg-primary-soft text-[19px] leading-none font-semibold text-primary-text"
            aria-hidden="true"
            >{{ initials() }}</span
          >
        } @else if (icon()) {
          <span
            class="icon grid size-14 flex-none place-items-center rounded-panel bg-surface text-[28px] text-primary-text"
            aria-hidden="true"
            >{{ icon() }}</span
          >
        }
        <div class="flex min-w-0 flex-1 flex-col gap-2">
          <h2 class="font-display text-[26px] leading-[1.1] font-bold [overflow-wrap:anywhere]">
            {{ heading() }}
          </h2>
          <div class="flex flex-wrap items-center gap-2">
            <ng-content select="[chip]" />
            <span class="text-sm leading-[1.3] text-muted">{{ subtitle() }}</span>
          </div>
        </div>
        <ng-content select="[big]" />
      </div>
      <ng-content select="[stats]" />
      <ng-content />
    </div>
  `,
})
export class DetailPane {
  protected readonly layout = inject(Layout);

  readonly crumb = input.required<string>();
  readonly heading = input.required<string>();
  readonly subtitle = input('');
  readonly initials = input('');
  readonly icon = input('');
  readonly closed = output<void>();
}
