import { PillTone } from '../../../shared/status-pill/status-pill';
import { CouponState } from '../data/pricing.models';

/** How a preset or coupon's state reads in a pill. */
export const COUPON_STATE: Readonly<Record<CouponState, { label: string; tone: PillTone }>> = {
  active: { label: 'Active', tone: 'primary' },
  scheduled: { label: 'Scheduled', tone: 'info' },
  expired: { label: 'Expired', tone: 'warning' },
  used_up: { label: 'Used up', tone: 'warning' },
  off: { label: 'Off', tone: 'info' },
};
