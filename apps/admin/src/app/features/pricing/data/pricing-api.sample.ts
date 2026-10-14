import { AppError } from '../../../core/auth/auth-api';
import { BillingPolicy, DEFAULT_POLICY } from './billing-policy';
import { PRICING_MESSAGES, PricingApi, holidayOps, policyOps } from './pricing-api';
import {
  BusinessHours,
  Holiday,
  PricingData,
  Rate,
  RateChange,
  StationType,
  TypeInput,
} from './pricing.models';

const OPEN = { start: 840, end: 1380 };
const HAPPY = { start: 840, end: 1020 };

/** The server's default hours (open Tue–Sun 2–11 pm, happy Tue–Fri 2–5 pm). */
export function defaultHours(): BusinessHours {
  return {
    open: { '1': null, '2': OPEN, '3': OPEN, '4': OPEN, '5': OPEN, '6': OPEN, '7': OPEN },
    happy: { '1': null, '2': HAPPY, '3': HAPPY, '4': HAPPY, '5': HAPPY, '6': null, '7': null },
  };
}

function type(id: string, code: string, name: string, o: Partial<StationType> = {}): StationType {
  return {
    id,
    code,
    name,
    usesControllers: false,
    usesGames: false,
    durationModel: 'hourly',
    happyEligible: true,
    sortOrder: 0,
    active: true,
    stations: 0,
    ...o,
  };
}

/** A deterministic price list (paise); changes are applied in memory like the server would. */
export class SamplePricingApi extends PricingApi {
  types: StationType[];
  rates: Rate[];
  hours: BusinessHours = defaultHours();
  /** Ordered by day; one past (Independence Day) and two to come, for a sample "now" in Oct 2026. */
  holidays: Holiday[];
  policy: BillingPolicy = DEFAULT_POLICY;
  /** Every holiday / policy write, in order, as `kind` + payload (what sync_push would get). */
  readonly ops: { kind: string; payload: unknown }[] = [];
  /** Set to make the next call fail with this code. */
  failNext: string | null = null;

  constructor(empty = false) {
    super();
    this.types = empty
      ? []
      : [
          type('t-ps5', 'PS5', 'PlayStation 5', {
            usesControllers: true,
            usesGames: true,
            stations: 4,
          }),
          type('t-vr', 'VR', 'VR', {
            usesGames: true,
            durationModel: 'unit',
            happyEligible: false,
            stations: 1,
            sortOrder: 1,
          }),
          type('t-pool', 'POOL', 'Pool', { stations: 0, sortOrder: 2, active: false }),
        ];
    const ps5 = (cc: number, standard: number, happy: number): Rate[] => [
      {
        activityCode: 'PS5',
        band: 'standard',
        controllerCount: cc,
        unitMinutes: 60,
        pricePaise: standard,
      },
      {
        activityCode: 'PS5',
        band: 'happy',
        controllerCount: cc,
        unitMinutes: 60,
        pricePaise: happy,
      },
    ];
    this.holidays = empty
      ? []
      : [
          { day: '2026-08-15', name: 'Independence Day', closed: false },
          { day: '2026-11-08', name: 'Diwali', closed: false },
          { day: '2026-12-25', name: 'Christmas', closed: true },
        ];
    this.rates = empty
      ? []
      : [
          ...ps5(1, 15000, 12000),
          ...ps5(2, 22000, 18000),
          {
            activityCode: 'VR',
            band: 'standard',
            controllerCount: null,
            unitMinutes: 30,
            pricePaise: 20000,
          },
        ];
  }

  async load(): Promise<PricingData> {
    this.fail();
    return {
      types: [...this.types],
      rates: [...this.rates],
      hours: this.hours,
      holidays: [...this.holidays],
      policy: this.policy,
    };
  }

  async saveType(_arenaId: string, t: TypeInput): Promise<void> {
    this.fail();
    const code = t.code.trim().toUpperCase();
    if (!/^[A-Z0-9_]{1,12}$/.test(code)) throw this.error('invalid_code');
    const existing = this.types.find((x) => x.id === t.id);
    if (existing && existing.code !== code) throw this.error('code_locked');
    if (this.types.some((x) => x.id !== t.id && x.code === code)) throw this.error('duplicate');
    const next: StationType = { ...t, code, stations: existing?.stations ?? 0 };
    this.types = existing
      ? this.types.map((x) => (x.id === t.id ? next : x))
      : [...this.types, next];
  }

  /** Types with `used` ids have history: they are turned off instead of deleted. */
  used = new Set<string>(['t-ps5']);

  async removeType(_arenaId: string, id: string): Promise<'deleted' | 'retired'> {
    this.fail();
    const t = this.types.find((x) => x.id === id);
    if (!t) return 'deleted';
    if (t.stations > 0) throw this.error('activity_has_stations');
    if (this.used.has(id)) {
      this.types = this.types.map((x) => (x.id === id ? { ...x, active: false } : x));
      return 'retired';
    }
    this.types = this.types.filter((x) => x.id !== id);
    this.rates = this.rates.filter((r) => r.activityCode !== t.code);
    return 'deleted';
  }

  async saveRates(_arenaId: string, changes: readonly RateChange[]): Promise<void> {
    this.fail();
    for (const c of changes) {
      const same = (r: Rate) =>
        r.activityCode === c.activityCode &&
        r.band === c.band &&
        r.controllerCount === c.controllerCount;
      this.rates = this.rates.filter((r) => !same(r));
      if (c.pricePaise != null) {
        this.rates.push({ ...c, pricePaise: c.pricePaise });
      }
    }
  }

  async saveHours(_arenaId: string, hours: BusinessHours): Promise<void> {
    this.fail();
    this.hours = hours;
  }

  /** Like the server: an upsert by day, then the old day's delete when the holiday moved. */
  async saveHoliday(_arenaId: string, holiday: Holiday, replacing?: string): Promise<void> {
    this.fail();
    for (const op of holidayOps(holiday, replacing)) {
      this.ops.push(op);
      const day = String(op.payload['day']);
      this.holidays = this.holidays.filter((h) => h.day !== day);
      if (op.kind === 'holiday.upsert') this.holidays.push({ ...holiday });
    }
    this.holidays.sort((a, b) => a.day.localeCompare(b.day));
  }

  async deleteHoliday(_arenaId: string, day: string): Promise<void> {
    this.fail();
    this.ops.push({ kind: 'holiday.delete', payload: { day } });
    this.holidays = this.holidays.filter((h) => h.day !== day);
  }

  async savePolicy(_arenaId: string, policy: BillingPolicy): Promise<void> {
    this.fail();
    this.ops.push(...policyOps(policy));
    this.policy = { ...policy };
  }

  private error(code: string): AppError {
    return new AppError(code, PRICING_MESSAGES[code] ?? code);
  }

  private fail(): void {
    const code = this.failNext;
    if (!code) return;
    this.failNext = null;
    throw new AppError(
      code,
      code === 'forbidden' ? 'You need the Settings permission for that' : code,
    );
  }
}
