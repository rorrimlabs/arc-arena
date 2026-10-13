/**
 * Business time is Asia/Kolkata (fixed +05:30, no daylight saving); instants stay UTC and are
 * converted only for display and for the calendar-day boundaries of a report range.
 */
const IST_OFFSET_MS = 330 * 60_000;
const DAY_MS = 86_400_000;
const TIME_ZONE = 'Asia/Kolkata';

/** Midnight IST that starts the day `daysAgo` days before the IST day of `now`, as an instant. */
export function istDayStart(now: Date, daysAgo = 0): Date {
  const local = now.getTime() + IST_OFFSET_MS;
  return new Date(local - (local % DAY_MS) - daysAgo * DAY_MS - IST_OFFSET_MS);
}

const time = new Intl.DateTimeFormat('en-IN', {
  hour: 'numeric',
  minute: '2-digit',
  timeZone: TIME_ZONE,
});
const date = new Intl.DateTimeFormat('en-IN', {
  day: 'numeric',
  month: 'short',
  timeZone: TIME_ZONE,
});
const isoDate = new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE });

/** "9:42 pm" */
export function formatTime(at: string | Date): string {
  return time.format(new Date(at));
}

/** "1 Oct" */
export function formatDate(at: string | Date): string {
  return date.format(new Date(at));
}

/** "2026-10-01" (the IST calendar date; for exports). */
export function formatIsoDate(at: string | Date): string {
  return isoDate.format(new Date(at));
}

/** Minutes as the design writes them: 45 → "45m", 60 → "1h", 90 → "1h 30m". */
export function formatMinutes(minutes: number): string {
  const m = Math.round(minutes);
  const h = Math.floor(m / 60);
  const r = m % 60;
  return h ? (r ? `${h}h ${r}m` : `${h}h`) : `${r}m`;
}
