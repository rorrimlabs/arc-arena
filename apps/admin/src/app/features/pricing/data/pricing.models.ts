import { formatRupees } from '../../../shared/money/rupees.pipe';

export type DurationModel = 'hourly' | 'unit' | 'flat_hourly';
export type Band = 'standard' | 'happy';

/** A station type (server: activities) — what can be played and how it is billed. */
export interface StationType {
  readonly id: string;
  /** Stable business code (PS5, VR…), fixed once created. */
  readonly code: string;
  readonly name: string;
  /** Pads are tracked, and the price depends on how many are in use. */
  readonly usesControllers: boolean;
  readonly usesGames: boolean;
  readonly durationModel: DurationModel;
  readonly happyEligible: boolean;
  readonly sortOrder: number;
  readonly active: boolean;
  /** Stations offering it (not disabled). */
  readonly stations: number;
}

/** One price on the active rate card. `controllerCount` null = any number of players. */
export interface Rate {
  readonly activityCode: string;
  readonly band: string;
  readonly controllerCount: number | null;
  readonly unitMinutes: number;
  readonly pricePaise: number;
}

/** A window in minutes from IST midnight. */
export interface DayWindow {
  readonly start: number;
  readonly end: number;
}

/** ISO weekday '1' (Mon) … '7' (Sun) → window, or null (closed / no happy hour). */
export type WeekWindows = Readonly<Record<string, DayWindow | null>>;

export interface BusinessHours {
  readonly open: WeekWindows;
  readonly happy: WeekWindows;
}

export interface PricingData {
  readonly types: readonly StationType[];
  readonly rates: readonly Rate[];
  readonly hours: BusinessHours;
}

/** What the type dialog sends (activity.upsert). */
export interface TypeInput {
  readonly id: string;
  readonly code: string;
  readonly name: string;
  readonly usesControllers: boolean;
  readonly usesGames: boolean;
  readonly durationModel: DurationModel;
  readonly happyEligible: boolean;
  readonly sortOrder: number;
  readonly active: boolean;
}

/** A price to set (`pricePaise`) or remove (null) on the active card. */
export interface RateChange {
  readonly activityCode: string;
  readonly band: Band;
  readonly controllerCount: number | null;
  readonly unitMinutes: number;
  readonly pricePaise: number | null;
}

/** Physical pads per station: the engine prices 1–4 controllers. */
export const MAX_PADS = 4;

export const WEEKDAYS: readonly { readonly key: string; readonly short: string }[] = [
  { key: '1', short: 'Mon' },
  { key: '2', short: 'Tue' },
  { key: '3', short: 'Wed' },
  { key: '4', short: 'Thu' },
  { key: '5', short: 'Fri' },
  { key: '6', short: 'Sat' },
  { key: '7', short: 'Sun' },
];

export const BILLING_STYLES: readonly { readonly key: DurationModel; readonly label: string }[] = [
  { key: 'hourly', label: 'By the minute, hourly rate' },
  { key: 'unit', label: 'In fixed blocks (e.g. VR)' },
  { key: 'flat_hourly', label: 'Flat hourly, any group size' },
];

export function billingLabel(model: DurationModel): string {
  return BILLING_STYLES.find((b) => b.key === model)?.label ?? model;
}

export function typeIcon(t: Pick<StationType, 'usesControllers' | 'durationModel'>): string {
  if (t.usesControllers) return 'sports_esports';
  if (t.durationModel === 'unit') return 'view_in_ar';
  if (t.durationModel === 'flat_hourly') return 'weekend';
  return 'table_restaurant';
}

export function ratesFor(type: StationType, rates: readonly Rate[]): Rate[] {
  return rates.filter((r) => r.activityCode === type.code);
}

/** The rows a type is priced by: 1…4 controllers, or one "any number" row. */
export function rateRows(type: Pick<StationType, 'usesControllers'>): (number | null)[] {
  return type.usesControllers ? Array.from({ length: MAX_PADS }, (_, i) => i + 1) : [null];
}

export function findRate(
  rates: readonly Rate[],
  code: string,
  band: string,
  controllers: number | null,
): Rate | undefined {
  return rates.find(
    (r) => r.activityCode === code && r.band === band && r.controllerCount === controllers,
  );
}

/** Block length used by a type's rates (60 for hourly types). */
export function unitMinutesOf(type: StationType, rates: readonly Rate[]): number {
  return ratesFor(type, rates)[0]?.unitMinutes ?? (type.durationModel === 'unit' ? 30 : 60);
}

/** Most controllers with a standard price (players a station of this type takes). */
export function maxPlayers(type: StationType, rates: readonly Rate[]): number {
  if (!type.usesControllers) return 0;
  return Math.max(
    0,
    ...ratesFor(type, rates)
      .filter((r) => r.band === 'standard' && r.controllerCount != null)
      .map((r) => r.controllerCount as number),
  );
}

/** The list's headline price: the cheapest standard rate, per its block. */
export function headlinePrice(
  type: StationType,
  rates: readonly Rate[],
): { price: string; per: string } | null {
  const standard = ratesFor(type, rates).filter((r) => r.band === 'standard');
  if (!standard.length) return null;
  const cheapest = standard.reduce((a, b) => (b.pricePaise < a.pricePaise ? b : a));
  const per = cheapest.unitMinutes === 60 ? 'per hour' : `per ${cheapest.unitMinutes} min`;
  return { price: formatRupees(cheapest.pricePaise), per };
}

/** "2:00 pm" from minutes after IST midnight (1440 = midnight). */
export function formatMinuteOfDay(minutes: number): string {
  const m = minutes % 1440;
  const h = Math.floor(m / 60);
  const mm = m % 60;
  const h12 = h % 12 || 12;
  return `${h12}:${String(mm).padStart(2, '0')} ${h < 12 ? 'am' : 'pm'}`;
}

/** "14:00" for <input type="time">. */
export function toTimeInput(minutes: number): string {
  const m = minutes % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

export function fromTimeInput(value: string): number | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const minutes = Number(match[1]) * 60 + Number(match[2]);
  return minutes >= 0 && minutes < 1440 ? minutes : null;
}

/** "Tue–Fri · 2:00–5:00 pm", grouping consecutive days with the same window. */
export function summarizeWindows(windows: WeekWindows): string {
  const parts: string[] = [];
  let i = 0;
  while (i < WEEKDAYS.length) {
    const w = windows[WEEKDAYS[i].key];
    if (!w) {
      i++;
      continue;
    }
    let j = i;
    while (j + 1 < WEEKDAYS.length) {
      const next = windows[WEEKDAYS[j + 1].key];
      if (!next || next.start !== w.start || next.end !== w.end) break;
      j++;
    }
    const days = i === j ? WEEKDAYS[i].short : `${WEEKDAYS[i].short}–${WEEKDAYS[j].short}`;
    parts.push(`${days} · ${formatMinuteOfDay(w.start)}–${formatMinuteOfDay(w.end)}`);
    i = j + 1;
  }
  return parts.join(', ');
}

/** A code suggestion from a name: "PlayStation 5" → "PLAYSTATION5" (12 max). */
export function suggestCode(name: string): string {
  return name
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '')
    .slice(0, 12);
}
