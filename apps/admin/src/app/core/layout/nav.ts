import { Capability } from '../venue/venue';

/**
 * Side-nav destinations. Accessories (controllers, headsets…) live inside Stations, and station
 * and accessory types inside Settings, so neither has its own entry.
 */
export interface NavItem {
  /** Top-level route path. */
  readonly path: string;
  readonly label: string;
  /** Material Symbols name. */
  readonly icon: string;
  /** Shown (and routable) only for venues using this capability (core/venue). */
  readonly requires?: Capability;
  /** Labelled with the venue's own noun ("Tables", "Grounds") instead of `label`. */
  readonly venueNoun?: true;
}

export interface NavGroup {
  readonly heading: string;
  readonly items: readonly NavItem[];
}

export const NAV_GROUPS: readonly NavGroup[] = [
  {
    heading: 'Reports',
    items: [
      { path: 'overview', label: 'Overview', icon: 'dashboard' },
      { path: 'sales', label: 'Sales', icon: 'receipt_long' },
    ],
  },
  {
    heading: 'Configure',
    items: [
      { path: 'stations', label: 'Stations', icon: 'grid_view', venueNoun: true },
      { path: 'pricing', label: 'Pricing', icon: 'sell' },
      { path: 'games', label: 'Games', icon: 'stadia_controller', requires: 'games' },
    ],
  },
  {
    heading: 'People',
    items: [
      { path: 'members', label: 'Members', icon: 'group' },
      { path: 'users', label: 'Users', icon: 'manage_accounts' },
    ],
  },
  { heading: 'Arena', items: [{ path: 'settings', label: 'Settings', icon: 'settings' }] },
];

export const NAV_ITEMS: readonly NavItem[] = NAV_GROUPS.flatMap((group) => group.items);
