import {
  Charge,
  Customer,
  Game,
  LiveStation,
  Play,
  Visit,
  minutesLeft,
  playMinutes,
} from '../../../core/floor/floor.models';
import { formatRupees } from '../../../shared/money/rupees.pipe';
import { PillTone } from '../../../shared/status-pill/status-pill';
import { formatDate, formatTime, istDayStart } from '../../../shared/time/ist';
import { Rate, StationType, headlinePrice, typeIcon } from '../../pricing/data/pricing.models';
import { billRef } from '../../sales/data/sale.models';

export const STATE_TONE: Readonly<Record<LiveStation['state'], PillTone>> = {
  playing: 'primary',
  free: 'info',
  oos: 'danger',
};

/** The station types (activities) a station offers, in the price list's order. */
export function typesOf(codes: readonly string[], types: readonly StationType[]): StationType[] {
  return types.filter((t) => codes.includes(t.code));
}

export function typeLabel(codes: readonly string[], types: readonly StationType[]): string {
  const named = typesOf(codes, types).map((t) => t.name);
  return named.length ? named.join(', ') : codes.join(', ') || 'No type';
}

export function stationIcon(codes: readonly string[], types: readonly StationType[]): string {
  const t = typesOf(codes, types)[0];
  return t ? typeIcon(t) : 'sports_esports';
}

/** "PlayStation 5 · ₹120 / hr" (the first type's cheapest standard price). */
export function rateLine(
  codes: readonly string[],
  types: readonly StationType[],
  rates: readonly Rate[],
): string {
  const t = typesOf(codes, types)[0];
  const price = t ? headlinePrice(t, rates) : null;
  const label = typeLabel(codes, types);
  if (!price) return `${label} · no price yet`;
  const per = price.per === 'per hour' ? '/ hr' : price.per.replace('per ', '/ ');
  return `${label} · ${price.price} ${per}`;
}

/** "18m left", "Ends now" or "6m over". */
export function leftLabel(endsAt: string, now: Date): string {
  const left = minutesLeft(endsAt, now);
  if (left > 0) return `${left}m left`;
  return left === 0 ? 'Ends now' : `${-left}m over`;
}

/** The list row's subtitle: what is on, or the type. */
export function stationSubtitle(
  live: LiveStation,
  games: ReadonlyMap<string, Game>,
  types: readonly StationType[],
  now: Date,
): string {
  if (live.state === 'playing') {
    const game = live.gameId ? games.get(live.gameId)?.name : null;
    return [game ?? 'Playing', live.endsAt ? leftLabel(live.endsAt, now) : '']
      .filter(Boolean)
      .join(' · ');
  }
  return typeLabel(live.station.activityCodes, types);
}

export interface StationStats {
  readonly billedToday: number;
  readonly sessionsToday: number;
  readonly minutes30: number;
  readonly billed30: number;
}

/** Billed amounts (charges) and play on one station, today and over the 30-day window. */
export function stationStats(
  stationId: string,
  plays: readonly Play[],
  charges: readonly Charge[],
  now: Date,
): StationStats {
  const today = istDayStart(now).getTime();
  const since30 = istDayStart(now, 29).getTime();
  const mine = plays.filter((p) => p.resourceId === stationId && p.billStatus !== 'voided');
  const billed = charges.filter((c) => c.resourceId === stationId);
  return {
    billedToday: billed
      .filter((c) => Date.parse(c.segmentStart) >= today)
      .reduce((n, c) => n + c.amountPaise, 0),
    sessionsToday: new Set(
      mine.filter((p) => Date.parse(p.startedAt) >= today).map((p) => p.billId),
    ).size,
    minutes30: mine
      .filter((p) => Date.parse(p.startedAt) >= since30)
      .reduce((n, p) => n + playMinutes(p, now), 0),
    billed30: billed.reduce((n, c) => n + c.amountPaise, 0),
  };
}

export interface BillLine {
  readonly billId: string;
  readonly title: string;
  readonly subtitle: string;
  readonly value: string;
}

/**
 * A station's or member's latest bills from the play history, newest first: who (or where),
 * "S-3F9A2C · 1 Oct, 6:40 pm · game", and the bill (or its state).
 */
export function billLines(
  plays: readonly Play[],
  visits: ReadonlyMap<string, Visit>,
  customers: ReadonlyMap<string, Customer>,
  games: ReadonlyMap<string, Game>,
  title: (p: Play, game: string | null) => string,
  { limit = 6, gameInSubtitle = true } = {},
): BillLine[] {
  const seen = new Set<string>();
  return [...plays]
    .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt))
    .filter((p) => !seen.has(p.billId) && seen.add(p.billId))
    .slice(0, limit)
    .map((p) => {
      const v = visits.get(p.billId);
      const game = p.gameId ? games.get(p.gameId)?.name : null;
      const when = `${formatDate(p.startedAt)}, ${formatTime(p.startedAt)}`;
      const value =
        p.billStatus === 'voided'
          ? 'Void'
          : p.billStatus === 'active'
            ? 'Playing'
            : v?.billedPaise != null
              ? formatRupees(v.billedPaise)
              : '—';
      return {
        billId: p.billId,
        title: title(p, game ?? null),
        subtitle: [billRef(p.kind, p.billId), when, gameInSubtitle ? game : null]
          .filter(Boolean)
          .join(' · '),
        value,
      };
    });
}

/** A member's name, or Guest for a walk-in (guests are not in the members list). */
export function customerName(id: string, customers: ReadonlyMap<string, Customer>): string {
  return customers.get(id)?.name ?? 'Guest';
}
