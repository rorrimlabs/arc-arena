import { Component, computed, inject, input, output, resource } from '@angular/core';
import { FloorStore, PLAY_DAYS } from '../../../core/floor/floor-store';
import { MemberRow, initials } from '../../../core/floor/floor.models';
import { DetailPane } from '../../../shared/list-detail/detail-pane';
import { DetailRow } from '../../../shared/list-detail/detail-row';
import { DetailSection } from '../../../shared/list-detail/detail-section';
import { LineRow } from '../../../shared/list-detail/line-row';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { NotConnected } from '../../../shared/not-connected/not-connected';
import { StatTile } from '../../../shared/stat-tile/stat-tile';
import { StatusPill } from '../../../shared/status-pill/status-pill';
import { formatIsoDate, formatMinutes } from '../../../shared/time/ist';
import { activityLines } from '../../stations/data/station-view';
import { daysAgo, maskPhone } from '../data/member-view';

/**
 * One member, read-only: visits, play, spend (from the list's row), and favourite games and
 * recent bills (read when the member is opened). Age comes from the birth year given at registration on the floor app; plans
 * await the owner's decision (docs/OWNER_CONFIRMATION.md) and stay not connected.
 */
@Component({
  selector: 'app-member-detail',
  imports: [DetailPane, DetailSection, DetailRow, LineRow, NotConnected, StatTile, StatusPill],
  template: `
    @let m = member();
    <app-detail-pane
      [crumb]="'Members / ' + m.name"
      [initials]="initials(m.name)"
      [heading]="m.name"
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
        @if (activity.error()) {
          <p role="alert" class="text-[13px] leading-[1.45] text-danger">
            Play history couldn't load.
          </p>
        } @else if (!activity.hasValue()) {
          <p class="text-[13px] leading-[1.45] text-muted">Loading…</p>
        } @else {
          @for (g of favourites(); track g.name) {
            <app-detail-row [label]="g.name" [value]="minutes(g.minutes)" />
          } @empty {
            <p class="text-[13px] leading-[1.45] text-muted">No sessions yet.</p>
          }
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
          @if (activity.hasValue()) {
            <p class="text-[13px] leading-[1.45] text-muted">No bills yet.</p>
          }
        }
      </app-detail-section>

      <app-detail-section heading="Age and plan">
        <app-detail-row label="Age" [value]="ageLine()" [muted]="!m.birthYear" />
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

  readonly member = input.required<MemberRow>();
  readonly now = input.required<Date>();
  readonly closed = output<void>();

  protected readonly days = PLAY_DAYS;
  protected readonly initials = initials;
  protected readonly rupees = formatRupees;
  protected readonly minutes = formatMinutes;
  protected readonly phone = computed(() => maskPhone(this.member().phone));
  /** Age from the birth year alone (may be one too high before the birthday). */
  private readonly age = computed(() => {
    const born = this.member().birthYear;
    return born == null ? null : Number(formatIsoDate(this.now()).slice(0, 4)) - born;
  });
  protected readonly subtitle = computed(() => {
    const age = this.age();
    return age == null ? this.phone() : `${this.phone()} · age ${age}`;
  });
  protected readonly ageLine = computed(() => {
    const age = this.age();
    return age == null ? 'Not given' : `${age} · born ${this.member().birthYear}`;
  });
  protected readonly last = computed(() => daysAgo(this.member().lastVisit, this.now()));
  /** Minutes per game and newest bills, read when the member is opened. */
  protected readonly activity = resource({
    params: () => ({ id: this.member().id, revision: this.floor.revision() }),
    loader: ({ params }) => this.floor.activity({ customerId: params.id }),
  });
  protected readonly favourites = computed(() =>
    this.activity.hasValue() ? this.activity.value().games.slice(0, 3) : [],
  );
  protected readonly bills = computed(() =>
    activityLines(
      this.activity.hasValue() ? this.activity.value().bills : [],
      (b) => [b.station ?? 'Station', b.game].filter(Boolean).join(' · '),
      { gameInSubtitle: false },
    ),
  );
}
