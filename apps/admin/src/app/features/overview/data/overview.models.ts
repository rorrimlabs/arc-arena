import { Charge } from '../../../core/floor/floor.models';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { formatDate, formatMinutes, istDayStart } from '../../../shared/time/ist';
import { WeekWindows } from '../../pricing/data/pricing.models';
import { Bill, PayMethod, playedMinutes, summarize } from '../../sales/data/sale.models';

export type Period = 'today' | '7d' | '30d' | '12m';

export const PERIODS: readonly { readonly key: Period; readonly label: string }[] = [
  { key: 'today', label: 'Today' },
  { key: '7d', label: '7d' },
  { key: '30d', label: '30d' },
  { key: '12m', label: '12m' },
];

export function asPeriod(value: string | undefined): Period {
  return PERIODS.some((p) => p.key === value) ? (value as Period) : 'today';
}

const IST_OFFSET_MS = 330 * 60_000;
const DAY_MS = 86_400_000;

/** IST calendar parts of an instant. */
function ist(at: Date) {
  const d = new Date(at.getTime() + IST_OFFSET_MS);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth(), day: d.getUTCDate(), h: d.getUTCHours() };
}

/** Midnight IST starting the given IST calendar month (month may be out of 0–11). */
function istMonthStart(y: number, m: number): Date {
  return new Date(Date.UTC(y, m, 1) - IST_OFFSET_MS);
}

export interface PeriodRange {
  readonly from: Date;
  readonly to: Date;
  readonly prevFrom: Date;
  readonly prevTo: Date;
  /** "Today so far", "Last 7 days"… */
  readonly label: string;
  /** "vs yesterday", "vs previous 7 days"… */
  readonly compare: string;
}

/** The period and the one before it, as [from, to) instants on IST calendar boundaries. */
export function periodRange(period: Period, now: Date): PeriodRange {
  const tomorrow = istDayStart(now, -1);
  switch (period) {
    case 'today':
      return {
        from: istDayStart(now),
        to: tomorrow,
        prevFrom: istDayStart(now, 1),
        prevTo: istDayStart(now),
        label: 'Today so far',
        compare: 'vs yesterday',
      };
    case '7d':
    case '30d': {
      const n = period === '7d' ? 7 : 30;
      return {
        from: istDayStart(now, n - 1),
        to: tomorrow,
        prevFrom: istDayStart(now, 2 * n - 1),
        prevTo: istDayStart(now, n - 1),
        label: `Last ${n} days`,
        compare: `vs previous ${n} days`,
      };
    }
    case '12m': {
      const { y, m } = ist(now);
      return {
        from: istMonthStart(y, m - 11),
        to: tomorrow,
        prevFrom: istMonthStart(y - 1, m - 11),
        prevTo: istMonthStart(y, m - 11),
        label: 'Last 12 months',
        compare: 'vs previous year',
      };
    }
  }
}

/** [from, to) split into spans the sales API accepts (at most `maxDays` each). */
export function chunks(from: Date, to: Date, maxDays = 90): { from: Date; to: Date }[] {
  const out: { from: Date; to: Date }[] = [];
  for (let t = from.getTime(); t < to.getTime(); t += maxDays * DAY_MS) {
    out.push({ from: new Date(t), to: new Date(Math.min(to.getTime(), t + maxDays * DAY_MS)) });
  }
  return out;
}

export interface Totals {
  readonly takingsPaise: number;
  readonly bills: number;
  readonly minutes: number;
  readonly averagePaise: number;
}

/** Takings are what was collected on bills that were not voided (as on the Sales screen). */
export function totals(bills: readonly Bill[]): Totals {
  const live = bills.filter((b) => !b.voided);
  const s = summarize(live);
  return {
    takingsPaise: s.takingsPaise,
    bills: s.count,
    minutes: live.reduce((n, b) => n + playedMinutes(b), 0),
    averagePaise: s.count ? s.takingsPaise / s.count : 0,
  };
}

/** "+12%" / "−8%" with its tone, or "—" when there is nothing to compare with. */
export function delta(now: number, before: number): { label: string; up: boolean | null } {
  if (!before) return { label: '—', up: null };
  const p = Math.round(((now - before) / before) * 100);
  return { label: `${p >= 0 ? '+' : '−'}${Math.abs(p)}%`, up: p >= 0 };
}

export interface Bar {
  readonly paise: number;
  readonly label: string;
  readonly tip: string;
  /** Still to come today (drawn faint). */
  readonly future: boolean;
}

