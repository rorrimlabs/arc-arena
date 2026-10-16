import { Component, computed, effect, inject, input } from '@angular/core';
import { Router } from '@angular/router';
import { ArenaContext } from '../../core/arena/arena-context';
import { Layout } from '../../core/layout/layout';
import { Capability, VenueStore } from '../../core/venue/venue';
import { ListDetail } from '../../shared/list-detail/list-detail';
import { ListPaneHeader } from '../../shared/list-detail/list-pane-header';
import { ListRow } from '../../shared/list-detail/list-row';
import { PricingStore } from '../pricing/data/pricing-store';
import { AccessoryTypes } from './components/accessory-types';
import { ArenaSettings } from './components/arena-settings';
import { AttendanceSettings } from './components/attendance-settings';
import { BillingRules } from './components/billing-rules';
import { BillingSettings } from './components/billing-settings';
import { SessionSettings } from './components/session-settings';
import { StationTypes } from './components/station-types';
import { WorkHoursSettings } from './components/work-hours-settings';
import { LeaveSettings } from './components/leave-settings';
import { StaffSettings } from './components/staff-settings';
import { OwnersAccess } from './components/owners-access';
import { PayRulesDetail } from '../pay-setup/components/pay-rules-detail';

type Section =
  | 'arena'
  | 'types'
  | 'accessories'
  | 'games'
  | 'billing'
  | 'rules'
  | 'sessions'
  | 'owners'
  | 'staff'
  | 'attendance'
  | 'payrules'
  | 'workhours'
  | 'leave';

const SECTIONS: readonly {
  key: Section;
  icon: string;
  title: string;
  sub: string;
  /** Listed only for venues using this capability (core/venue). */
  requires?: Capability;
  /** Opens its own screen instead of the detail pane. */
  link?: string;
  /** Not listed: opened from Staff › Advanced settings. */
  advanced?: true;
  /** Only for holders of this permission (the owner holds every one). */
  perm?: string;
}[] = [
  { key: 'arena', icon: 'storefront', title: 'Arena', sub: 'Name, area, hours, what you rent out' },
  {
    key: 'types',
    icon: 'category',
    title: 'Station types',
    sub: 'What you sell: consoles, tables, grounds…',
  },
  {
    key: 'accessories',
    icon: 'videogame_asset',
    title: 'Accessory types',
    sub: 'Controller, VR headset, wheel…',
    requires: 'equipment',
  },
  {
    key: 'games',
    icon: 'stadia_controller',
    title: 'Games',
    sub: 'Library, platforms, where each is playable',
    requires: 'games',
    link: '/settings/games',
  },
  { key: 'billing', icon: 'payments', title: 'Billing', sub: 'Payment methods, discount limits' },
  { key: 'rules', icon: 'rule', title: 'Billing rules', sub: 'Rounding, grace, minimum charge' },
  { key: 'sessions', icon: 'timer', title: 'Sessions', sub: 'Time options and warnings' },
  {
    key: 'owners',
    icon: 'admin_panel_settings',
    title: 'Owners & access',
    sub: 'Who owns the venue, inviting an owner',
  },
  { key: 'staff', icon: 'badge', title: 'Staff', sub: 'Working hours, clock-in, leave' },
  {
    key: 'attendance',
    icon: 'location_on',
    title: 'Clock-in and location rules',
    sub: 'Venue location, clock-in rules',
    advanced: true,
  },
  {
    key: 'workhours',
    icon: 'schedule',
    title: 'Attendance calculation rules',
    sub: 'Late grace, half days, extra hours',
    advanced: true,
  },
  {
    key: 'leave',
    icon: 'event_available',
    title: 'Leave rules',
    sub: 'Paid leave a year, half days, backdating',
    advanced: true,
  },
  {
    key: 'payrules',
    icon: 'rule',
    title: 'Payroll calculation rules',
    sub: 'Pay period, deductions, extra-hours rate',
    advanced: true,
    perm: 'payroll',
  },
];

/** Sections that show part of the price list (hours, types, policy, discount limits). */
const NEEDS_PRICING: readonly Section[] = ['arena', 'types', 'billing', 'rules'];

/**
 * Settings: the arena, its station and accessory types, billing, billing rules and sessions.
 * The selected group is in the URL (`?id=billing`); on a wide screen Arena is shown when none is
 * chosen.
 */
@Component({
  selector: 'app-settings-page',
  imports: [
    ListDetail,
    ListPaneHeader,
    ListRow,
    ArenaSettings,
    BillingSettings,
    BillingRules,
    SessionSettings,
    StationTypes,
    AccessoryTypes,
    AttendanceSettings,
    WorkHoursSettings,
    LeaveSettings,
    StaffSettings,
    OwnersAccess,
    PayRulesDetail,
  ],
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
            @for (s of listed(); track s.key) {
              <li>
                <app-list-row
                  [title]="s.title"
                  [subtitle]="s.sub"
                  [icon]="s.icon"
                  [selected]="s.key === selected() || (s.key === 'staff' && isAdvanced())"
                  [link]="s.link ?? []"
                  [queryParams]="s.link ? null : { id: s.key }"
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
          @case ('types') {
            <app-station-types (closed)="close()" />
          }
          @case ('accessories') {
            <app-accessory-types (closed)="close()" />
          }
          @case ('billing') {
            <app-billing-settings (closed)="close()" />
          }
          @case ('rules') {
            <app-billing-rules (closed)="close()" />
          }
          @case ('sessions') {
            <app-session-settings (closed)="close()" />
          }
          @case ('owners') {
            <app-owners-access (closed)="close()" />
          }
          @case ('payrules') {
            <app-pay-rules-detail (closed)="close()" />
          }
          @case ('staff') {
            <app-staff-settings (closed)="close()" />
          }
          @case ('attendance') {
            <app-attendance-settings (closed)="close()" />
          }
          @case ('workhours') {
            <app-work-hours-settings (closed)="close()" />
          }
          @case ('leave') {
            <app-leave-settings (closed)="close()" />
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
  private readonly venue = inject(VenueStore);

  /** `?id=` — arena | types | accessories | billing | rules | sessions | staff | attendance | workhours | leave. */
  readonly id = input<string>();

  protected readonly sections = computed(() => {
    const caps = this.venue.capabilities();
    return SECTIONS.filter(
      (s) =>
        (!s.requires || !caps || caps.has(s.requires)) &&
        (!s.perm || this.arena.hasPerm(s.perm)),
    );
  });
  protected readonly listed = computed(() => this.sections().filter((s) => !s.advanced));
  protected readonly isAdvanced = computed(
    () => !!this.sections().find((s) => s.key === this.selected())?.advanced,
  );
  protected readonly selected = computed<Section | undefined>(() => {
    const id = this.id();
    const known = this.sections().find((s) => s.key === id && !s.link)?.key;
    if (known) return known;
    return this.layout.wideDetail() ? 'arena' : undefined;
  });

  constructor() {
    // Opening hours, types, the policy and discount limits come with the price list: read it
    // only for a section that shows part of it.
    effect(() => {
      const section = this.selected();
      if (this.arena.current().id && section && NEEDS_PRICING.includes(section)) {
        void this.pricing.load();
      }
    });
  }

  /** An advanced staff panel closes back to Staff; the others close the detail. */
  protected close(): void {
    void this.router.navigate([], {
      queryParams: { id: this.isAdvanced() ? 'staff' : null },
      queryParamsHandling: 'merge',
    });
  }
}
