import { PillTone } from '../../../shared/status-pill/status-pill';
import { ArenaUser, UserStatus, userStatus } from '../data/user.models';

/** "Priya Nair" → "PN" (the design's `initials`). */
export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
}

const TONES: Readonly<Record<UserStatus, PillTone>> = {
  Owner: 'primary',
  Off: 'danger',
  Invited: 'warning',
  Active: 'info',
};

/** The design's `stt(u)`: status label and pill colours. */
export function statusTone(u: ArenaUser): { label: UserStatus; tone: PillTone } {
  const label = userStatus(u);
  return { label, tone: TONES[label] };
}
