import { AppError } from '../../../core/auth/auth-api';
import {
  FLOOR_OPTION_MESSAGES,
  FloorOptions,
  FloorOptionsApi,
  parseFloorOptions,
} from './floor-options';

/** In-memory floor options for tests; the arena starts on the floor app's defaults. */
export class SampleFloorOptionsApi extends FloorOptionsApi {
  saved: FloorOptions | null = null;
  /** Every save, as the payload json the server would receive. */
  readonly writes: Record<string, unknown>[] = [];

  async load(): Promise<FloorOptions | null> {
    return this.saved;
  }

  async save(_arenaId: string, o: FloorOptions): Promise<void> {
    if (!o.paymentMethods.length || !o.startPresets.length) {
      throw new AppError('invalid_floor_options', FLOOR_OPTION_MESSAGES['invalid_floor_options']);
    }
    const json = {
      payment_methods: o.paymentMethods,
      start_presets: o.startPresets,
      warn_minutes: o.warnMinutes,
    };
    this.writes.push(json);
    this.saved = parseFloorOptions(json);
  }
}
