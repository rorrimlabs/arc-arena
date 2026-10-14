import { Component, computed, inject, input } from '@angular/core';
import { MatButton } from '@angular/material/button';
import { RouterLink } from '@angular/router';
import { FloorStore } from '../../../core/floor/floor-store';
import { FLOOR_STATE_LABEL, FloorState, liveStations } from '../../../core/floor/floor.models';
import { Layout } from '../../../core/layout/layout';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { formatTime } from '../../../shared/time/ist';
import { PricingStore } from '../../pricing/data/pricing-store';
import { Bill, billState } from '../../sales/data/sale.models';
import { stationIcon } from '../../stations/data/station-view';
import { minutesLeft } from '../../../core/floor/floor.models';

/** Legend states; "paused" is in the design's legend, though the floor has no pause yet. */
type DotState = FloorState | 'paused';

const DOT: Readonly<Record<DotState, string>> = {
  playing: 'bg-primary',
  paused: 'bg-warning',
  free: 'bg-border-strong',
  oos: 'bg-danger',
};

/**
 * Design: the Overview's Live aside. Stations in use with a dot per station, the sessions ending
 * soonest (→ Stations) and today's latest bills (→ Sales). Beside the page on a wide screen,
 * under it otherwise.
 */
@Component({
  selector: 'app-live-pane',
  imports: [MatButton, RouterLink],
  host: {
    class: 'flex flex-col bg-surface-sunken',
    '[class.w-[340px]]': 'layout.wideDetail()',
    '[class.flex-none]': 'layout.wideDetail()',
    '[class.sticky]': 'layout.wideDetail()',
    '[class.top-0]': 'layout.wideDetail()',
    '[class.h-dvh]': 'layout.wideDetail()',
    '[class.overflow-y-auto]': 'layout.wideDetail()',
    '[class.border-l]': 'layout.wideDetail()',
    '[class.w-full]': '!layout.wideDetail()',
    '[class.border-t]': '!layout.wideDetail()',
    '[class.border-border]': 'true',
    role: 'complementary',
    'aria-labelledby': 'live-heading',
  },
  template: `
    <div
      class="sticky top-0 z-[5] flex h-topbar flex-none items-center gap-2.5 border-b border-border bg-surface-sunken px-5"
    >
      <span
        class="size-2 rounded-full bg-primary ring-4 ring-primary-soft"
        aria-hidden="true"
      ></span>
      <h2 id="live-heading" class="flex-1 text-base leading-none font-semibold">Live</h2>
      <a mat-button class="arena-link" routerLink="/stations">Stations</a>
    </div>
    <div class="flex flex-col gap-5 p-5">
      <div class="flex flex-col gap-3">
        <p class="flex items-baseline gap-2">
          <span class="font-display text-[30px] leading-none font-bold"
            >{{ inUse() }} of {{ live().length }}</span
          >
          <span class="text-sm leading-none text-muted">stations in use</span>
        </p>
        <ul class="flex flex-wrap gap-1" aria-label="Stations">
          @for (l of live(); track l.station.id) {
            <li
              class="size-[18px] rounded-[4px]"
              [class]="dot(l.state)"
              [title]="l.station.name + ' · ' + label(l.state)"
              [attr.aria-label]="l.station.name + ', ' + label(l.state)"
            ></li>
          }
        </ul>
        <div class="flex flex-wrap gap-3" aria-hidden="true">
          @for (s of legend; track s) {
            <span class="flex items-center gap-1.5 text-xs leading-none text-muted">
              <span class="size-2.5 rounded-[3px]" [class]="dot(s)"></span>{{ label(s) }}
            </span>
          }
        </div>
      </div>

      <section class="flex flex-col gap-0.5" aria-labelledby="ending-heading">
        <h3 id="ending-heading" class="pb-2 text-[13px] leading-none font-semibold text-muted">
          Ending soon
        </h3>
        @for (e of ending(); track e.id) {
          <a
            routerLink="/stations"
            [queryParams]="{ id: e.id }"
            class="-mx-2 flex min-h-12 items-center gap-3 rounded-chip px-2 text-fg no-underline hover:bg-info-soft hover:text-fg"
          >
            <span class="icon text-xl text-muted" aria-hidden="true">{{ e.icon }}</span>
            <span class="flex min-w-0 flex-1 flex-col gap-0.75">
              <span class="text-sm leading-[1.2] font-semibold">{{ e.name }}</span>
              <span class="truncate text-xs leading-[1.2] text-muted">{{ e.game }}</span>
            </span>
            <span
              class="text-sm leading-none font-semibold tabular-nums"
              [class.text-warning]="e.left <= 10"
              >{{ e.left }}m</span
            >
          </a>
        } @empty {
          <p class="text-[13px] text-muted">Nothing running.</p>
        }
      </section>

      <section class="flex flex-col gap-0.5" aria-labelledby="latest-heading">
        <h3 id="latest-heading" class="pb-2 text-[13px] leading-none font-semibold text-muted">
          Latest bills
        </h3>
        @for (b of latest(); track b.id) {
          <a
            routerLink="/sales"
            [queryParams]="{ id: b.id }"
            class="-mx-2 flex min-h-13 items-center gap-3 rounded-chip px-2 text-fg no-underline hover:bg-info-soft hover:text-fg"
          >
            <span class="flex min-w-0 flex-1 flex-col gap-0.75">
              <span class="truncate text-sm leading-[1.2] font-medium">{{ b.customer }}</span>
              <span class="truncate text-xs leading-[1.2] text-muted">{{ meta(b) }}</span>
            </span>
            <span class="flex flex-col items-end gap-0.75">
              <span class="text-sm leading-none font-semibold tabular-nums">{{ amount(b) }}</span>
              <span class="text-xs leading-none text-muted">{{ state(b) }}</span>
            </span>
          </a>
        } @empty {
          <p class="text-[13px] text-muted">No bills yet today.</p>
        }
      </section>
    </div>
  `,
})
export class LivePane {
  protected readonly layout = inject(Layout);
  private readonly floor = inject(FloorStore);
  private readonly pricing = inject(PricingStore);

