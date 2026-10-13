import { Service, inject, signal } from '@angular/core';
import { ArenaContext } from '../../../core/arena/arena-context';
import { toAppError } from '../../../core/auth/auth-api';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import { PayMethod } from '../../sales/data/sale.models';

/**
 * What the floor app offers staff (settings key `floor_options`, validated by the server's
 * _floor_options): payment methods, session start durations and the end-of-session warning.
 * Not part of pricing; the floor app reads it after its next sync.
 */
export interface FloorOptions {
  readonly paymentMethods: readonly PayMethod[];
  /** Minutes, ascending. */
  readonly startPresets: readonly number[];
  readonly warnMinutes: number;
}

/** The floor app's behaviour before an arena saves any options. */
export const DEFAULT_FLOOR_OPTIONS: FloorOptions = {
  paymentMethods: ['cash', 'upi', 'card', 'other'],
  startPresets: [30, 60, 90, 120],
  warnMinutes: 5,
};

/** The design's choices on the Sessions screen. */
export const PRESET_CHOICES = [15, 30, 45, 60, 90, 120, 180] as const;
export const WARN_CHOICES = [5, 10, 15] as const;

const METHOD_ORDER: readonly PayMethod[] = ['cash', 'upi', 'card', 'other'];

export const FLOOR_OPTION_MESSAGES: Readonly<Record<string, string>> = {
  invalid_floor_options: 'Check the options: keep at least one payment method and one time option',
  setting_not_shared: 'This server does not accept floor options yet. Apply the latest migrations',
};

export function parseFloorOptions(json: unknown): FloorOptions {
  const j = (json ?? {}) as Record<string, unknown>;
  const methods = METHOD_ORDER.filter((m) =>
    ((j['payment_methods'] as unknown[]) ?? []).includes(m),
  );
  const presets = [...new Set(((j['start_presets'] as unknown[]) ?? []).map(Number))]
    .filter((n) => Number.isInteger(n) && n >= 5 && n <= 720)
    .sort((a, b) => a - b);
  const warn = Number(j['warn_minutes']);
  return {
    paymentMethods: methods.length ? methods : DEFAULT_FLOOR_OPTIONS.paymentMethods,
    startPresets: presets.length ? presets : DEFAULT_FLOOR_OPTIONS.startPresets,
    warnMinutes:
      Number.isInteger(warn) && warn >= 1 && warn <= 30 ? warn : DEFAULT_FLOOR_OPTIONS.warnMinutes,
  };
}

/** Reads the setting row (RLS) and saves it as a settings.save op through sync_push. */
@Service({ factory: () => new SupabaseFloorOptionsApi() })
export abstract class FloorOptionsApi {
  /** The saved options, or null when the arena has never saved any. */
  abstract load(arenaId: string): Promise<FloorOptions | null>;
  abstract save(arenaId: string, options: FloorOptions): Promise<void>;
}

class SupabaseFloorOptionsApi extends FloorOptionsApi {
  private readonly supabase = inject(Supabase);

  async load(arenaId: string): Promise<FloorOptions | null> {
    const client = await this.supabase.client();
    const { data, error } = await client
      .from('settings')
      .select('json')
      .eq('arena_id', arenaId)
      .eq('key', 'floor_options')
      .maybeSingle();
    if (error) throw dbError(error);
    return data ? parseFloorOptions((data as { json: unknown }).json) : null;
  }

  async save(arenaId: string, options: FloorOptions): Promise<void> {
    await pushOps(
      await this.supabase.client(),
      arenaId,
      [
        {
          kind: 'settings.save',
          payload: {
            key: 'floor_options',
            json: {
              payment_methods: options.paymentMethods,
              start_presets: options.startPresets,
              warn_minutes: options.warnMinutes,
            },
          },
        },
      ],
      FLOOR_OPTION_MESSAGES,
    );
  }
}

/** The current arena's floor options; a save goes to the server first, then reloads. */
@Service()
export class FloorOptionsStore {
  private readonly api = inject(FloorOptionsApi);
  private readonly arena = inject(ArenaContext);

  /** What the floor app uses now (the defaults until the arena saves its own). */
  readonly options = signal<FloorOptions | null>(null);
  /** False until the arena has saved options (the floor app is on its defaults). */
  readonly saved = signal(false);
  readonly loading = signal(false);
  readonly loadError = signal('');
  private loadedArena: string | null = null;

  async load(force = false): Promise<void> {
    const arenaId = this.arena.current().id;
    if (!arenaId || (!force && this.loadedArena === arenaId)) return;
    if (this.loadedArena !== arenaId) this.options.set(null);
    this.loading.set(true);
    this.loadError.set('');
    try {
      const found = await this.api.load(arenaId);
      this.options.set(found ?? DEFAULT_FLOOR_OPTIONS);
      this.saved.set(!!found);
      this.loadedArena = arenaId;
    } catch (e) {
      this.loadError.set(toAppError(e).message);
    } finally {
      this.loading.set(false);
    }
  }

  async save(options: FloorOptions): Promise<void> {
    await this.api.save(this.arena.current().id, options);
    await this.load(true);
  }
}
