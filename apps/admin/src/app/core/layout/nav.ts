/** Side-nav destinations, in the design's order (`const NAV` in design/admin.html). */
export interface NavItem {
  /** Top-level route path. */
  readonly path: string;
  readonly label: string;
  /** Material Symbols name. */
  readonly icon: string;
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
      { path: 'stations', label: 'Stations', icon: 'sports_esports' },
      { path: 'pricing', label: 'Pricing', icon: 'sell' },
      { path: 'games', label: 'Games', icon: 'stadia_controller' },
    ],
  },
  {
    heading: 'People',
    items: [
      { path: 'members', label: 'Members', icon: 'group' },
      { path: 'staff', label: 'Staff', icon: 'badge' },
    ],
  },
  { heading: 'Arena', items: [{ path: 'settings', label: 'Settings', icon: 'settings' }] },
];

export const NAV_ITEMS: readonly NavItem[] = NAV_GROUPS.flatMap((group) => group.items);