  /** Today's closed bills, newest first. */
  readonly today = input.required<readonly Bill[]>();
  readonly now = input.required<Date>();

  protected readonly legend: readonly DotState[] = ['playing', 'paused', 'free', 'oos'];
  protected readonly live = computed(() => liveStations(this.floor.stations(), this.floor.live()));
  protected readonly inUse = computed(
    () => this.live().filter((l) => l.state === 'playing').length,
  );
  protected readonly ending = computed(() =>
    this.live()
      .filter((l) => l.state === 'playing' && l.endsAt)
      .sort((a, b) => (a.endsAt ?? '').localeCompare(b.endsAt ?? ''))
      .slice(0, 5)
      .map((l) => ({
        id: l.station.id,
        name: l.station.name,
        icon: stationIcon(l.station.activityCodes, this.pricing.types()),
        game: (l.gameId && this.floor.gameById().get(l.gameId)?.name) || 'Playing',
        left: minutesLeft(l.endsAt as string, this.now()),
      })),
  );
  protected readonly latest = computed(() => this.today().slice(0, 8));

  protected dot(state: DotState): string {
    return DOT[state];
  }

  protected label(state: DotState): string {
    return state === 'paused' ? 'Paused' : FLOOR_STATE_LABEL[state];
  }

  protected meta(b: Bill): string {
    return [formatTime(b.at), b.stations.join(', '), b.ref].filter(Boolean).join(' · ');
  }

  protected amount(b: Bill): string {
    return b.voided ? '—' : formatRupees(b.billedPaise ?? 0);
  }

  protected state(b: Bill): string {
    return billState(b).label;
  }
}
