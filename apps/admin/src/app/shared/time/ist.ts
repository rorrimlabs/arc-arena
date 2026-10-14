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

/**
 * Midnight IST that starts the calendar day `iso` ("2026-10-01"), as an instant; null when `iso`
 * is not a real date in that form.
 */
export function istDayStartOf(iso: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return null;
  const [y, mo, d] = [+m[1], +m[2], +m[3]];
  const utc = Date.UTC(y, mo - 1, d);
  const check = new Date(utc);
  if (check.getUTCFullYear() !== y || check.getUTCMonth() !== mo - 1 || check.getUTCDate() !== d) {
    return null;
  }
  return new Date(utc - IST_OFFSET_MS);
}

/** The IST calendar date `days` after `iso` ("2026-10-31", 1 → "2026-11-01"). */
export function addDays(iso: string, days: number): string {
  const start = istDayStartOf(iso);
  if (!start) throw new Error(`not a date: ${iso}`);
  return formatIsoDate(new Date(start.getTime() + days * DAY_MS));
}

/** Whole IST calendar days from `first` to `last` ("2026-10-01" → "2026-10-03" is 2). */
export function daysBetween(first: string, last: string): number {
  const a = istDayStartOf(first);
  const b = istDayStartOf(last);
  if (!a || !b) return Number.NaN;
  return Math.round((b.getTime() - a.getTime()) / DAY_MS);
}

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

const hm = new Intl.DateTimeFormat('en-GB', {
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
  timeZone: TIME_ZONE,
});

/** "21:42" (IST, 24-hour; for exports). */
export function formatHm(at: string | Date): string {
  return hm.format(new Date(at));
}

/** Minutes as the design writes them: 45 → "45m", 60 → "1h", 90 → "1h 30m". */
export function formatMinutes(minutes: number): string {
  const m = Math.round(minutes);
  const h = Math.floor(m / 60);
  const r = m % 60;
  return h ? (r ? `${h}h ${r}m` : `${h}h`) : `${r}m`;
}