/** Takings bars: by hour today (opening hours, widened to any bill), by day, or by month. */
export function takingsBars(
  period: Period,
  range: PeriodRange,
  bills: readonly Bill[],
  open: WeekWindows | null,
  now: Date,
): Bar[] {
  const live = bills.filter((b) => !b.voided);
  if (period === 'today') {
    const weekday = String(((new Date(now.getTime() + IST_OFFSET_MS).getUTCDay() + 6) % 7) + 1);
    const w = open?.[weekday];
    const hours = live.map((b) => ist(new Date(b.at)).h);
    const first = Math.min(w ? Math.floor(w.start / 60) : 10, ...hours);
    const last = Math.max(w ? Math.ceil(w.end / 60) - 1 : 23, ...hours);
    const nowHour = ist(now).h;
    return Array.from({ length: last - first + 1 }, (_, k) => {
      const h = first + k;
      const paise = live
        .filter((b) => ist(new Date(b.at)).h === h)
        .reduce((n, b) => n + b.paidPaise, 0);
      const label = hourLabel(h);
      return {
        paise,
        label: k % 2 ? '' : label,
        tip: `${label} · ${formatRupees(paise)}`,
        future: h > nowHour,
      };
    });
  }
  if (period === '12m') {
    const { y, m } = ist(range.from);
    return Array.from({ length: 12 }, (_, k) => {
      const start = istMonthStart(y, m + k).getTime();
      const end = istMonthStart(y, m + k + 1).getTime();
      const paise = live
        .filter((b) => Date.parse(b.at) >= start && Date.parse(b.at) < end)
        .reduce((n, b) => n + b.paidPaise, 0);
      const label = new Intl.DateTimeFormat('en-IN', { month: 'short', timeZone: 'UTC' }).format(
        new Date(Date.UTC(y, m + k, 1)),
      );
      return { paise, label, tip: `${label} · ${formatRupees(paise)}`, future: false };
    });
  }
  const n = period === '7d' ? 7 : 30;
  return Array.from({ length: n }, (_, k) => {
    const daysAgo = n - 1 - k;
    const start = istDayStart(now, daysAgo);
    const end = istDayStart(now, daysAgo - 1).getTime();
    const paise = live
      .filter((b) => Date.parse(b.at) >= start.getTime() && Date.parse(b.at) < end)
      .reduce((n2, b) => n2 + b.paidPaise, 0);
    const label =
      n === 7
        ? daysAgo
          ? new Intl.DateTimeFormat('en-IN', { weekday: 'short', timeZone: 'Asia/Kolkata' }).format(
              start,
            )
          : 'Today'
        : daysAgo % 5 === 0
          ? String(ist(start).day)
          : '';
    return { paise, label, tip: `${formatDate(start)} · ${formatRupees(paise)}`, future: false };
  });
}

function hourLabel(h: number): string {
  return `${h % 12 || 12}${h >= 12 && h < 24 ? 'pm' : 'am'}`;
}

/** The chart's top gridline (a round number above the tallest bar) and its labels. */
export function chartScale(bars: readonly Bar[]): { topPaise: number; top: string; mid: string } {
  const max = Math.max(100, ...bars.map((b) => b.paise));
  const unit = max > 2_000_000 ? 1_000_000 : 100_000;
  const top = Math.ceil(max / unit) * unit;
  return { topPaise: top, top: compact(top), mid: compact(top / 2) };
}

/** ₹48k, ₹1.2L */
function compact(paise: number): string {
  const r = paise / 100;
  return r >= 100_000 ? `₹${+(r / 100_000).toFixed(1)}L` : `₹${+(r / 1000).toFixed(1)}k`;
}

export interface MethodRow {
  readonly method: PayMethod;
  readonly label: string;
  readonly paise: number;
  readonly bills: number;
}

/** UPI and Cash always; Card and Other only when used. */
export function paymentRows(bills: readonly Bill[]): MethodRow[] {
  const live = bills.filter((b) => !b.voided);
  const s = summarize(live);
  const rows: MethodRow[] = (
    [
      ['upi', 'UPI'],
      ['cash', 'Cash'],
      ['card', 'Card'],
      ['other', 'Other'],
    ] as [PayMethod, string][]
  ).map(([method, label]) => ({
    method,
    label,
    paise: s.byMethod[method],
    bills: live.filter((b) => (b.methods[method] ?? 0) > 0).length,
  }));
  return rows.filter((r) => r.method === 'upi' || r.method === 'cash' || r.paise);
}

/** Billed amount per station type code. */
export function billedByType(charges: readonly Charge[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const c of charges) out.set(c.activityCode, (out.get(c.activityCode) ?? 0) + c.amountPaise);
  return out;
}

/** Most-played games by bill time (a bill's time is shared between its games). */
export function topGames(bills: readonly Bill[], limit = 5): { name: string; time: string }[] {
  const by = new Map<string, number>();
  for (const b of bills) {
    if (b.voided || !b.games.length) continue;
    const share = playedMinutes(b) / b.games.length;
    for (const g of b.games) by.set(g, (by.get(g) ?? 0) + share);
  }
  return [...by]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, minutes]) => ({ name, time: formatMinutes(minutes) }));
}

/** Bills and takings by the staff member who started them. */
export function byStaff(bills: readonly Bill[]): { name: string; bills: number; paise: number }[] {
  const by = new Map<string, { bills: number; paise: number }>();
  for (const b of bills) {
    if (b.voided || !b.startedBy) continue;
    const s = by.get(b.startedBy) ?? { bills: 0, paise: 0 };
    s.bills++;
    s.paise += b.paidPaise;
    by.set(b.startedBy, s);
  }
  return [...by].map(([name, s]) => ({ name, ...s })).sort((a, b) => b.paise - a.paise);
}
