import { Component, computed, inject, input, output } from '@angular/core';
import { FloorStore, PLAY_DAYS } from '../../../core/floor/floor-store';
import { initials } from '../../../core/floor/floor.models';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { LineRow } from '../../../shared/list-detail/line-row';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { NotConnected } from '../../../shared/not-connected/not-connected';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatIsoDate, formatMinutes } from '../../../shared/time/ist';
import { billLines } from '../../stations/data/station-view';
import { MemberSummary, daysAgo, maskPhone } from '../data/member-view';

/**
 * Design: `if (p === 'members')` detail, read-only: visits, play, spend, favourite games and
 * recent bills. Age comes from the birth year given at registration on the floor app; plans
 * await the owner's decision (docs/OWNER_CONFIRMATION.md) and stay not connected.
 */
@Component({
  selector: 'app-member-detail',
  imports: [DetailPane, DetailSection, DetailRow, LineRow, NotConnected, StatTile, StatusPill],
  template: `
    @let m = member();
    <app-detail-pane
      [crumb]="'Members / ' + m.customer.name"
      [initials]="initials(m.customer.name)"
      [heading]="m.customer.name"
      [subtitle]="subtitle()"
      (closed)="closed.emit()"
    >
      <app-status-pill chip tone="info" title="Membership plans aren't stored yet"
        >Plan —</app-status-pill
      >
      <div stats class="grid grid-cols-[repeat(auto-fit,minmax(130px,1fr))] gap-3">
        <app-stat-tile [label]="'Visits · ' + days + ' days'" [value]="m.visits.toString()" />
        <app-stat-tile [label]="'Hours played · ' + days + ' days'" [value]="minutes(m.minutes)" />
        <app-stat-tile label="Spent · 30 days" [value]="rupees(m.spent30Paise)" />
        <app-stat-tile label="Last visit" [value]="last()" />
      </div>

      <app-detail-section heading="Favourite games">
        @for (g of favourites(); track g.name) {
          <app-detail-row [label]="g.name" [value]="minutes(g.minutes)" />
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">No sessions yet.</p>
        }
      </app-detail-section>

      <app-detail-section heading="Recent bills">
        @for (b of bills(); track b.billId) {
          <app-line-row
            [title]="b.title"
            [subtitle]="b.subtitle"
            [value]="b.value"
            link="/sales"
            [queryParams]="{ id: b.billId }"
          />
        } @empty {
          <p class="text-[13px] leading-[1.45] text-muted">No bills yet.</p>
        }
      </app-detail-section>

      <app-detail-section heading="Age and plan">
        <app-detail-row label="Age" [value]="ageLine()" [muted]="!m.customer.birthYear" />
        <app-detail-row label="Plan" value="—" [muted]="true" />
        <app-not-connected>Membership plans aren't set up yet.</app-not-connected>
      </app-detail-section>

      <app-detail-section>
        <p class="text-[13px] leading-[1.45] text-muted">
          Members register on the floor app. Phone numbers are masked here.
        </p>
      </app-detail-section>
    </app-detail-pane>
  `,
})
export class MemberDetail {
  private readonly floor = inject(FloorStore);

  readonly member = input.required<MemberSummary>();
  readonly now = input.required<Date>();
  readonly closed = output<void>();

  protected readonly days = PLAY_DAYS;
  protected readonly initials = initials;
  protected readonly rupees = formatRupees;
  protected readonly minutes = formatMinutes;
  protected readonly phone = computed(() => maskPhone(this.member().customer.phone));
  /** Age from the birth year alone (may be one too high before the birthday). */
  private readonly age = computed(() => {
    const born = this.member().customer.birthYear;
    return born == null ? null : Number(formatIsoDate(this.now()).slice(0, 4)) - born;
  });
  protected readonly subtitle = computed(() => {
    const age = this.age();
    return age == null ? this.phone() : `${this.phone()} · age ${age}`;
  });
  protected readonly ageLine = computed(() => {
    const age = this.age();
    return age == null ? 'Not given' : `${age} · born ${this.member().customer.birthYear}`;
  });
  protected readonly last = computed(() => daysAgo(this.member().lastVisit, this.now()));
  protected readonly favourites = computed(() =>
    [...this.member().games]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([id, minutes]) => ({
        name: this.floor.gameById().get(id)?.name ?? 'Unknown game',
        minutes,
      })),
  );
  protected readonly bills = computed(() => {
    const games = this.floor.gameById();
    const stations = this.floor.stationById();
    return billLines(
      this.floor.plays().filter((p) => p.customerId === this.member().customer.id),
      new Map(this.floor.visits().map((v) => [v.id, v])),
      this.floor.customerById(),
      games,
      (p, game) =>
        [stations.get(p.resourceId)?.name ?? 'Station', game].filter(Boolean).join(' · '),
      { gameInSubtitle: false },
    );
  });
}
