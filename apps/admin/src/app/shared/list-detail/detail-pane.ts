import { NgTemplateOutlet } from '@angular/common';
import { Component, Directive, InjectionToken, inject, input, output } from '@angular/core';
import { MatIconButton } from '@angular/material/button';
import { MatIcon } from '@angular/material/icon';
import { Layout } from '../../core/layout/layout';

/** Provided by DetailTabs: a detail pane inside a tab renders embedded. */
export const EMBEDDED_DETAIL = new InjectionToken<boolean>('EMBEDDED_DETAIL');

/** On a detail component's host: its pane renders embedded (an item opened inside a section). */
@Directive({
  selector: '[appEmbeddedDetail]',
  providers: [{ provide: EMBEDDED_DETAIL, useValue: true }],
})
export class EmbeddedDetail {}

/**
 * Detail pane body from the design (`dt.some` block): sticky 64px bar (close when it is an
 * overlay, breadcrumb, projected `[actions]`), then the hero (initials or icon, display title,
 * projected `[chip]` and subtitle, projected `[big]` amount), projected `[stats]`, the projected
 * sections, and a projected `[footer]` (e.g. the unsaved-changes bar).
 *
 * Embedded (inside DetailTabs): no bar, breadcrumb or hero; a title row (heading, chip,
 * subtitle, `[big]`, `[actions]`) over the stats, sections and footer.
 */
@Component({
  selector: 'app-detail-pane',
  imports: [MatIconButton, MatIcon, NgTemplateOutlet],
  host: { class: 'flex flex-col', '[class.min-h-full]': '!embedded' },
  template: `
    <!-- Projected once each, then placed for the full or the embedded layout. -->
    <ng-template #actions><ng-content select="[actions]" /></ng-template>
    <ng-template #chip><ng-content select="[chip]" /></ng-template>
    <ng-template #big><ng-content select="[big]" /></ng-template>
    <ng-template #body>
      <ng-content select="[stats]" />
      <ng-content />
    </ng-template>
    <ng-template #footer><ng-content select="[footer]" /></ng-template>

    @if (embedded) {
      <div class="flex flex-col gap-5">
        <div class="flex items-center gap-3">
          <div class="flex min-w-0 flex-1 flex-col gap-1">
            <h3 class="text-lg leading-[1.2] font-semibold [overflow-wrap:anywhere]">
              {{ heading() }}
            </h3>
            <div class="flex flex-wrap items-center gap-2">
              <ng-container [ngTemplateOutlet]="chip" />
              <span class="text-sm leading-[1.3] text-muted">{{ subtitle() }}</span>
            </div>
          </div>
          <ng-container [ngTemplateOutlet]="big" />
          <ng-container [ngTemplateOutlet]="actions" />
        </div>
        <ng-container [ngTemplateOutlet]="body" />
      </div>
    } @else {
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
        <ng-container [ngTemplateOutlet]="actions" />
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
              <ng-container [ngTemplateOutlet]="chip" />
              <span class="text-sm leading-[1.3] text-muted">{{ subtitle() }}</span>
            </div>
          </div>
          <ng-container [ngTemplateOutlet]="big" />
        </div>
        <ng-container [ngTemplateOutlet]="body" />
      </div>
    }
    <ng-container [ngTemplateOutlet]="footer" />
  `,
})
export class DetailPane {
  protected readonly layout = inject(Layout);
  protected readonly embedded = inject(EMBEDDED_DETAIL, { optional: true }) ?? false;

  readonly crumb = input.required<string>();
  readonly heading = input.required<string>();
  readonly subtitle = input('');
  readonly initials = input('');
  readonly icon = input('');
  readonly closed = output<void>();
}
