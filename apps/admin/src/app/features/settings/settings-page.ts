import { Component, computed, effect, inject, input } from '@angular/core';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { PricingStore } from '../pricing/data/pricing-store';
import { ArenaSettings } from './components/arena-settings';
import { BillingSettings } from './components/billing-settings';
import { SessionSettings } from './components/session-settings';

type Section = 'arena' | 'billing' | 'sessions';

const SECTIONS: readonly { key: Section; icon: string; title: string; sub: string }[] = [
  { key: 'arena', icon: 'storefront', title: 'Arena', sub: 'Name, area, hours' },
  { key: 'billing', icon: 'payments', title: 'Billing', sub: 'GST, invoices, payment, discounts' },
  { key: 'sessions', icon: 'timer', title: 'Sessions', sub: 'Time options and warnings' },
];

/**
 * Settings (design: `if (p === 'settings')`): three groups of arena settings. The selected
 * group is in the URL (`?id=billing`); on a wide screen Arena is shown when none is chosen.
 */
@Component({
  selector: 'app-settings-page',
  imports: [ListDetail, ListPaneHeader, ListRow, ArenaSettings, BillingSettings, SessionSettings],
  template: `
    <app-list-detail
      listLabel="Settings"
      detailLabel="Settings"
      [open]="!!selected()"
      (closed)="close()"
    >
      <ng-container list>
        <app-list-pane-header title="Settings" />
        <div class="flex min-h-0 flex-1 flex-col overflow-y-auto p-2">
          <ul class="flex flex-col gap-0.5" aria-label="Settings">
            @for (s of sections; track s.key) {
              <li>
                <app-list-row
                  [title]="s.title"
                  [subtitle]="s.sub"
                  [icon]="s.icon"
                  [selected]="s.key === selected()"
                  [queryParams]="{ id: s.key }"
                />
              </li>
            }
          </ul>
        </div>
      </ng-container>
      <ng-container detail>
        @switch (selected()) {
          @case ('arena') {
            <app-arena-settings (closed)="close()" />
          }
          @case ('billing') {
            <app-billing-settings (closed)="close()" />
          }
          @case ('sessions') {
            <app-session-settings (closed)="close()" />
          }
        }
      </ng-container>
    </app-list-detail>
  `,
})
export class SettingsPage {
  private readonly pricing = inject(PricingStore);
  private readonly arena = inject(ArenaContext);
  private readonly layout = inject(Layout);
  private readonly router = inject(Router);

  /** `?id=` — arena | billing | sessions. */
  readonly id = input<string>();

  protected readonly sections = SECTIONS;
  protected readonly selected = computed<Section | undefined>(() => {
    const id = this.id();
    const known = SECTIONS.find((s) => s.key === id)?.key;
    if (known) return known;
    return this.layout.wideDetail() ? 'arena' : undefined;
  });

  constructor() {
    // Opening hours come with the price list.
    effect(() => {
      if (this.arena.current().id) void this.pricing.load();
    });
  }

  protected close(): void {
    void this.router.navigate([], { queryParams: { id: null }, queryParamsHandling: 'merge' });
  }
}
