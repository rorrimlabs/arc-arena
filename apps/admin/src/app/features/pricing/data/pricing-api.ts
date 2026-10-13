import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/arena/arena-api';
import { Supabase } from '../../../core/supabase/supabase';
import { SyncOp, pushOps } from '../../../core/sync/push-ops';
import {
  BusinessHours,
  DurationModel,
  PricingData,
  Rate,
  RateChange,
  TypeInput,
  WeekWindows,
} from './pricing.models';

/**
 * Station types, rates and happy hour: read through arena_pricing() (owner level), written as
 * activity.upsert / rate.upsert / rate.delete / settings.save ops through sync_push. Tests
 * provide SamplePricingApi.
 */
@Service({ factory: () => new SupabasePricingApi() })
export abstract class PricingApi {
  abstract load(arenaId: string): Promise<PricingData>;
  abstract saveType(arenaId: string, type: TypeInput): Promise<void>;
  /** Deletes a never-used type with its prices, or turns a used one off (past bills keep it). */
  abstract removeType(arenaId: string, id: string): Promise<'deleted' | 'retired'>;
  abstract saveRates(arenaId: string, changes: readonly RateChange[]): Promise<void>;
  abstract saveHours(arenaId: string, hours: BusinessHours): Promise<void>;
}

export const PRICING_MESSAGES: Readonly<Record<string, string>> = {
  invalid_code: 'Use up to 12 letters, digits or _ for the code',
  invalid_name: 'Enter a name of up to 40 characters',
  duplicate: 'Another type already uses that code',
  code_locked: 'A type keeps its code once created',
  activity_busy: 'A session of this type is running · end it on the floor first',
  activity_missing: 'That type is gone. Refresh',
  activity_has_stations: 'Stations still offer this type · remove them first',
  setting_not_shared: 'That setting cannot be saved here',
};

export function typeOps(type: TypeInput): SyncOp[] {
  return [
    {
      kind: 'activity.upsert',
      payload: {
        id: type.id,
        code: type.code,
        name: type.name,
        uses_controllers: type.usesControllers,
        uses_games: type.usesGames,
        duration_model: type.durationModel,
        happy_hour_eligible: type.happyEligible,
        sort_order: type.sortOrder,
        active: type.active,
      },
    },
  ];
}

export function rateOps(changes: readonly RateChange[]): SyncOp[] {
  return changes.map((c) =>
    c.pricePaise == null
      ? {
          kind: 'rate.delete',
          payload: {
            activity_code: c.activityCode,
            band: c.band,
            controller_count: c.controllerCount,
          },
        }
      : {
          kind: 'rate.upsert',
          payload: {
            activity_code: c.activityCode,
            band: c.band,
            controller_count: c.controllerCount,
            unit_minutes: c.unitMinutes,
            price_paise: c.pricePaise,
          },
        },
  );
}

function toWeek(v: unknown): WeekWindows {
  const out: Record<string, { start: number; end: number } | null> = {};
  for (const [day, w] of Object.entries((v as Record<string, unknown>) ?? {})) {
    const win = w as { start?: number; end?: number } | null;
    out[day] =
      win && win.start != null && win.end != null ? { start: +win.start, end: +win.end } : null;
  }
  return out;
}

class SupabasePricingApi extends PricingApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<PricingData> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('arena_pricing', { p_arena: arenaId });
    if (error) throw dbError(error);
    const d = data as {
      types: Record<string, unknown>[];
      rates: Record<string, unknown>[];
      hours: { open?: unknown; happy?: unknown };
    };
    return {
      types: d.types.map((t) => ({
        id: String(t['id']),
        code: String(t['code']),
        name: String(t['name']),
        usesControllers: t['uses_controllers'] === true,
        usesGames: t['uses_games'] === true,
        durationModel: (t['duration_model'] as DurationModel) ?? 'hourly',
        happyEligible: t['happy_hour_eligible'] !== false,
        sortOrder: Number(t['sort_order'] ?? 0),
        active: t['active'] !== false,
        stations: Number(t['stations'] ?? 0),
      })),
      rates: d.rates.map((r): Rate => ({
        activityCode: String(r['activity_code']),
        band: String(r['band']),
        controllerCount: r['controller_count'] == null ? null : Number(r['controller_count']),
        unitMinutes: Number(r['unit_minutes'] ?? 60),
        pricePaise: Number(r['price_paise']),
      })),
      hours: { open: toWeek(d.hours?.open), happy: toWeek(d.hours?.happy) },
    };
  }

  async saveType(arenaId: string, type: TypeInput): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, typeOps(type), PRICING_MESSAGES);
  }

  async removeType(arenaId: string, id: string): Promise<'deleted' | 'retired'> {
    const [result] = await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'activity.remove', payload: { id } }],
      PRICING_MESSAGES,
    );
    return result?.['removed'] === 'retired' ? 'retired' : 'deleted';
  }

  async saveRates(arenaId: string, changes: readonly RateChange[]): Promise<void> {
    await pushOps(await this.supabase.client(), arenaId, rateOps(changes), PRICING_MESSAGES);
  }

  async saveHours(arenaId: string, hours: BusinessHours): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [{ kind: 'settings.save', payload: { key: 'business_hours', json: hours } }],
      PRICING_MESSAGES,
    );
  }
}
